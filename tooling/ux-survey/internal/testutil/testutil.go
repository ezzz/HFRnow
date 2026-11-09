// Package testutil regroupe les aides des tests : contenu, envois, jetons.
package testutil

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	uxsurvey "github.com/ezzz/hfrnow/tooling/ux-survey"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/contenu"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
)

// Questionnaire charge le contenu embarqué.
func Questionnaire(t testing.TB) *contenu.Questionnaire {
	t.Helper()
	q, err := contenu.Charger(uxsurvey.ContenuJSON())
	if err != nil {
		t.Fatal(err)
	}
	return q
}

// Jeton renvoie un jeton valide (32 caractères hexadécimaux) propre à n.
func Jeton(n int) string { return fmt.Sprintf("%032x", n+1) }

// Reponses fabrique le champ reponses d'un envoi à partir de valeurs Go.
func Reponses(t testing.TB, m map[string]any) map[string]json.RawMessage {
	t.Helper()
	out := map[string]json.RawMessage{}
	for k, v := range m {
		b, err := json.Marshal(v)
		if err != nil {
			t.Fatal(err)
		}
		out[k] = b
	}
	return out
}

// Envoi fabrique un envoi valide pour la version du contenu, avec les réponses données.
func Envoi(t testing.TB, q *contenu.Questionnaire, jeton string, m map[string]any) *reponse.Envoi {
	t.Helper()
	return &reponse.Envoi{Version: q.Version, Jeton: jeton, DureeS: json.RawMessage("312"), Reponses: Reponses(t, m)}
}

// Chaine renvoie une chaîne de n caractères « a ».
func Chaine(n int) string { return strings.Repeat("a", n) }

// D1 fabrique une réponse D1 : sections {code, etat, rang}.
func D1(comme bool, sections ...map[string]any) map[string]any {
	l := make([]any, len(sections))
	for i, s := range sections {
		l[i] = s
	}
	m := map[string]any{"comme_aujourdhui": comme}
	if len(l) > 0 {
		m["sections"] = l
	}
	return m
}

// Sec fabrique une section de D1 ; un rang de 0 n'est pas écrit.
func Sec(code, etat string, rang int) map[string]any {
	m := map[string]any{"code": code, "etat": etat}
	if rang > 0 {
		m["rang"] = rang
	}
	return m
}
