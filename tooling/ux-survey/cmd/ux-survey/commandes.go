package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/exporter"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stats"
)

func commandeExport(args []string) error {
	fs := flag.NewFlagSet("export", flag.ContinueOnError)
	format := fs.String("format", "", "analyse, agregats ou pseudos")
	sortie := fs.String("sortie", "", "préfixe des fichiers produits ; la date et l'extension sont ajoutées")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *format == "" || *sortie == "" {
		return fmt.Errorf("--format et --sortie sont obligatoires")
	}
	e, err := charger()
	if err != nil {
		return err
	}
	defer e.base.Fermer()
	ctx := context.Background()
	date := time.Now().In(e.cfg.Fermeture.Location()).Format(time.DateOnly)
	ecrire := func(ext string, contenu []byte, err error) error {
		if err != nil {
			return err
		}
		nom := fmt.Sprintf("%s-%s.%s", *sortie, date, ext)
		if err := os.WriteFile(nom, contenu, 0o600); err != nil {
			return err
		}
		fmt.Println(nom)
		return nil
	}
	switch *format {
	case "analyse":
		lignes, err := e.base.Reponses(ctx)
		if err != nil {
			return err
		}
		c, err := exporter.AnalyseCSV(e.q, lignes)
		if err := ecrire("csv", c, err); err != nil {
			return err
		}
		j, err := exporter.AnalyseJSON(e.q, lignes)
		return ecrire("json", j, err)
	case "agregats":
		a, err := agregatsCourants(ctx, e)
		if err != nil {
			return err
		}
		c, err := exporter.AgregatsCSV(a)
		if err := ecrire("csv", c, err); err != nil {
			return err
		}
		j, err := exporter.AgregatsJSON(a)
		return ecrire("json", j, err)
	case "pseudos":
		p, err := e.base.Pseudos(ctx)
		if err != nil {
			return err
		}
		c, err := exporter.PseudosCSV(p)
		return ecrire("csv", c, err)
	}
	return fmt.Errorf("format inconnu %q", *format)
}

// agregatsCourants lit l'instantané s'il existe (après l'effacement), sinon calcule sur la base.
func agregatsCourants(ctx context.Context, e *env) (stats.Agregats, error) {
	if brut, err := os.ReadFile(e.cfg.Donnees + "/agregats.json"); err == nil {
		var a stats.Agregats
		return a, json.Unmarshal(brut, &a)
	}
	lignes, err := e.base.Reponses(ctx)
	if err != nil {
		return stats.Agregats{}, err
	}
	return stats.Calculer(e.q, lignes), nil
}

func commandeSauvegarder(args []string) error {
	if len(args) != 1 {
		return fmt.Errorf("usage : ux-survey sauvegarder <fichier>")
	}
	e, err := charger()
	if err != nil {
		return err
	}
	defer e.base.Fermer()
	if err := e.base.Sauvegarder(context.Background(), args[0]); err != nil {
		return err
	}
	fmt.Println("sauvegarde écrite :", args[0], "(sans cle-ip ; à supprimer à la date d'effacement)")
	return nil
}

func commandeFermer() error {
	e, err := charger()
	if err != nil {
		return err
	}
	defer e.base.Fermer()
	if err := e.base.Fermeture(context.Background(), e.cfg.Fermeture, time.Now()); err != nil {
		return err
	}
	fmt.Println("fermeture faite : cle-ip supprimée, empreintes et jetons vidés, journal vide")
	return nil
}

func commandeEffacer() error {
	e, err := charger()
	if err != nil {
		return err
	}
	defer e.base.Fermer()
	instantane := func(l []reponse.Ligne) ([]byte, error) {
		return exporter.AgregatsJSON(stats.Calculer(e.q, l))
	}
	if err := e.base.Effacement(context.Background(), e.cfg.Fermeture, time.Now(), instantane); err != nil {
		return err
	}
	fmt.Println("effacement terminé")
	return nil
}

func commandePseudo(args []string) error {
	fs := flag.NewFlagSet("pseudo", flag.ContinueOnError)
	chercher := fs.String("chercher", "", "pseudo à chercher (sans la casse ni les espaces de bord)")
	afficher := fs.String("afficher", "", "identifiant de la réponse à afficher")
	corriger := fs.String("corriger", "", "identifiant de la réponse à corriger (avec --question et --valeur-json)")
	effQuestion := fs.String("effacer-question", "", "identifiant de la réponse dont retirer une question (avec --question)")
	effPseudo := fs.String("effacer-pseudo", "", "identifiant dont supprimer la seule ligne de pseudos")
	limiter := fs.String("limiter", "", "identifiant à marquer « limitée » (R13) : gardée, exclue des statistiques et des exports")
	leverLimite := fs.String("lever-limite", "", "identifiant dont lever la limitation")
	effacer := fs.String("effacer", "", "identifiant dont supprimer la réponse et le pseudo")
	question := fs.String("question", "", "identifiant de question, par exemple L2")
	valeur := fs.String("valeur-json", "", "nouvelle valeur JSON : un code, un texte entre guillemets ou un objet D1")
	if err := fs.Parse(args); err != nil {
		return err
	}
	e, err := charger()
	if err != nil {
		return err
	}
	defer e.base.Fermer()
	ctx := context.Background()
	v := &reponse.Validateur{Q: e.q}
	switch {
	case *chercher != "":
		lignes, err := e.base.Chercher(ctx, *chercher)
		if err != nil {
			return err
		}
		for _, l := range lignes {
			note := ""
			if l.Limitee {
				note = " (limitée)"
			}
			fmt.Println(l.Identifiant, l.RecueLe+note)
		}
		fmt.Printf("%d réponse(s)\n", len(lignes))
	case *afficher != "":
		l, err := e.base.Reponse(ctx, *afficher)
		if err != nil {
			return err
		}
		b, _ := json.MarshalIndent(l.Donnees, "", "  ")
		fmt.Printf("%s %s\n%s\n", l.Identifiant, l.RecueLe, b)
	case *corriger != "":
		if *question == "" || *valeur == "" {
			return fmt.Errorf("--corriger demande --question et --valeur-json")
		}
		if err := e.base.Corriger(ctx, v, *corriger, *question, *valeur); err != nil {
			return err
		}
		fmt.Println("corrigé ; refaire un export d'analyse et demander aux destinataires de remplacer leur copie")
	case *effQuestion != "":
		if *question == "" {
			return fmt.Errorf("--effacer-question demande --question")
		}
		if err := e.base.EffacerQuestion(ctx, v, *effQuestion, *question); err != nil {
			return err
		}
		fmt.Println("réponse retirée ; refaire un export d'analyse")
	case *effPseudo != "":
		if err := e.base.SupprimerPseudo(ctx, *effPseudo); err != nil {
			return err
		}
		fmt.Println("pseudo supprimé ; la réponse reste")
	case *limiter != "":
		if err := e.base.Limiter(ctx, *limiter, true); err != nil {
			return err
		}
		fmt.Println("réponse limitée : exclue des statistiques et des exports suivants ; refaire un export d'analyse et demander aux destinataires de remplacer leur copie")
	case *leverLimite != "":
		if err := e.base.Limiter(ctx, *leverLimite, false); err != nil {
			return err
		}
		fmt.Println("limitation levée")
	case *effacer != "":
		if err := e.base.SupprimerReponse(ctx, *effacer); err != nil {
			return err
		}
		fmt.Println("réponse et pseudo supprimés ; refaire un export d'analyse")
	default:
		return fmt.Errorf("une action est demandée : --chercher, --afficher, --corriger, --effacer-question, --effacer-pseudo, --limiter, --lever-limite ou --effacer")
	}
	return nil
}
