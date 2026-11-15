// Commande ux-survey : le service du questionnaire UX et ses commandes d'exploitation.
//
//	ux-survey serve
//	ux-survey export --format analyse|agregats|pseudos --sortie <préfixe>
//	ux-survey sauvegarder <fichier>
//	ux-survey fermer
//	ux-survey effacer
//	ux-survey pseudo --chercher <pseudo> | --afficher <id> | --corriger <id> --question <ID> --valeur-json <v> |
//	                 --effacer-question <id> --question <ID> | --effacer-pseudo <id> | --effacer <id>
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	uxsurvey "github.com/ezzz/hfrnow/tooling/ux-survey"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/contenu"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stockage"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/web"
	"net/http"
)

func main() {
	// umask 077 : base, -wal, -shm et cle-ip en 0600, dossier de données en 0700.
	syscall.Umask(0o077)
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	if err := lancer(os.Args[1], os.Args[2:]); err != nil {
		fmt.Fprintln(os.Stderr, "erreur :", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage : ux-survey serve | export | sauvegarder | fermer | effacer | pseudo  (voir README.md)")
}

// env regroupe ce que toutes les commandes chargent : configuration, contenu et base.
type env struct {
	cfg  *contenu.Config
	q    *contenu.Questionnaire
	base *stockage.Base
}

func charger() (*env, error) {
	cfg, err := contenu.ChargerConfig(os.Getenv)
	if err != nil {
		return nil, err
	}
	q, err := contenu.Charger(uxsurvey.ContenuJSON())
	if err != nil {
		return nil, err
	}
	base, err := stockage.Ouvrir(cfg.Donnees)
	if err != nil {
		return nil, err
	}
	if err := base.VerifierFermeture(context.Background(), cfg.Fermeture); err != nil {
		base.Fermer()
		return nil, err
	}
	return &env{cfg: cfg, q: q, base: base}, nil
}

func lancer(commande string, args []string) error {
	switch commande {
	case "serve":
		return serve()
	case "export":
		return commandeExport(args)
	case "sauvegarder":
		return commandeSauvegarder(args)
	case "fermer":
		return commandeFermer()
	case "effacer":
		return commandeEffacer()
	case "pseudo":
		return commandePseudo(args)
	default:
		usage()
		return fmt.Errorf("commande inconnue %q", commande)
	}
}

func serve() error {
	e, err := charger()
	if err != nil {
		return err
	}
	defer e.base.Fermer()
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	s, err := web.Nouveau(e.cfg, e.q, uxsurvey.ContenuJSON(), uxsurvey.Web(), e.base, log, time.Now)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go s.Boucle(ctx)

	srv := &http.Server{
		Addr: e.cfg.Adresse, Handler: s.Handler(),
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second,
		WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 << 10,
	}
	go func() {
		<-ctx.Done()
		c, annuler := context.WithTimeout(context.Background(), 10*time.Second)
		defer annuler()
		_ = srv.Shutdown(c)
	}()
	log.Info("démarrage", "adresse", e.cfg.Adresse, "version", e.q.Version, "ouvert", s.Ouvert())
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}
