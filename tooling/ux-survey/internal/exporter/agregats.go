package exporter

import (
	"encoding/json"
	"slices"
	"sort"
	"strconv"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stats"
)

// SeuilExport est l'effectif minimal d'une question, ou d'une section de D1, dans l'export d'ensemble (R11).
const SeuilExport = 5

// AgregatsExport applique le seuil de 5 aux agrégats : c'est le contenu de l'export agregats et de agregats.json.
func AgregatsExport(a stats.Agregats) stats.Agregats { return a.Filtrer(SeuilExport) }

// AgregatsJSON produit l'export d'ensemble en JSON.
func AgregatsJSON(a stats.Agregats) ([]byte, error) {
	b, err := json.MarshalIndent(AgregatsExport(a), "", "  ")
	if err != nil {
		return nil, err
	}
	return append(b, '\n'), nil
}

// AgregatsCSV produit l'export d'ensemble en CSV long : question, élément, état, pourcentage, effectif, rang médian.
// Aucun texte libre, pseudo ni identifiant de réponse.
func AgregatsCSV(a stats.Agregats) ([]byte, error) {
	a = AgregatsExport(a)
	rows := [][]string{{"question", "element", "etat", "pourcentage", "effectif", "rang_median"}}
	ids := make([]string, 0, len(a.Questions))
	for id := range a.Questions {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		q := a.Questions[id]
		eff := strconv.Itoa(q.Effectif)
		codes := make([]string, 0, len(q.Codes))
		for c := range q.Codes {
			codes = append(codes, c)
		}
		slices.Sort(codes)
		for _, c := range codes {
			rows = append(rows, []string{id, c, "", strconv.Itoa(q.Codes[c]), eff, ""})
		}
		if q.ComeAujourdhui != nil {
			rows = append(rows, []string{id, "comme_aujourdhui", "", strconv.Itoa(*q.ComeAujourdhui), eff, ""})
		}
		sections := make([]string, 0, len(q.Sections))
		for s := range q.Sections {
			sections = append(sections, s)
		}
		slices.Sort(sections)
		for _, s := range sections {
			sec := q.Sections[s]
			rang := ""
			if sec.RangMedian != nil {
				rang = strconv.FormatFloat(*sec.RangMedian, 'f', -1, 64)
			}
			se := strconv.Itoa(sec.Effectif)
			rows = append(rows,
				[]string{id, s, "garder", strconv.Itoa(sec.Garder), se, rang},
				[]string{id, s, "deplier", strconv.Itoa(sec.Deplier), se, ""},
				[]string{id, s, "ecarter", strconv.Itoa(sec.Ecarter), se, ""})
		}
	}
	return EcrireCSV(rows)
}
