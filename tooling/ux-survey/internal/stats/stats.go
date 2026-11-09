// Package stats calcule les agrégats de l'écran de fin et de l'export d'ensemble : questions fermées
// seulement, jamais un texte libre, un pseudo, une durée ni un ordre de cartes.
package stats

import (
	"encoding/json"
	"math"
	"slices"
	"sort"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/contenu"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
)

// Section résume l'une des sections de D1, sur les répondants qui lui ont donné un état.
type Section struct {
	Effectif   int      `json:"effectif"`
	Garder     int      `json:"garder"`
	Deplier    int      `json:"deplier"`
	Ecarter    int      `json:"ecarter"`
	RangMedian *float64 `json:"rang_median,omitempty"`
}

// Question résume une question fermée : pourcentages entiers arrondis et effectif.
type Question struct {
	Effectif       int                `json:"effectif"`
	Codes          map[string]int     `json:"codes,omitempty"`
	ComeAujourdhui *int               `json:"comme_aujourdhui,omitempty"`
	Sections       map[string]Section `json:"sections,omitempty"`
}

// Agregats est le jeu complet, sans seuil : base de l'écran de fin, de l'export et de agregats.json.
type Agregats struct {
	Total     int                 `json:"total"`
	Questions map[string]Question `json:"questions"`
}

// Disponible est la charge publiée au-dessus du seuil global (§8).
type Disponible struct {
	Disponible bool                `json:"disponible"`
	Total      int                 `json:"total"`
	Seuil      int                 `json:"seuil"`
	Questions  map[string]Question `json:"questions"`
}

// Indisponible est la charge sous le seuil : ni total ni autre compte.
type Indisponible struct {
	Disponible bool `json:"disponible"`
	Seuil      int  `json:"seuil"`
}

func pct(n, total int) int { return int(math.Round(100 * float64(n) / float64(total))) }

// Calculer agrège les réponses stockées sur les questions fermées du contenu.
func Calculer(q *contenu.Questionnaire, lignes []reponse.Ligne) Agregats {
	a := Agregats{Total: len(lignes), Questions: map[string]Question{}}
	for id, qu := range q.Questions {
		switch qu.Type {
		case contenu.TypeChoix, contenu.TypeReaction:
			if r, ok := calculerChoix(id, qu, lignes); ok {
				a.Questions[id] = r
			}
		case contenu.TypeTri:
			if r, ok := calculerD1(id, qu, lignes); ok {
				a.Questions[id] = r
			}
		}
	}
	return a
}

func calculerChoix(id string, qu contenu.Question, lignes []reponse.Ligne) (Question, bool) {
	comptes := map[string]int{}
	eff := 0
	for _, l := range lignes {
		var code string
		if brut, ok := l.Donnees[id]; ok && json.Unmarshal(brut, &code) == nil && slices.Contains(qu.Codes(), code) {
			comptes[code]++
			eff++
		}
	}
	if eff == 0 {
		return Question{}, false
	}
	r := Question{Effectif: eff, Codes: map[string]int{}}
	for _, c := range qu.Codes() {
		r.Codes[c] = pct(comptes[c], eff)
	}
	return r, true
}

func calculerD1(id string, qu contenu.Question, lignes []reponse.Ligne) (Question, bool) {
	var reponses []reponse.D1
	for _, l := range lignes {
		var d reponse.D1
		if brut, ok := l.Donnees[id]; ok && json.Unmarshal(brut, &d) == nil {
			reponses = append(reponses, d)
		}
	}
	if len(reponses) == 0 {
		return Question{}, false
	}
	comme := 0
	type acc struct {
		n     int
		etats map[string]int
		rangs []int
	}
	parSection := map[string]*acc{}
	for _, d := range reponses {
		if d.ComeAujourdhui {
			comme++
			continue
		}
		for _, s := range d.Sections {
			x := parSection[s.Code]
			if x == nil {
				x = &acc{etats: map[string]int{}}
				parSection[s.Code] = x
			}
			x.n++
			x.etats[s.Etat]++
			if s.Rang > 0 {
				x.rangs = append(x.rangs, s.Rang)
			}
		}
	}
	p := pct(comme, len(reponses))
	r := Question{Effectif: len(reponses), ComeAujourdhui: &p, Sections: map[string]Section{}}
	for _, code := range qu.CodesSections() {
		x := parSection[code]
		if x == nil || x.n == 0 {
			continue
		}
		s := Section{
			Effectif: x.n,
			Garder:   pct(x.etats[reponse.EtatGarder], x.n),
			Deplier:  pct(x.etats[reponse.EtatDeplier], x.n),
			Ecarter:  pct(x.etats[reponse.EtatEcarter], x.n),
		}
		if len(x.rangs) > 0 {
			sort.Ints(x.rangs)
			m := float64(x.rangs[len(x.rangs)/2])
			if len(x.rangs)%2 == 0 {
				m = float64(x.rangs[len(x.rangs)/2-1]+x.rangs[len(x.rangs)/2]) / 2
			}
			s.RangMedian = &m
		}
		r.Sections[code] = s
	}
	return r, true
}

// Filtrer omet les questions dont l'effectif est sous le seuil, et les sections de D1 dont l'effectif
// propre est sous le seuil.
func (a Agregats) Filtrer(seuil int) Agregats {
	out := Agregats{Total: a.Total, Questions: map[string]Question{}}
	for id, q := range a.Questions {
		if q.Effectif < seuil {
			continue
		}
		if q.Sections != nil {
			sections := map[string]Section{}
			for c, s := range q.Sections {
				if s.Effectif >= seuil {
					sections[c] = s
				}
			}
			q.Sections = sections
			if len(sections) == 0 {
				q.Sections = nil
			}
		}
		out.Questions[id] = q
	}
	return out
}

// Publier applique le seuil D3 : rien sous le seuil global, puis seulement les questions (et sections) dont
// l'effectif propre atteint le seuil.
func (a Agregats) Publier(seuil int) any {
	if a.Total < seuil {
		return Indisponible{Disponible: false, Seuil: seuil}
	}
	f := a.Filtrer(seuil)
	return Disponible{Disponible: true, Total: f.Total, Seuil: seuil, Questions: f.Questions}
}
