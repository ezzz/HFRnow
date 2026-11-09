package exporter_test

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"slices"
	"strings"
	"testing"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/exporter"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stats"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stockage"
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
		out = append(out, reponse.Ligne{Identifiant: testutil.Jeton(i)[16:], RecueLe: "2026-11-20", Version: q.Version, DureeS: 300, OrdreCartes: n.OrdreCartes, Donnees: n.Donnees})
	}
	return out
}

func lireCSV(t *testing.T, b []byte) [][]string {
	t.Helper()
	if !bytes.HasPrefix(b, []byte{0xEF, 0xBB, 0xBF}) {
		t.Error("le CSV doit commencer par un BOM UTF-8")
	}
	r := csv.NewReader(bytes.NewReader(bytes.TrimPrefix(b, []byte{0xEF, 0xBB, 0xBF})))
	rows, err := r.ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	return rows
}

// Test 16 : export d'analyse.
func TestAnalyse(t *testing.T) {
	q := testutil.Questionnaire(t)
	l := lignes(t, map[string]any{
		"P1": "ipad", "O1": "oser", "G1": "=HYPERLINK(\"http://x\")", "L2": "+cmd", "C11": "-1+1", "F1": "@SUM(A1)", "M1": "un_onglet",
		"D1":           testutil.D1(false, testutil.Sec("mp", "garder", 1), testutil.Sec("favoris", "deplier", 2), testutil.Sec("reglages", "ecarter", 0)),
		"ordre_cartes": q.Cartes, "I1": "Pseudo-Secret",
	})
	b, err := exporter.AnalyseCSV(q, l)
	if err != nil {
		t.Fatal(err)
	}
	rows := lireCSV(t, b)
	cols := rows[0]
	debut := []string{"identifiant", "recue_le", "version", "duree_s", "P1", "P2", "P3", "O1", "G1", "L1", "L2", "D1_comme_aujourdhui"}
	if !slices.Equal(cols[:len(debut)], debut) {
		t.Errorf("début des colonnes : %v", cols[:len(debut)])
	}
	if slices.Index(cols, "G1") != slices.Index(cols, "O1")+1 || slices.Index(cols, "L1") != slices.Index(cols, "G1")+1 {
		t.Error("G1 doit être entre O1 et L1")
	}
	if slices.Contains(cols, "D1") || slices.Contains(cols, "C08") || slices.Contains(cols, "I1") {
		t.Error("pas de colonne D1, C08 ni I1")
	}
	d1 := 0
	for _, c := range cols {
		if strings.HasPrefix(c, "D1_") {
			d1++
		}
	}
	if d1 != 19 {
		t.Errorf("D1 aplati en %d colonnes, 19 attendues", d1)
	}
	if cols[len(cols)-2] != "ordre_cartes" || cols[len(cols)-1] != "textes_relus" {
		t.Errorf("fin des colonnes : %v", cols[len(cols)-3:])
	}
	pos := func(c string) string { return rows[1][slices.Index(cols, c)] }
	if pos("D1_comme_aujourdhui") != "non" || pos("D1_mp_etat") != "garder" || pos("D1_mp_rang") != "1" || pos("D1_favoris_etat") != "deplier" ||
		pos("D1_favoris_rang") != "2" || pos("D1_reglages_etat") != "ecarter" || pos("D1_reglages_rang") != "" || pos("textes_relus") != "" {
		t.Errorf("D1 aplati : %v", rows[1])
	}
	// injection de formule neutralisée
	for _, c := range []string{"G1", "L2", "C11", "F1"} {
		if !strings.HasPrefix(pos(c), "'") {
			t.Errorf("%s non neutralisé : %q", c, pos(c))
		}
	}
	if strings.Contains(string(b), "Pseudo-Secret") {
		t.Error("le pseudo ne doit pas être dans l'export d'analyse")
	}
	// JSON : mêmes colonnes, aucun pseudo
	j, _ := exporter.AnalyseJSON(q, l)
	var objs []map[string]string
	if err := json.Unmarshal(j, &objs); err != nil || len(objs) != 1 || objs[0]["D1_mp_etat"] != "garder" {
		t.Errorf("JSON : %v %s", err, j)
	}
	if strings.Contains(string(j), "Pseudo-Secret") {
		t.Error("pseudo dans le JSON")
	}
	// l'identifiant n'a pas d'ordre d'arrivée : le tri est par identifiant
	if !slices.IsSorted([]string{rows[1][0]}) {
		t.Error("tri")
	}
}

func TestPseudosCSV(t *testing.T) {
	b, err := exporter.PseudosCSV([]stockage.Pseudo{{Identifiant: "ab12", Pseudo: "=Pseudo"}})
	if err != nil {
		t.Fatal(err)
	}
	r := lireCSV(t, b)
	if r[1][0] != "ab12" || r[1][1] != "'=Pseudo" {
		t.Errorf("%v", r)
	}
}

// Test 16 : export d'ensemble, seuil de 5 par question et par section.
func TestAgregatsExport(t *testing.T) {
	q := testutil.Questionnaire(t)
	var reps []map[string]any
	garde := testutil.D1(false, testutil.Sec("favoris", "garder", 1))
	for i := 0; i < 10; i++ { // 10 répondants ont trié D1 ; seulement 4 ont donné un état à « mp »
		d := garde
		if i < 4 {
			d = testutil.D1(false, testutil.Sec("favoris", "garder", 1), testutil.Sec("mp", "garder", 2))
		}
		reps = append(reps, map[string]any{"P1": "ipad", "D1": d, "G1": "texte secret", "I1": "pseudo secret"})
	}
	for i := 0; i < 4; i++ { // M1 : 4 répondants seulement
		reps[i]["M1"] = "un_onglet"
	}
	a := stats.Calculer(q, lignes(t, reps...))
	j, err := exporter.AgregatsJSON(a)
	if err != nil {
		t.Fatal(err)
	}
	var out stats.Agregats
	if err := json.Unmarshal(j, &out); err != nil {
		t.Fatal(err)
	}
	if _, ok := out.Questions["M1"]; ok {
		t.Error("une question à 4 répondants doit être absente")
	}
	d1 := out.Questions["D1"]
	if d1.Effectif != 10 {
		t.Errorf("D1 : %+v", d1)
	}
	if _, ok := d1.Sections["mp"]; ok {
		t.Error("une section à laquelle 4 répondants seulement ont donné un état est absente, même si 10 ont trié")
	}
	if _, ok := d1.Sections["favoris"]; !ok {
		t.Error("favoris (10 répondants) présente")
	}
	c, _ := exporter.AgregatsCSV(a)
	for _, interdit := range []string{"texte secret", "pseudo secret", "G1", "I1"} {
		if strings.Contains(string(j), interdit) || strings.Contains(string(c), interdit) {
			t.Errorf("l'export d'ensemble contient %q", interdit)
		}
	}
	rows := lireCSV(t, c)
	if rows[0][0] != "question" || len(rows) < 3 {
		t.Errorf("CSV d'ensemble : %v", rows)
	}
}
