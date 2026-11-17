package stockage

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/contenu"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
)

// Corriger remplace la réponse d'une question par une valeur JSON (code, texte ou objet D1), avec la
// validation du §5.2, puis réapplique les conditions. La question I1 corrige le pseudo.
func (b *Base) Corriger(ctx context.Context, v *reponse.Validateur, id, question, valeur string) error {
	val, err := v.ValiderUne(question, json.RawMessage(valeur))
	if err != nil {
		return err
	}
	if v.Q.Questions[question].Type == contenu.TypePseudo {
		var p string
		if val != nil {
			_ = json.Unmarshal(val, &p)
		}
		return b.RemplacerPseudo(ctx, id, p)
	}
	l, err := b.Reponse(ctx, id)
	if err != nil {
		return err
	}
	if val == nil {
		delete(l.Donnees, question)
	} else {
		l.Donnees[question] = val
	}
	v.AppliquerConditions(l.Donnees)
	return b.MettreAJourDonnees(ctx, id, l.Donnees)
}

// EffacerQuestion retire une seule réponse ; pour I1, c'est la ligne de pseudos.
func (b *Base) EffacerQuestion(ctx context.Context, v *reponse.Validateur, id, question string) error {
	qu, ok := v.Q.Questions[question]
	if !ok {
		return fmt.Errorf("question inconnue %q", question)
	}
	if qu.Type == contenu.TypePseudo {
		if _, err := b.Reponse(ctx, id); err != nil {
			return err
		}
		return b.SupprimerPseudo(ctx, id)
	}
	l, err := b.Reponse(ctx, id)
	if err != nil {
		return err
	}
	delete(l.Donnees, question)
	v.AppliquerConditions(l.Donnees)
	return b.MettreAJourDonnees(ctx, id, l.Donnees)
}
