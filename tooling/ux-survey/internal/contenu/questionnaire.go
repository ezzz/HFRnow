// Package contenu charge et valide le questionnaire, la configuration et les valeurs des textes.
package contenu

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
)

// Reponse est une réponse possible d'une question à choix ou de réaction.
type Reponse struct {
	Code    string   `json:"code"`
	Libelle string   `json:"libelle"`
	Details []string `json:"details,omitempty"`
	Visuels []Visuel `json:"visuels,omitempty"`
}

// Visuel référence un fichier de web/visuels/ ; une vidéo porte une image d'attente.
type Visuel struct {
	Fichier      string `json:"fichier"`
	ImageAttente string `json:"image_attente,omitempty"`
	Alt          string `json:"alt"`
}

// Question est un bloc de questions.md.
type Question struct {
	Type         string    `json:"type"`
	Libelle      string    `json:"libelle"`
	Aide         string    `json:"aide,omitempty"`
	Max          int       `json:"max,omitempty"`
	Lien         string    `json:"lien,omitempty"`
	Textes       []string  `json:"textes,omitempty"`
	Reponses     []Reponse `json:"reponses,omitempty"`
	Sections     []Reponse `json:"sections,omitempty"`
	Etats        []Reponse `json:"etats,omitempty"`
	ReponseSeule *Reponse  `json:"reponse_seule,omitempty"`
}

// Ecran regroupe les questions affichées ensemble ; Condition vaut {question: codes autorisés}.
type Ecran struct {
	ID        string              `json:"id"`
	Questions []string            `json:"questions"`
	Condition map[string][]string `json:"condition,omitempty"`
	Melange   bool                `json:"melange,omitempty"`
	Fin       bool                `json:"fin,omitempty"`
}

// Questionnaire est le contenu complet.
type Questionnaire struct {
	Version   string              `json:"version"`
	Ecrans    []Ecran             `json:"ecrans"`
	Questions map[string]Question `json:"questions"`
	Cartes    []string            `json:"cartes"`
}

var (
	reCode = regexp.MustCompile(`^[a-z0-9_]+$`)
	reID   = regexp.MustCompile(`^[A-Z]\d{1,2}$`)
)

// Types de questions reconnus.
const (
	TypeTexteSeul = "texte-seul"
	TypeChoix     = "choix"
	TypeTexte     = "texte"
	TypeTri       = "tri"
	TypeReaction  = "reaction"
	TypePseudo    = "pseudo"
)

// Charger lit et valide un questionnaire.json ; toute clé inconnue est refusée.
func Charger(donnees []byte) (*Questionnaire, error) {
	dec := json.NewDecoder(bytes.NewReader(donnees))
	dec.DisallowUnknownFields()
	var q Questionnaire
	if err := dec.Decode(&q); err != nil {
		return nil, fmt.Errorf("questionnaire.json : %w", err)
	}
	if err := q.Valider(); err != nil {
		return nil, err
	}
	return &q, nil
}

// Valider vérifie la cohérence interne : types, codes ASCII uniques, écrans, cartes, absence de C08.
func (q *Questionnaire) Valider() error {
	if q.Version == "" {
		return fmt.Errorf("questionnaire.json : version vide")
	}
	if _, ok := q.Questions["C08"]; ok {
		return fmt.Errorf("questionnaire.json : C08 est retirée et ne doit pas figurer")
	}
	for id, qu := range q.Questions {
		if !reID.MatchString(id) {
			return fmt.Errorf("identifiant invalide %q", id)
		}
		if err := validerQuestion(id, qu); err != nil {
			return err
		}
	}
	vues := map[string]bool{}
	for _, e := range q.Ecrans {
		for _, id := range e.Questions {
			if _, ok := q.Questions[id]; !ok {
				return fmt.Errorf("écran %q : question inconnue %q", e.ID, id)
			}
			if vues[id] {
				return fmt.Errorf("question %q dans deux écrans", id)
			}
			vues[id] = true
		}
		for cle, codes := range e.Condition {
			qu, ok := q.Questions[cle]
			if !ok {
				return fmt.Errorf("écran %q : condition sur une question inconnue %q", e.ID, cle)
			}
			for _, c := range codes {
				if !slices.ContainsFunc(qu.Reponses, func(r Reponse) bool { return r.Code == c }) {
					return fmt.Errorf("écran %q : condition sur un code inconnu %s=%s", e.ID, cle, c)
				}
			}
		}
	}
	for id := range q.Questions {
		if !vues[id] {
			return fmt.Errorf("question %q absente des écrans", id)
		}
	}
	if len(q.Cartes) != 9 {
		return fmt.Errorf("neuf cartes attendues, %d trouvées", len(q.Cartes))
	}
	for _, c := range q.Cartes {
		if q.Questions[c].Type != TypeReaction {
			return fmt.Errorf("carte %q : type reaction attendu", c)
		}
	}
	return nil
}

func validerQuestion(id string, qu Question) error {
	switch qu.Type {
	case TypeTexteSeul, TypeChoix, TypeTexte, TypeTri, TypeReaction, TypePseudo:
	default:
		return fmt.Errorf("%s : type inconnu %q", id, qu.Type)
	}
	if (qu.Type == TypeTexte || qu.Type == TypePseudo) && qu.Max <= 0 {
		return fmt.Errorf("%s : longueur maximale manquante", id)
	}
	for nom, liste := range map[string][]Reponse{"reponses": qu.Reponses, "sections": qu.Sections, "etats": qu.Etats} {
		vus := map[string]bool{}
		for _, r := range liste {
			if !reCode.MatchString(r.Code) {
				return fmt.Errorf("%s.%s : code %q invalide (ASCII minuscules, chiffres, _)", id, nom, r.Code)
			}
			if vus[r.Code] {
				return fmt.Errorf("%s.%s : code %q en double", id, nom, r.Code)
			}
			vus[r.Code] = true
		}
	}
	if (qu.Type == TypeChoix || qu.Type == TypeReaction) && len(qu.Reponses) == 0 {
		return fmt.Errorf("%s : aucune réponse", id)
	}
	if qu.Type == TypeTri && (len(qu.Sections) == 0 || len(qu.Etats) != 3 || qu.ReponseSeule == nil) {
		return fmt.Errorf("%s : tri incomplet", id)
	}
	return nil
}

// Codes renvoie les codes de réponse de la question, dans l'ordre.
func (qu Question) Codes() []string {
	out := make([]string, 0, len(qu.Reponses))
	for _, r := range qu.Reponses {
		out = append(out, r.Code)
	}
	return out
}

// CodesSections renvoie les codes des sections d'une question de tri.
func (qu Question) CodesSections() []string {
	out := make([]string, 0, len(qu.Sections))
	for _, r := range qu.Sections {
		out = append(out, r.Code)
	}
	return out
}

// IDsDansLOrdre renvoie les identifiants de question dans l'ordre des écrans, sans les écrans de lecture seule.
func (q *Questionnaire) IDsDansLOrdre() []string {
	var out []string
	for _, e := range q.Ecrans {
		for _, id := range e.Questions {
			if q.Questions[id].Type != TypeTexteSeul {
				out = append(out, id)
			}
		}
	}
	return out
}
