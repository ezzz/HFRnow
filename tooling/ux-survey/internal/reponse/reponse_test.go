package reponse_test

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/testutil"
)

func valider(t *testing.T, m map[string]any) (*reponse.Normalisee, error) {
	t.Helper()
	q := testutil.Questionnaire(t)
	return (&reponse.Validateur{Q: q}).Valider(testutil.Envoi(t, q, testutil.Jeton(1), m))
}

func present(n *reponse.Normalisee, id string) bool { _, ok := n.Donnees[id]; return ok }

// Test 3 : conditions côté serveur.
func TestConditionsServeur(t *testing.T) {
	d1 := testutil.D1(false, testutil.Sec("favoris", "garder", 1))
	for _, p1 := range []string{"ipad", "duo", "plusieurs"} {
		n, err := valider(t, map[string]any{"P1": p1, "D1": d1, "D2": "cote_a_cote"})
		if err != nil || !present(n, "D1") || !present(n, "D2") {
			t.Errorf("P1=%s : D1 et D2 doivent être gardés (%v)", p1, err)
		}
	}
	for nom, m := range map[string]map[string]any{
		"iphone": {"P1": "iphone", "D1": d1, "D2": "cote_a_cote"},
		"absent": {"D1": d1, "D2": "cote_a_cote"},
	} {
		n, err := valider(t, m)
		if err != nil || present(n, "D1") || present(n, "D2") {
			t.Errorf("P1 %s : D1 et D2 doivent être retirés (%v)", nom, err)
		}
	}
	// G1 et L2 gardés quels que soient le profil et la réponse à L1
	for _, m := range []map[string]any{
		{"P1": "iphone", "G1": "irritant", "L2": "texte"},
		{"P1": "ipad", "L1": "lecture_continue", "G1": "irritant", "L2": "texte"},
		{"G1": "irritant", "L2": "texte"},
	} {
		n, err := valider(t, m)
		if err != nil || !present(n, "G1") || !present(n, "L2") {
			t.Errorf("G1 et L2 doivent être gardés : %v %v", m, err)
		}
	}
}

// Test 6 : validation.
func TestValidationRefus(t *testing.T) {
	refus := map[string]map[string]any{
		"clé inconnue":          {"Z9": "x"},
		"C08":                   {"C08": "adore"},
		"écran de lecture":      {"E0": "x"},
		"code inconnu":          {"P1": "mac"},
		"type inattendu":        {"P1": 3},
		"G1 à 281 caractères":   {"G1": testutil.Chaine(281)},
		"I1 à 41 caractères":    {"I1": testutil.Chaine(41)},
		"D1 comme + sections":   {"P1": "ipad", "D1": testutil.D1(true, testutil.Sec("favoris", "garder", 1))},
		"D1 rangs en double":    {"D1": testutil.D1(false, testutil.Sec("favoris", "garder", 1), testutil.Sec("mp", "garder", 1))},
		"D1 rangs non contigus": {"D1": testutil.D1(false, testutil.Sec("favoris", "garder", 1), testutil.Sec("mp", "garder", 3))},
		"D1 rang sur écartée":   {"D1": testutil.D1(false, testutil.Sec("favoris", "ecarter", 1))},
		"D1 rang de 1 à 9":      {"D1": testutil.D1(false, testutil.Sec("favoris", "garder", 2))},
		"D1 section en double":  {"D1": testutil.D1(false, testutil.Sec("favoris", "garder", 1), testutil.Sec("favoris", "deplier", 2))},
		"D1 section inconnue":   {"D1": testutil.D1(false, testutil.Sec("autre", "garder", 1))},
		"D1 état inconnu":       {"D1": testutil.D1(false, testutil.Sec("favoris", "peut-etre", 1))},
		"D1 gardée sans rang":   {"D1": testutil.D1(false, testutil.Sec("favoris", "garder", 0))},
		"D1 clé inconnue":       {"D1": map[string]any{"comme_aujourdhui": false, "x": 1}},
		"D1 pas un objet":       {"D1": "garder"},
	}
	for nom, m := range refus {
		_, err := valider(t, m)
		var inv *reponse.ErrInvalide
		if !errors.As(err, &inv) {
			t.Errorf("%s : doit être refusé (400), obtenu %v", nom, err)
		}
	}
	// limites acceptées
	for nom, m := range map[string]map[string]any{
		"G1 à 280":  {"G1": testutil.Chaine(280)},
		"I1 à 40":   {"I1": testutil.Chaine(40)},
		"accentués": {"G1": strings.Repeat("é", 280)},
	} {
		if _, err := valider(t, m); err != nil {
			t.Errorf("%s : doit être accepté : %v", nom, err)
		}
	}
	// jeton et version
	q := testutil.Questionnaire(t)
	v := &reponse.Validateur{Q: q}
	e := testutil.Envoi(t, q, "pas-un-jeton", nil)
	if _, err := v.Valider(e); err == nil {
		t.Error("jeton invalide accepté")
	}
	e = testutil.Envoi(t, q, testutil.Jeton(1), nil)
	e.Version = "autre"
	if _, err := v.Valider(e); !errors.Is(err, reponse.ErrVersion) {
		t.Errorf("version différente : %v", err)
	}
}

func TestNormalisation(t *testing.T) {
	n, err := valider(t, map[string]any{
		"G1":  "  Bonjour\u0000\u0007 tout\r\nle monde\ttab ‮",
		"L2":  "   ",
		"I1":  "  Pseudo\nSur deux lignes ",
		"C11": "café",
	})
	if err != nil {
		t.Fatal(err)
	}
	var g1, c11 string
	_ = json.Unmarshal(n.Donnees["G1"], &g1)
	_ = json.Unmarshal(n.Donnees["C11"], &c11)
	if g1 != "Bonjour tout\nle mondetab" {
		t.Errorf("G1 normalisé : %q", g1)
	}
	if present(n, "L2") {
		t.Error("un texte vide devient absent")
	}
	if n.Pseudo != "Pseudo Sur deux lignes" || present(n, "I1") {
		t.Errorf("pseudo : %q, dans les données : %v", n.Pseudo, present(n, "I1"))
	}
	if c11 != "café" {
		t.Errorf("NFC : %q", c11)
	}
}

func TestD1Normalise(t *testing.T) {
	n, err := valider(t, map[string]any{"P1": "ipad", "D1": testutil.D1(false,
		testutil.Sec("reglages", "ecarter", 0), testutil.Sec("mp", "deplier", 2), testutil.Sec("favoris", "garder", 1))})
	if err != nil {
		t.Fatal(err)
	}
	var d reponse.D1
	_ = json.Unmarshal(n.Donnees["D1"], &d)
	if len(d.Sections) != 3 || d.Sections[0].Code != "favoris" || d.Sections[1].Code != "mp" || d.Sections[2].Etat != "ecarter" {
		t.Errorf("D1 rangé par rang, écartées en dernier : %+v", d)
	}
	// comme_aujourdhui seul ; faux sans section = absent
	n, _ = valider(t, map[string]any{"P1": "duo", "D1": map[string]any{"comme_aujourdhui": true}})
	if string(n.Donnees["D1"]) != `{"comme_aujourdhui":true}` {
		t.Errorf("D1 réponse seule : %s", n.Donnees["D1"])
	}
	n, _ = valider(t, map[string]any{"P1": "duo", "D1": map[string]any{"comme_aujourdhui": false}})
	if present(n, "D1") {
		t.Error("D1 faux sans section doit être absent")
	}
}

func TestOrdreCartesEtDuree(t *testing.T) {
	q := testutil.Questionnaire(t)
	ordre := append([]string{}, q.Cartes...)
	ordre[0], ordre[1] = ordre[1], ordre[0]
	n, _ := valider(t, map[string]any{"ordre_cartes": ordre})
	if len(n.OrdreCartes) != 9 || n.OrdreCartes[0] != ordre[0] {
		t.Errorf("permutation valide gardée : %v", n.OrdreCartes)
	}
	for nom, o := range map[string][]string{"doublon": append([]string{q.Cartes[0]}, q.Cartes[0:8]...), "C08": append([]string{"C08"}, q.Cartes[1:]...), "court": q.Cartes[:5]} {
		if n, err := valider(t, map[string]any{"ordre_cartes": o}); err != nil || n.OrdreCartes != nil {
			t.Errorf("%s : ordre ignoré, sans erreur (%v, %v)", nom, n.OrdreCartes, err)
		}
	}
	e := testutil.Envoi(t, q, testutil.Jeton(1), nil)
	v := &reponse.Validateur{Q: q}
	for brut, attendu := range map[string]int{"99999": 7200, "-5": 0, `"x"`: 0, "12.4": 12} {
		e.DureeS = json.RawMessage(brut)
		if n, err := v.Valider(e); err != nil || n.DureeS != attendu {
			t.Errorf("duree_s %s : %v, attendu %d (%v)", brut, n.DureeS, attendu, err)
		}
	}
}
