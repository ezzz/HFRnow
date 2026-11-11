package contenu

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"

	uxsurvey "github.com/ezzz/hfrnow/tooling/ux-survey"
)

// racineDepot remonte jusqu'au dossier qui contient .git (dossier, ou fichier dans un worktree).
func racineDepot(t *testing.T) string {
	t.Helper()
	d, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	for {
		if _, err := os.Stat(filepath.Join(d, ".git")); err == nil {
			return d
		}
		p := filepath.Dir(d)
		if p == d {
			t.Fatal("racine du dépôt introuvable (aucun .git en remontant)")
		}
		d = p
	}
}

func chargerContenu(t *testing.T) *Questionnaire {
	t.Helper()
	q, err := Charger(uxsurvey.ContenuJSON())
	if err != nil {
		t.Fatal(err)
	}
	return q
}

type bloc struct {
	id    string
	corps []string
}

var reTitreQ = regexp.MustCompile(`^### ([A-Z]\d{1,2})$`)

// lireBlocs découpe questions.md : un bloc commence à un titre ### dont le texte est un identifiant, et va
// jusqu'au titre suivant ; les autres titres ### (note « Écran Cartes ») sont ignorés avec leur contenu.
func lireBlocs(t *testing.T) []bloc {
	t.Helper()
	brut, err := os.ReadFile(filepath.Join(racineDepot(t), "docs/ux/questionnaire/questions.md"))
	if err != nil {
		t.Fatal(err)
	}
	var blocs []bloc
	var cur *bloc
	for _, l := range strings.Split(string(brut), "\n") {
		switch {
		case strings.HasPrefix(l, "### "):
			if m := reTitreQ.FindStringSubmatch(l); m != nil {
				blocs = append(blocs, bloc{id: m[1]})
				cur = &blocs[len(blocs)-1]
			} else {
				cur = nil
			}
		case strings.HasPrefix(l, "## "), strings.HasPrefix(l, "#"):
			cur = nil
		default:
			if cur != nil {
				cur.corps = append(cur.corps, l)
			}
		}
	}
	return blocs
}

func (b bloc) champ(nom string) (string, bool) {
	for _, l := range b.corps {
		if v, ok := strings.CutPrefix(l, "- "+nom+" : "); ok {
			return strings.TrimSpace(v), true
		}
	}
	return "", false
}

func (b bloc) sousChamp(nom string) (string, bool) {
	for _, l := range b.corps {
		if v, ok := strings.CutPrefix(l, "  - "+nom+" : "); ok {
			return strings.TrimSpace(v), true
		}
	}
	return "", false
}

var reCodeLibelle = regexp.MustCompile("^`([a-z0-9_]+)` (.+)$")

func listeCodes(t *testing.T, s string) []Reponse {
	t.Helper()
	var out []Reponse
	for _, p := range strings.Split(s, " · ") {
		m := reCodeLibelle.FindStringSubmatch(strings.TrimSpace(p))
		if m == nil {
			t.Fatalf("liste illisible : %q", p)
		}
		out = append(out, Reponse{Code: m[1], Libelle: m[2]})
	}
	return out
}

func comparerListe(t *testing.T, ou string, attendu, obtenu []Reponse) {
	t.Helper()
	if len(attendu) != len(obtenu) {
		t.Errorf("%s : %d réponses dans questions.md, %d dans le JSON", ou, len(attendu), len(obtenu))
		return
	}
	for i := range attendu {
		if attendu[i].Code != obtenu[i].Code || attendu[i].Libelle != obtenu[i].Libelle {
			t.Errorf("%s[%d] : questions.md %q/%q, JSON %q/%q", ou, i, attendu[i].Code, attendu[i].Libelle, obtenu[i].Code, obtenu[i].Libelle)
		}
	}
}

var reGuillemets = regexp.MustCompile(`«\s*(.+?)\s*»`)

// Test 1 : concordance entre questionnaire.json et questions.md.
func TestConcordanceQuestionsMd(t *testing.T) {
	q := chargerContenu(t)
	blocs := lireBlocs(t)
	var idsMd []string
	for _, b := range blocs {
		idsMd = append(idsMd, b.id)
		if b.id == "C08" {
			continue // un bloc C08 marqué retiré serait ignoré
		}
		qu, ok := q.Questions[b.id]
		if !ok {
			t.Errorf("%s : présent dans questions.md, absent du JSON", b.id)
			continue
		}
		verifierBloc(t, q, b, qu)
	}
	// ordre et ensemble : les écrans, aplatis, donnent les identifiants de questions.md dans le même ordre
	var idsJSON []string
	for _, e := range q.Ecrans {
		idsJSON = append(idsJSON, e.Questions...)
	}
	idsMd = slices.DeleteFunc(idsMd, func(s string) bool { return s == "C08" })
	if !slices.Equal(idsMd, idsJSON) {
		t.Errorf("ordre ou ensemble différents\n questions.md : %v\n JSON         : %v", idsMd, idsJSON)
	}
	if _, ok := q.Questions["C08"]; ok || slices.Contains(q.Cartes, "C08") {
		t.Error("C08 ne doit pas figurer dans le JSON")
	}
}

func verifierBloc(t *testing.T, q *Questionnaire, b bloc, qu Question) {
	t.Helper()
	if v, _ := b.champ("Question"); v != qu.Libelle {
		t.Errorf("%s : question %q dans questions.md, %q dans le JSON", b.id, v, qu.Libelle)
	}
	aide, _ := b.champ("Aide")
	if qu.Type == TypeTexteSeul {
		for _, g := range reGuillemets.FindAllStringSubmatch(aide, -1) {
			if !slices.Contains(qu.Textes, g[1]) {
				t.Errorf("%s : texte absent du JSON : %q", b.id, g[1])
			}
		}
		if len(qu.Textes) != len(reGuillemets.FindAllStringSubmatch(aide, -1)) {
			t.Errorf("%s : %d textes dans le JSON, %d dans questions.md", b.id, len(qu.Textes), len(reGuillemets.FindAllStringSubmatch(aide, -1)))
		}
	} else if strings.HasPrefix(aide, "(aucune)") || strings.HasPrefix(aide, "(facultative)") {
		if qu.Aide != "" {
			t.Errorf("%s : pas d'aide dans questions.md, %q dans le JSON", b.id, qu.Aide)
		}
	} else if g := reGuillemets.FindStringSubmatch(aide); g == nil || g[1] != qu.Aide {
		t.Errorf("%s : aide %v dans questions.md, %q dans le JSON", b.id, g, qu.Aide)
	}

	rep, _ := b.champ("Réponses")
	switch {
	case b.id == "D1":
		s, _ := b.sousChamp("Sections")
		comparerListe(t, "D1.sections", listeCodes(t, s), qu.Sections)
		e, _ := b.sousChamp("États")
		comparerListe(t, "D1.états", listeCodes(t, e), qu.Etats)
		if o, ok := b.sousChamp("Ordre"); !ok || o == "" {
			t.Error("D1 : ligne Ordre absente de questions.md")
		}
		rs, _ := b.sousChamp("Réponse seule")
		if qu.ReponseSeule == nil {
			t.Fatal("D1 : réponse seule absente du JSON")
		}
		comparerListe(t, "D1.réponse seule", listeCodes(t, rs), []Reponse{*qu.ReponseSeule})
	case strings.HasPrefix(rep, "(texte libre"):
		if m := regexp.MustCompile(`(\d+) caractères`).FindStringSubmatch(rep); m != nil {
			if n, _ := strconv.Atoi(m[1]); n != qu.Max {
				t.Errorf("%s : %d caractères dans questions.md, %d dans le JSON", b.id, n, qu.Max)
			}
		}
		if qu.Type != TypeTexte && qu.Type != TypePseudo {
			t.Errorf("%s : texte libre, type %q dans le JSON", b.id, qu.Type)
		}
	case strings.HasPrefix(rep, "(aucune"):
		if qu.Type != TypeTexteSeul {
			t.Errorf("%s : écran de lecture, type %q dans le JSON", b.id, qu.Type)
		}
	default:
		comparerListe(t, b.id+".réponses", listeCodes(t, rep), qu.Reponses)
		verifierDetails(t, b, qu)
	}

	cond, _ := b.champ("Condition")
	verifierCondition(t, q, b.id, cond)
}

func verifierDetails(t *testing.T, b bloc, qu Question) {
	t.Helper()
	attendus := map[string][]string{}
	dans := false
	for _, l := range b.corps {
		switch {
		case l == "- Détails :":
			dans = true
		case dans && strings.HasPrefix(l, "  - "):
			code, pts, ok := strings.Cut(strings.TrimPrefix(l, "  - "), " : ")
			if !ok {
				t.Fatalf("%s : ligne de détails illisible : %q", b.id, l)
			}
			points := strings.Split(pts, " · ")
			if len(points) > 3 {
				t.Errorf("%s : plus de trois points pour %s", b.id, code)
			}
			attendus[strings.Trim(code, "`")] = points
		case dans:
			dans = false
		}
	}
	for _, r := range qu.Reponses {
		if !slices.Equal(attendus[r.Code], r.Details) {
			t.Errorf("%s.%s : détails %v dans questions.md, %v dans le JSON", b.id, r.Code, attendus[r.Code], r.Details)
		}
		delete(attendus, r.Code)
	}
	if len(attendus) > 0 {
		t.Errorf("%s : détails pour des codes absents du JSON : %v", b.id, attendus)
	}
}

var reCond = regexp.MustCompile("^`([A-Z]\\d)` vaut (.+)$")

func verifierCondition(t *testing.T, q *Questionnaire, id, cond string) {
	t.Helper()
	var ecran *Ecran
	for i := range q.Ecrans {
		if slices.Contains(q.Ecrans[i].Questions, id) {
			ecran = &q.Ecrans[i]
		}
	}
	if ecran == nil {
		t.Errorf("%s : aucun écran", id)
		return
	}
	if strings.HasPrefix(cond, "(aucune)") {
		if len(ecran.Condition) != 0 {
			t.Errorf("%s : aucune condition dans questions.md, %v dans le JSON", id, ecran.Condition)
		}
		return
	}
	m := reCond.FindStringSubmatch(cond)
	if m == nil {
		t.Errorf("%s : condition illisible : %q", id, cond)
		return
	}
	var codes []string
	for _, c := range regexp.MustCompile("`([a-z_]+)`").FindAllStringSubmatch(m[2], -1) {
		codes = append(codes, c[1])
	}
	if got := ecran.Condition[m[1]]; !slices.Equal(got, codes) {
		t.Errorf("%s : condition %s=%v dans questions.md, %v dans le JSON", id, m[1], codes, got)
	}
}

// Les identifiants de cadrage-construction.md §2 sont tous présents, hors C08.
func TestIdentifiantsDuCadrage(t *testing.T) {
	q := chargerContenu(t)
	brut, err := os.ReadFile(filepath.Join(racineDepot(t), "docs/ux/questionnaire/cadrage-construction.md"))
	if err != nil {
		t.Fatal(err)
	}
	section := strings.Split(strings.Split(string(brut), "## 2.")[1], "## 3.")[0]
	var ids []string
	for _, l := range strings.Split(section, "\n") {
		if !strings.HasPrefix(l, "| ") || strings.HasPrefix(l, "| Écran") {
			continue
		}
		cols := strings.Split(l, "|")
		if len(cols) < 3 {
			continue
		}
		cellule := cols[2]
		if strings.Contains(cellule, "à `C10`") { // « `C01` à `C10` sauf `C08` »
			for n := 1; n <= 10; n++ {
				if n != 8 {
					ids = append(ids, "C"+strings.Repeat("0", 2-len(strconv.Itoa(n)))+strconv.Itoa(n))
				}
			}
			continue
		}
		for _, m := range regexp.MustCompile("`([A-Z]\\d{1,2})`").FindAllStringSubmatch(cellule, -1) {
			ids = append(ids, m[1])
		}
	}
	if len(ids) < 20 {
		t.Fatalf("§2 mal lue : %v", ids)
	}
	for _, id := range ids {
		if _, ok := q.Questions[id]; !ok {
			t.Errorf("%s de cadrage-construction.md §2 absent du JSON", id)
		}
	}
	if !slices.Contains(ids, "G1") {
		t.Error("G1 devrait figurer dans la §2 du cadrage")
	}
}
