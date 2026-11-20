package stockage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
)

// Erreurs du cycle de vie.
var (
	ErrAvantFermeture = errors.New("refusé avant UX_FERMETURE : le formulaire accepte encore des réponses")
	ErrPointOccupe    = errors.New("point de contrôle du journal occupé : réessayer")
	ErrJournalNonVide = errors.New("le fichier -wal n'est pas vide : réessayer")
)

// Fermeture exécute la fermeture (§12) : suppression de cle-ip, tables d'anti-abus vidées, VACUUM et
// point de contrôle. Chaque étape est sans effet si elle est déjà faite ; une erreur (point de contrôle
// occupé) veut dire « pas fermé » et la tâche horaire la reprend.
func (b *Base) Fermeture(ctx context.Context, fermeture, maintenant time.Time) error {
	if maintenant.Before(fermeture) {
		return ErrAvantFermeture
	}
	// L'indicateur d'abord : une fermeture interrompue reste une fermeture, et rien ne la rouvre (F1).
	if err := b.noterFermetureFaite(ctx, fermeture); err != nil {
		return err
	}
	if err := os.Remove(filepath.Join(b.dossier, FichierCleIP)); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := b.viderAntiAbus(ctx); err != nil {
		return err
	}
	return b.compacter(ctx)
}

func (b *Base) viderAntiAbus(ctx context.Context) error {
	for _, q := range []string{`DELETE FROM empreintes_ip`, `DELETE FROM jetons`} {
		if _, err := b.db.ExecContext(ctx, q); err != nil {
			return err
		}
	}
	return nil
}

// compacter lance VACUUM puis le point de contrôle, et vérifie que -wal est vide.
func (b *Base) compacter(ctx context.Context) error {
	if _, err := b.db.ExecContext(ctx, `VACUUM`); err != nil {
		return err
	}
	if err := b.pointDeControle(ctx); err != nil {
		return err
	}
	if st, err := os.Stat(filepath.Join(b.dossier, FichierBase+"-wal")); err == nil && st.Size() != 0 {
		return ErrJournalNonVide
	}
	return nil
}

func (b *Base) checkpointTronque(ctx context.Context) error {
	var occupe, journal, deplace int
	if err := b.db.QueryRowContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE)`).Scan(&occupe, &journal, &deplace); err != nil {
		return err
	}
	if occupe != 0 {
		return ErrPointOccupe
	}
	return nil
}

// Instantane produit le contenu de agregats.json à partir des réponses (même contenu que l'export agregats).
type Instantane func(lignes []reponse.Ligne) ([]byte, error)

// Effacement exécute l'effacement idempotent (§12) : instantané des agrégats (écrit une seule fois), puis
// réponses et pseudos vidés, VACUUM et point de contrôle. Il refuse avant la fermeture. Une reprise après
// une interruption ne remplace jamais un agregats.json existant.
func (b *Base) Effacement(ctx context.Context, fermeture, maintenant time.Time, instantane Instantane) error {
	if maintenant.Before(fermeture) {
		return ErrAvantFermeture
	}
	if err := b.noterFermetureFaite(ctx, fermeture); err != nil {
		return err
	}
	chemin := filepath.Join(b.dossier, FichierAgregats)
	if _, err := os.Stat(chemin); errors.Is(err, os.ErrNotExist) {
		lignes, err := b.Reponses(ctx)
		if err != nil {
			return err
		}
		contenu, err := instantane(lignes)
		if err != nil {
			return err
		}
		if err := ecrireAtomique(b.dossier, FichierAgregats, contenu); err != nil {
			return err
		}
	} else if err != nil {
		return err
	}
	for _, q := range []string{`DELETE FROM pseudos`, `DELETE FROM reponses`, `DELETE FROM empreintes_ip`, `DELETE FROM jetons`} {
		if _, err := b.db.ExecContext(ctx, q); err != nil {
			return err
		}
	}
	if err := os.Remove(filepath.Join(b.dossier, FichierCleIP)); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	// Exports et sauvegardes contiennent des pseudos et des textes libres : ils ne survivent pas à l'effacement (M2).
	if err := b.supprimerCopies(); err != nil {
		return err
	}
	return b.compacter(ctx)
}

// Dossiers d'exports et de sauvegardes dans le dossier de données, et préfixe des exports qui survivent.
const (
	DossierExports       = "exports"
	DossierSauvegardes   = "sauvegardes"
	prefixeAgregatsGarde = "agregats-"
)

// supprimerCopies supprime sauvegardes/ et tout ce qui est dans exports/ sauf les fichiers agregats-* (le seul
// jeu gardé après l'effacement). Sans effet si les dossiers n'existent pas ; idempotent.
func (b *Base) supprimerCopies() error {
	if err := os.RemoveAll(filepath.Join(b.dossier, DossierSauvegardes)); err != nil {
		return err
	}
	exports := filepath.Join(b.dossier, DossierExports)
	entrees, err := os.ReadDir(exports)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, e := range entrees {
		if !e.IsDir() && strings.HasPrefix(e.Name(), prefixeAgregatsGarde) {
			continue
		}
		if err := os.RemoveAll(filepath.Join(exports, e.Name())); err != nil {
			return err
		}
	}
	return nil
}

// EcrireAtomique écrit un fichier de données : .tmp, fsync, renommage, fsync du dossier.
func ecrireAtomique(dossier, nom string, contenu []byte) error {
	tmp := filepath.Join(dossier, nom+".tmp")
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	if _, err := f.Write(contenu); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmp, filepath.Join(dossier, nom)); err != nil {
		return err
	}
	d, err := os.Open(dossier)
	if err != nil {
		return err
	}
	defer d.Close()
	if err := d.Sync(); err != nil {
		return fmt.Errorf("fsync du dossier : %w", err)
	}
	return nil
}

// Sauvegarder écrit une copie cohérente de la base par VACUUM INTO, en 0600. cle-ip n'y entre jamais.
func (b *Base) Sauvegarder(ctx context.Context, fichier string) error {
	if err := b.VerifierSortie(DossierSauvegardes, fichier); err != nil {
		return err
	}
	if _, err := os.Stat(fichier); err == nil {
		return fmt.Errorf("%s existe déjà", fichier)
	}
	if _, err := b.db.ExecContext(ctx, `VACUUM INTO ?`, fichier); err != nil {
		return err
	}
	if err := viderAntiAbusDansCopie(ctx, fichier); err != nil {
		os.Remove(fichier) // pas de copie à moitié nettoyée
		return err
	}
	return os.Chmod(fichier, 0o600)
}

// viderAntiAbusDansCopie retire de la copie les jetons et les empreintes d'IP (R4, M3), puis compacte pour que
// leurs pages ne restent pas dans le fichier.
func viderAntiAbusDansCopie(ctx context.Context, fichier string) error {
	chemin, err := filepath.Abs(fichier)
	if err != nil {
		return err
	}
	db, err := sql.Open("sqlite", (&url.URL{Scheme: "file", Path: chemin}).String())
	if err != nil {
		return err
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	for _, q := range []string{`DELETE FROM empreintes_ip`, `DELETE FROM jetons`, `VACUUM`} {
		if _, err := db.ExecContext(ctx, q); err != nil {
			return err
		}
	}
	return nil
}

// ErrSortieHorsDossier signale un chemin de sortie hors de exports/ ou de sauvegardes/ du dossier de données :
// l'effacement ne supprimerait pas un tel fichier (N2).
var ErrSortieHorsDossier = errors.New("le fichier de sortie doit être dans exports/ (export) ou sauvegardes/ (sauvegarder) du dossier de données")

// VerifierSortie refuse un chemin qui n'est pas sous <dossier de données>/<sous>/ : chemins relatifs et « .. »
// ramenés à leur forme absolue, liens symboliques du dossier parent suivis. Le dossier du fichier est créé (0700).
func (b *Base) VerifierSortie(sous, chemin string) error {
	racine, err := filepath.Abs(filepath.Join(b.dossier, sous))
	if err != nil {
		return err
	}
	if r, err := filepath.EvalSymlinks(racine); err == nil {
		racine = r
	}
	cible, err := filepath.Abs(chemin)
	if err != nil {
		return err
	}
	if r, err := filepath.EvalSymlinks(filepath.Dir(cible)); err == nil {
		cible = filepath.Join(r, filepath.Base(cible))
	}
	rel, err := filepath.Rel(racine, cible)
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return fmt.Errorf("%w : %s", ErrSortieHorsDossier, chemin)
	}
	return os.MkdirAll(filepath.Dir(cible), 0o700) // l'image n'a pas de shell pour un mkdir
}
