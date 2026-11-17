package contenu

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	uxsurvey "github.com/ezzz/hfrnow/tooling/ux-survey"
)

// Test 2 : codes en ASCII minuscules, uniques ; dix cartes ; visuels existants et identiques à ceux de #632.
func TestContenuCodesCartesEtVisuels(t *testing.T) {
	q := chargerContenu(t)
	reASCII := regexp.MustCompile(`^[a-z0-9_]+$`)
	for id, qu := range q.Questions {
		vus := map[string]bool{}
		for _, r := range append(append(append([]Reponse{}, qu.Reponses...), qu.Sections...), qu.Etats...) {
			if !reASCII.MatchString(r.Code) || vus[r.Code] {
				t.Errorf("%s : code %q invalide ou en double", id, r.Code)
			}
			vus[r.Code] = true
		}
	}
	if len(q.Cartes) != 10 {
		t.Errorf("dix cartes attendues : %v", q.Cartes)
	}

	racine := racineDepot(t)
	copie := filepath.Join(racine, "tooling/ux-survey/web/visuels")
	ref := filepath.Join(racine, "docs/ux/questionnaire/visuels")
	inventaire, err := os.ReadFile(filepath.Join(ref, "inventaire.md"))
	if err != nil {
		t.Fatal(err)
	}
	for id, qu := range q.Questions {
		for _, r := range append(append([]Reponse{}, qu.Reponses...), qu.Sections...) {
			for _, v := range r.Visuels {
				fichiers := []string{v.Fichier}
				if v.ImageAttente != "" {
					fichiers = append(fichiers, v.ImageAttente)
				}
				for _, f := range fichiers {
					if _, err := os.Stat(filepath.Join(copie, f)); err != nil {
						t.Errorf("%s : visuel %s absent de web/visuels", id, f)
					}
				}
				if !strings.Contains(string(inventaire), "`"+v.Fichier+"` | "+v.Alt+" |") {
					t.Errorf("%s : %s et son texte alternatif ne sont pas dans inventaire.md", id, v.Fichier)
				}
				if v.Alt == "" {
					t.Errorf("%s : %s sans texte alternatif", id, v.Fichier)
				}
			}
		}
	}
	// web/visuels est identique, octet pour octet, à docs/ux/questionnaire/visuels (hors inventaire.md et README)
	liste := func(d string) map[string][]byte {
		out := map[string][]byte{}
		entrees, err := os.ReadDir(d)
		if err != nil {
			t.Fatal(err)
		}
		for _, e := range entrees {
			if e.IsDir() || strings.HasSuffix(e.Name(), ".md") {
				continue
			}
			b, err := os.ReadFile(filepath.Join(d, e.Name()))
			if err != nil {
				t.Fatal(err)
			}
			out[e.Name()] = b
		}
		return out
	}
	a, b := liste(ref), liste(copie)
	// les captures de l'app actuelle (#911) vivent dans visuels/actuel/, les maquettes (#632) dans visuels/scenarios/ ;
	// les unes et les autres sont copiées à plat dans web/visuels (les cartes de D1, dans scenarios/D1-cartes/, ne le sont pas)
	for _, sous := range []string{"actuel", "scenarios"} {
		for nom, c := range liste(filepath.Join(ref, sous)) {
			if _, deja := a[nom]; deja {
				t.Errorf("visuel %s présent dans deux dossiers de docs/ux/questionnaire/visuels", nom)
			}
			a[nom] = c
		}
	}
	// les cartes de D1 (#919) sont copiées dans web/visuels/D1-cartes/, une par section, identiques à l'original
	cartes := liste(filepath.Join(ref, "scenarios/D1-cartes"))
	copiees := liste(filepath.Join(copie, "D1-cartes"))
	for _, s := range q.Questions["D1"].Sections {
		nom := "D1-carte-" + s.Code + ".png"
		if len(s.Visuels) != 1 || s.Visuels[0].Fichier != "D1-cartes/"+nom {
			t.Errorf("D1.%s : une carte D1-cartes/%s attendue : %+v", s.Code, nom, s.Visuels)
		}
		if len(cartes[nom]) == 0 || !bytes.Equal(cartes[nom], copiees[nom]) {
			t.Errorf("carte %s absente ou différente dans web/visuels/D1-cartes", nom)
		}
		delete(copiees, nom)
	}
	if len(copiees) > 0 {
		t.Errorf("web/visuels/D1-cartes contient des fichiers sans section : %v", len(copiees))
	}
	for nom, c := range a {
		if !bytes.Equal(c, b[nom]) {
			t.Errorf("visuel %s absent ou différent dans web/visuels", nom)
		}
	}
	for nom := range b {
		if _, ok := a[nom]; !ok {
			t.Errorf("visuel %s de web/visuels absent de docs/ux/questionnaire/visuels", nom)
		}
	}
}

func TestChargerRefuse(t *testing.T) {
	base := func() map[string]any {
		var m map[string]any
		if err := json.Unmarshal(uxsurvey.ContenuJSON(), &m); err != nil {
			t.Fatal(err)
		}
		return m
	}
	cas := map[string]func(map[string]any){
		"C08 présent": func(m map[string]any) {
			qs := m["questions"].(map[string]any)
			qs["C08"] = qs["C01"]
		},
		"code non ASCII": func(m map[string]any) {
			r := m["questions"].(map[string]any)["P1"].(map[string]any)["reponses"].([]any)[0].(map[string]any)
			r["code"] = "Été"
		},
		"code en double": func(m map[string]any) {
			rs := m["questions"].(map[string]any)["P1"].(map[string]any)["reponses"].([]any)
			rs[1].(map[string]any)["code"] = rs[0].(map[string]any)["code"]
		},
		"exclusive inconnue": func(m map[string]any) {
			m["questions"].(map[string]any)["X1"].(map[string]any)["exclusive"] = "autre"
		},
		"exclusive sur un choix simple": func(m map[string]any) {
			m["questions"].(map[string]any)["P1"].(map[string]any)["exclusive"] = "iphone"
		},
		"huit cartes":  func(m map[string]any) { m["cartes"] = m["cartes"].([]any)[1:] },
		"clé inconnue": func(m map[string]any) { m["inconnue"] = 1 },
	}
	for nom, mod := range cas {
		m := base()
		mod(m)
		b, _ := json.Marshal(m)
		if _, err := Charger(b); err == nil {
			t.Errorf("%s : aurait dû être refusé", nom)
		}
	}
}

func env(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func envValide() map[string]string {
	return map[string]string{
		"UX_ORIGINE": "https://sondage.exemple.fr", "UX_PROXY_DE_CONFIANCE": "172.31.250.1",
		"UX_FERMETURE": "2026-12-31T23:00:00+01:00", "UX_MENTION_MAJ": "2026-11-09",
	}
}

// Test 19 : configuration.
func TestConfiguration(t *testing.T) {
	if _, err := ChargerConfig(env(envValide())); err != nil {
		t.Fatal(err)
	}
	for _, v := range []string{"UX_ORIGINE", "UX_PROXY_DE_CONFIANCE", "UX_FERMETURE", "UX_MENTION_MAJ"} {
		m := envValide()
		delete(m, v)
		if _, err := ChargerConfig(env(m)); err == nil {
			t.Errorf("sans %s : doit échouer", v)
		}
	}
	for _, o := range []string{"https://sondage.exemple.fr/questionnaire", "https://sondage.exemple.fr?x=1", "ftp://sondage.exemple.fr", "sondage.exemple.fr", "https://u:p@sondage.exemple.fr"} {
		m := envValide()
		m["UX_ORIGINE"] = o
		if _, err := ChargerConfig(env(m)); err == nil {
			t.Errorf("UX_ORIGINE=%q doit être refusée", o)
		}
	}
	for _, o := range []string{"http://127.0.0.1:8080", "https://sondage.exemple.fr/"} {
		m := envValide()
		m["UX_ORIGINE"] = o
		if _, err := ChargerConfig(env(m)); err != nil {
			t.Errorf("UX_ORIGINE=%q : %v", o, err)
		}
	}
	m := envValide()
	m["UX_SEUIL_STATS"] = "9"
	if _, err := ChargerConfig(env(m)); err == nil {
		t.Error("UX_SEUIL_STATS=9 doit être refusé")
	}
	m["UX_SEUIL_STATS"] = "10"
	if c, err := ChargerConfig(env(m)); err != nil || c.SeuilStats != 10 {
		t.Errorf("UX_SEUIL_STATS=10 : %v", err)
	}
	m["UX_PROXY_DE_CONFIANCE"] = "pas une ip"
	if _, err := ChargerConfig(env(m)); err == nil {
		t.Error("proxy invalide doit échouer")
	}
	m["UX_PROXY_DE_CONFIANCE"] = "aucun"
	if c, err := ChargerConfig(env(m)); err != nil || len(c.Proxy) != 0 {
		t.Errorf("aucun : %v", err)
	}
}

func TestDateEffacement(t *testing.T) {
	cas := map[string]string{
		"2026-12-15T23:00:00+01:00": "2027-02-15T23:00:00+01:00",
		"2026-12-31T23:00:00+01:00": "2027-02-28T23:00:00+01:00", // février non bissextile
		"2027-12-31T10:00:00+01:00": "2028-02-29T10:00:00+01:00", // février bissextile
		"2026-10-31T08:00:00Z":      "2026-12-31T08:00:00Z",
		"2026-11-30T08:00:00Z":      "2027-01-30T08:00:00Z",
	}
	for f, attendu := range cas {
		ft, _ := time.Parse(time.RFC3339, f)
		if got := PlusDeuxMois(ft).Format(time.RFC3339); got != attendu {
			t.Errorf("fermeture %s : effacement %s, attendu %s", f, got, attendu)
		}
	}
}

func TestRemplacerEtDates(t *testing.T) {
	c, _ := ChargerConfig(env(envValide()))
	v := c.Valeurs()
	if v["{date_fermeture}"] != "31 décembre 2026" || v["{date_effacement}"] != "28 février 2027" || v["{seuil_statistiques}"] != "10" {
		t.Errorf("valeurs : %v", v)
	}
	if DateFrancaise(time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC)) != "1er janvier 2027" {
		t.Error("1er janvier")
	}
	s, err := Remplacer("fermé le {date_fermeture}, effacé le {date_effacement}", v)
	if err != nil || strings.Contains(s, "{") {
		t.Errorf("remplacement : %q %v", s, err)
	}
	if _, err := Remplacer("valeur {inconnue}", v); err == nil {
		t.Error("une valeur inconnue doit être refusée")
	}
}
