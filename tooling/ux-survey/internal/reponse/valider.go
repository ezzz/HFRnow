package reponse

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/contenu"
)

// MaxDuree est la borne haute de duree_s, en secondes.
const MaxDuree = 7200

// ErrVersion signale une version de questionnaire différente (409, « rechargez la page »).
var ErrVersion = errors.New("version du questionnaire différente : rechargez la page")

// ErrInvalide signale une réponse refusée (400) ; son texte dit pourquoi, sans citer le contenu reçu.
type ErrInvalide struct{ Raison string }

func (e *ErrInvalide) Error() string { return e.Raison }

func invalide(format string, a ...any) error { return &ErrInvalide{fmt.Sprintf(format, a...)} }

var reJeton = regexp.MustCompile(`^[0-9a-fA-F]{32}$`)

// Validateur applique les règles du §5.2 au contenu chargé.
type Validateur struct{ Q *contenu.Questionnaire }

// Valider vérifie et normalise un envoi : rien n'est accepté qu'il n'ait validé, puis les conditions
// sont appliquées avant stockage. Le champ piège et le jeton sont traités par l'appelant.
func (v *Validateur) Valider(e *Envoi) (*Normalisee, error) {
	if e.Version != v.Q.Version {
		return nil, ErrVersion
	}
	if !reJeton.MatchString(e.Jeton) {
		return nil, invalide("jeton invalide")
	}
	res := &Normalisee{Donnees: map[string]json.RawMessage{}, DureeS: duree(e.DureeS)}
	for cle, brut := range e.Reponses {
		if cle == "ordre_cartes" {
			res.OrdreCartes = v.ordreCartes(brut)
			continue
		}
		qu, ok := v.Q.Questions[cle]
		if !ok || qu.Type == contenu.TypeTexteSeul {
			return nil, invalide("question inconnue : %q", tronquer(cle))
		}
		valeur, err := v.valeur(cle, qu, brut)
		if err != nil {
			return nil, err
		}
		if valeur == nil {
			continue
		}
		if qu.Type == contenu.TypePseudo {
			res.Pseudo = valeur.(string)
			continue
		}
		b, _ := json.Marshal(valeur)
		res.Donnees[cle] = b
	}
	v.AppliquerConditions(res.Donnees)
	return res, nil
}

func tronquer(s string) string {
	if r := []rune(s); len(r) > 20 {
		return string(r[:20]) + "…"
	}
	return s
}

func duree(brut json.RawMessage) int {
	var f float64
	if json.Unmarshal(brut, &f) != nil || math.IsNaN(f) {
		return 0
	}
	return int(math.Max(0, math.Min(MaxDuree, math.Round(f))))
}

// ordreCartes renvoie l'ordre s'il est une permutation exacte des cartes, sinon nil (ignoré).
func (v *Validateur) ordreCartes(brut json.RawMessage) []string {
	var ordre []string
	if json.Unmarshal(brut, &ordre) != nil || len(ordre) != len(v.Q.Cartes) {
		return nil
	}
	tri := slices.Clone(ordre)
	ref := slices.Clone(v.Q.Cartes)
	slices.Sort(tri)
	slices.Sort(ref)
	if !slices.Equal(tri, ref) {
		return nil
	}
	return ordre
}

// valeur valide une réponse ; elle renvoie nil pour « absente ».
func (v *Validateur) valeur(id string, qu contenu.Question, brut json.RawMessage) (any, error) {
	switch qu.Type {
	case contenu.TypeChoix, contenu.TypeReaction:
		var code string
		if json.Unmarshal(brut, &code) != nil {
			return nil, invalide("%s : texte attendu", id)
		}
		if !slices.Contains(qu.Codes(), code) {
			return nil, invalide("%s : code inconnu", id)
		}
		return code, nil
	case contenu.TypeTexte, contenu.TypePseudo:
		var s string
		if json.Unmarshal(brut, &s) != nil {
			return nil, invalide("%s : texte attendu", id)
		}
		s = NormaliserTexte(s, qu.Type == contenu.TypePseudo)
		if Longueur(s) > qu.Max {
			return nil, invalide("%s : %d caractères au plus", id, qu.Max)
		}
		if s == "" {
			return nil, nil
		}
		return s, nil
	case contenu.TypeTri:
		return validerD1(qu, brut)
	}
	return nil, invalide("%s : type non pris en charge", id)
}

func validerD1(qu contenu.Question, brut json.RawMessage) (any, error) {
	var d D1
	dec := json.NewDecoder(bytes.NewReader(brut))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&d); err != nil {
		return nil, invalide("D1 : forme invalide")
	}
	if d.ComeAujourdhui {
		if len(d.Sections) > 0 {
			return nil, invalide("D1 : « comme aujourd'hui » et des sections ensemble")
		}
		return D1{ComeAujourdhui: true}, nil
	}
	if len(d.Sections) == 0 {
		return nil, nil
	}
	codes := qu.CodesSections()
	etats := []string{EtatGarder, EtatDeplier, EtatEcarter}
	vues := map[string]bool{}
	var gardees []SectionD1
	var ecartees []SectionD1
	for _, s := range d.Sections {
		if !slices.Contains(codes, s.Code) {
			return nil, invalide("D1 : section inconnue")
		}
		if vues[s.Code] {
			return nil, invalide("D1 : section en double")
		}
		vues[s.Code] = true
		if !slices.Contains(etats, s.Etat) {
			return nil, invalide("D1 : état inconnu")
		}
		if s.Etat == EtatEcarter {
			if s.Rang != 0 {
				return nil, invalide("D1 : une section écartée n'a pas de rang")
			}
			ecartees = append(ecartees, s)
		} else {
			gardees = append(gardees, s)
		}
	}
	for _, s := range gardees {
		if s.Rang < 1 || s.Rang > len(gardees) {
			return nil, invalide("D1 : les rangs vont de 1 au nombre de sections gardées")
		}
	}
	sort.SliceStable(gardees, func(i, j int) bool { return gardees[i].Rang < gardees[j].Rang })
	for i, s := range gardees {
		if s.Rang != i+1 {
			return nil, invalide("D1 : rangs en double ou non contigus")
		}
	}
	sort.SliceStable(ecartees, func(i, j int) bool {
		return slices.Index(codes, ecartees[i].Code) < slices.Index(codes, ecartees[j].Code)
	})
	return D1{Sections: append(gardees, ecartees...)}, nil
}

// AppliquerConditions retire, avant stockage, les réponses des écrans dont la condition n'est pas remplie.
func (v *Validateur) AppliquerConditions(donnees map[string]json.RawMessage) {
	for _, e := range v.Q.Ecrans {
		for cle, codes := range e.Condition {
			var code string
			if brut, ok := donnees[cle]; ok {
				_ = json.Unmarshal(brut, &code)
			}
			if !slices.Contains(codes, code) {
				for _, id := range e.Questions {
					delete(donnees, id)
				}
			}
		}
	}
}

// CodeEnMinuscules est un utilitaire de comparaison de pseudos (lower(trim(pseudo))).
func CodeEnMinuscules(s string) string { return strings.ToLower(strings.TrimSpace(s)) }

// ValiderUne valide la valeur d'une seule question, pour une correction demandée par un répondant (R7).
// Elle renvoie la valeur normalisée en JSON, ou nil si la réponse devient absente.
func (v *Validateur) ValiderUne(id string, brut json.RawMessage) (json.RawMessage, error) {
	qu, ok := v.Q.Questions[id]
	if !ok || qu.Type == contenu.TypeTexteSeul {
		return nil, invalide("question inconnue : %q", tronquer(id))
	}
	val, err := v.valeur(id, qu, brut)
	if err != nil || val == nil {
		return nil, err
	}
	return json.Marshal(val)
}
