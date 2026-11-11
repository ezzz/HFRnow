package stats_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stats"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/testutil"
)

func lignes(t *testing.T, reps ...map[string]any) []reponse.Ligne {
	t.Helper()
	q := testutil.Questionnaire(t)
	v := &reponse.Validateur{Q: q}
	var out []reponse.Ligne
	for i, m := range reps {
		n, err := v.Valider(testutil.Envoi(t, q, testutil.Jeton(i), m))
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, reponse.Ligne{Identifiant: testutil.Jeton(i)[:16], DureeS: 999, OrdreCartes: n.OrdreCartes, Donnees: n.Donnees})
	}
	return out
}

func repetees(n int, m map[string]any) []map[string]any {
	out := make([]map[string]any, n)
	for i := range out {
		out[i] = m
	}
	return out
}

func agreger(t *testing.T, reps []map[string]any) stats.Agregats {
	t.Helper()
	return stats.Calculer(testutil.Questionnaire(t), lignes(t, reps...))
}

// Test 14 : statistiques.
func TestSeuilGlobal(t *testing.T) {
	neuf := agreger(t, repetees(9, map[string]any{"P1": "iphone"}))
	b, _ := json.Marshal(neuf.Publier(10))
	if string(b) != `{"disponible":false,"seuil":10}` {
		t.Errorf("9 réponses : %s", b)
	}
	dix := agreger(t, repetees(10, map[string]any{"P1": "iphone"}))
	b, _ = json.Marshal(dix.Publier(10))
	if !strings.Contains(string(b), `"disponible":true`) || !strings.Contains(string(b), `"total":10`) || !strings.Contains(string(b), `"P1":{"effectif":10,"codes":{`) || !strings.Contains(string(b), `"iphone":100`) {
		t.Errorf("10 réponses : %s", b)
	}
}

func TestSeuilParQuestionEtArrondis(t *testing.T) {
	var reps []map[string]any
	reps = append(reps, repetees(4, map[string]any{"P1": "iphone", "O1": "oser"})...)
	reps = append(reps, repetees(2, map[string]any{"P1": "ipad", "O1": "rester"})...)
	reps = append(reps, repetees(4, map[string]any{"P1": "duo"})...)
	// M1 : 9 réponses seulement (sous le seuil)
	reps[0]["M1"] = "un_onglet"
	m := map[string]any{}
	for i := 0; i < 9; i++ {
		x := map[string]any{}
		for k, v := range reps[i] {
			x[k] = v
		}
		x["M1"] = "un_onglet"
		reps[i] = x
	}
	_ = m
	a := agreger(t, reps)
	pub := a.Publier(10).(stats.Disponible)
	if _, ok := pub.Questions["M1"]; ok {
		t.Error("M1 (9 réponses) est sous le seuil : absente")
	}
	if _, ok := pub.Questions["O1"]; ok {
		t.Error("O1 (6 réponses) est sous le seuil : absente")
	}
	p1 := pub.Questions["P1"]
	if p1.Effectif != 10 || p1.Codes["iphone"] != 40 || p1.Codes["ipad"] != 20 || p1.Codes["duo"] != 40 || p1.Codes["plusieurs"] != 0 {
		t.Errorf("P1 : %+v", p1)
	}
	// arrondi au plus proche : 1/3 -> 33, 2/3 -> 67, 1/6 -> 17, 5/6 -> 83
	tiers := agreger(t, append(repetees(4, map[string]any{"O1": "oser"}), append(repetees(8, map[string]any{"O1": "rester"}), repetees(0, nil)...)...))
	o1 := tiers.Questions["O1"]
	if o1.Codes["oser"] != 33 || o1.Codes["rester"] != 67 {
		t.Errorf("arrondis : %+v", o1.Codes)
	}
	six := agreger(t, append(repetees(1, map[string]any{"O1": "oser"}), repetees(5, map[string]any{"O1": "rester"})...))
	if c := six.Questions["O1"].Codes; c["oser"] != 17 || c["rester"] != 83 {
		t.Errorf("arrondis sur six : %+v", c)
	}
}

func TestD1Agregats(t *testing.T) {
	garde := testutil.D1(false, testutil.Sec("favoris", "garder", 1), testutil.Sec("mp", "deplier", 2), testutil.Sec("reglages", "ecarter", 0))
	autre := testutil.D1(false, testutil.Sec("mp", "garder", 1), testutil.Sec("favoris", "garder", 2))
	var reps []map[string]any
	for i := 0; i < 6; i++ {
		reps = append(reps, map[string]any{"P1": "ipad", "D1": garde})
	}
	for i := 0; i < 2; i++ {
		reps = append(reps, map[string]any{"P1": "ipad", "D1": autre})
	}
	for i := 0; i < 4; i++ {
		reps = append(reps, map[string]any{"P1": "duo", "D1": map[string]any{"comme_aujourdhui": true}})
	}
	a := agreger(t, reps)
	d := a.Questions["D1"]
	if d.Effectif != 12 || *d.ComeAujourdhui != 33 {
		t.Fatalf("D1 : effectif %d, comme %v", d.Effectif, d.ComeAujourdhui)
	}
	if f := d.Sections["favoris"]; f.Effectif != 8 || f.Garder != 100 || f.Deplier != 0 || *f.RangMedian != 1 {
		t.Errorf("favoris : %+v", f)
	}
	if mp := d.Sections["mp"]; mp.Effectif != 8 || mp.Garder != 25 || mp.Deplier != 75 || *mp.RangMedian != 2 {
		t.Errorf("mp : %+v rang %v", mp, *mp.RangMedian)
	}
	if r := d.Sections["reglages"]; r.Effectif != 6 || r.Ecarter != 100 || r.RangMedian != nil {
		t.Errorf("reglages : %+v", r)
	}
	// effectif propre à la section : 6 répondants ont écarté Réglages, sous le seuil de 10 pour le global,
	// mais seuil de 5 à l'export : présent ; et pour un seuil de 7, absent
	if _, ok := a.Filtrer(7).Questions["D1"].Sections["reglages"]; ok {
		t.Error("section à 6 répondants : absente au seuil 7")
	}
	if _, ok := a.Filtrer(5).Questions["D1"].Sections["reglages"]; !ok {
		t.Error("section à 6 répondants : présente au seuil 5")
	}
}

func TestAucuneCleDeTexteLibre(t *testing.T) {
	reps := repetees(12, map[string]any{
		"P1": "iphone", "G1": "irritant", "L2": "texte", "C11": "idée", "F1": "mot", "I1": "pseudo", "ordre_cartes": testutil.Questionnaire(t).Cartes,
	})
	b, _ := json.Marshal(agreger(t, reps).Publier(10))
	for _, interdit := range []string{`"G1"`, `"L2"`, `"C11"`, `"F1"`, `"I1"`, "pseudo", "duree", "ordre", "irritant", "texte"} {
		if strings.Contains(string(b), interdit) {
			t.Errorf("la charge contient %s : %s", interdit, b)
		}
	}
}
