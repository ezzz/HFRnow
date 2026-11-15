package exporter

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/contenu"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stockage"
)

// ColonnesAnalyse renvoie les colonnes de l'export d'analyse, dans l'ordre du §12 : identifiant, recue_le,
// version, duree_s, puis les questions dans l'ordre des écrans (sans I1 ni C08), D1 aplati en
// D1_comme_aujourdhui puis D1_<section>_etat et D1_<section>_rang, ordre_cartes, textes_relus.
func ColonnesAnalyse(q *contenu.Questionnaire) []string {
	cols := []string{"identifiant", "recue_le", "version", "duree_s"}
	for _, id := range q.IDsDansLOrdre() {
		switch q.Questions[id].Type {
		case contenu.TypePseudo:
			continue
		case contenu.TypeTri:
			cols = append(cols, id+"_comme_aujourdhui")
			for _, s := range q.Questions[id].CodesSections() {
				cols = append(cols, id+"_"+s+"_etat", id+"_"+s+"_rang")
			}
		default:
			cols = append(cols, id)
		}
	}
	return append(cols, "ordre_cartes", "textes_relus")
}

// LignesAnalyse met chaque réponse à plat, dans l'ordre des colonnes. Ni pseudo, ni empreinte, ni jeton.
func LignesAnalyse(q *contenu.Questionnaire, lignes []reponse.Ligne) ([]string, [][]string, error) {
	cols := ColonnesAnalyse(q)
	var out [][]string
	for _, l := range lignes {
		valeurs := map[string]string{
			"identifiant": l.Identifiant, "recue_le": l.RecueLe, "version": l.Version,
			"duree_s": strconv.Itoa(l.DureeS), "ordre_cartes": strings.Join(l.OrdreCartes, " "),
		}
		for id, brut := range l.Donnees {
			qu, ok := q.Questions[id]
			if !ok {
				return nil, nil, fmt.Errorf("réponse %s : question inconnue %q", l.Identifiant, id)
			}
			if qu.Type == contenu.TypeTri {
				var d reponse.D1
				if err := json.Unmarshal(brut, &d); err != nil {
					return nil, nil, err
				}
				if d.ComeAujourdhui {
					valeurs[id+"_comme_aujourdhui"] = "oui"
				} else {
					valeurs[id+"_comme_aujourdhui"] = "non"
				}
				for _, s := range d.Sections {
					valeurs[id+"_"+s.Code+"_etat"] = s.Etat
					if s.Rang > 0 {
						valeurs[id+"_"+s.Code+"_rang"] = strconv.Itoa(s.Rang)
					}
				}
				continue
			}
			var s string
			if err := json.Unmarshal(brut, &s); err != nil {
				return nil, nil, err
			}
			valeurs[id] = s
		}
		ligne := make([]string, len(cols))
		for i, c := range cols {
			ligne[i] = valeurs[c]
		}
		out = append(out, ligne)
	}
	return cols, out, nil
}

// AnalyseCSV produit l'export d'analyse en CSV.
func AnalyseCSV(q *contenu.Questionnaire, lignes []reponse.Ligne) ([]byte, error) {
	cols, rows, err := LignesAnalyse(q, lignes)
	if err != nil {
		return nil, err
	}
	return EcrireCSV(append([][]string{cols}, rows...))
}

// AnalyseJSON produit l'export d'analyse en JSON : un objet par réponse, clés dans l'ordre des colonnes.
func AnalyseJSON(q *contenu.Questionnaire, lignes []reponse.Ligne) ([]byte, error) {
	cols, rows, err := LignesAnalyse(q, lignes)
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	buf.WriteString("[")
	for i, r := range rows {
		if i > 0 {
			buf.WriteString(",")
		}
		buf.WriteString("\n  {")
		for j, c := range cols {
			if j > 0 {
				buf.WriteString(", ")
			}
			k, _ := json.Marshal(c)
			v, _ := json.Marshal(r[j])
			buf.Write(k)
			buf.WriteString(": ")
			buf.Write(v)
		}
		buf.WriteString("}")
	}
	buf.WriteString("\n]\n")
	return buf.Bytes(), nil
}

// PseudosCSV produit la table pseudo ↔ identifiant, pour traiter une demande de droits seulement.
func PseudosCSV(pseudos []stockage.Pseudo) ([]byte, error) {
	rows := [][]string{{"identifiant", "pseudo"}}
	for _, p := range pseudos {
		rows = append(rows, []string{p.Identifiant, p.Pseudo})
	}
	return EcrireCSV(rows)
}
