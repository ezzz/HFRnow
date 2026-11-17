package stockage

import (
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/testutil"
	_ "modernc.org/sqlite"
)

// M4 : reponses et pseudos sont WITHOUT ROWID, donc rangées par identifiant aléatoire : aucun ordre d'arrivée
// n'est lisible, ni par rowid ni par un parcours de la table, ni dans une sauvegarde.
func TestSansRowidPasDOrdreDArrivee(t *testing.T) {
	b := ouvrir(t)
	for i := 1; i <= 12; i++ {
		if _, err := ecrire(t, b, i, "203.0.113."+string(rune(0x40+i)), "Pseudo", nil); err != nil {
			t.Fatal(err)
		}
	}
	for _, table := range []string{"reponses", "pseudos"} {
		if _, err := b.DB().QueryContext(ctx, `SELECT rowid FROM `+table); err == nil {
			t.Errorf("%s a un rowid : l'ordre d'arrivée est lisible", table)
		}
	}
	// Parcours sans ORDER BY : l'ordre rendu est celui de la clé, pas celui des insertions.
	rows, err := b.DB().QueryContext(ctx, `SELECT identifiant FROM reponses`)
	if err != nil {
		t.Fatal(err)
	}
	var vus []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		vus = append(vus, id)
	}
	rows.Close()
	if !sort.StringsAreSorted(vus) {
		t.Errorf("le parcours suit autre chose que l'identifiant : %v", vus)
	}
	// Une sauvegarde garde ce rangement.
	dest := filepath.Join(b.Dossier(), "sauvegardes", "copie.db")
	if err := b.Sauvegarder(ctx, dest); err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite", "file:"+dest)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Query(`SELECT rowid FROM reponses`); err == nil {
		t.Error("la sauvegarde a un rowid sur reponses")
	}
}

// Une base d'un ancien schéma (avec rowid) est refusée au lieu d'être gardée en silence.
func TestSchemaAncienRefuse(t *testing.T) {
	dossier := filepath.Join(t.TempDir(), "donnees")
	if err := os.MkdirAll(dossier, 0o700); err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite", "file:"+filepath.Join(dossier, FichierBase))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`CREATE TABLE reponses (identifiant TEXT PRIMARY KEY, recue_le TEXT NOT NULL, version TEXT NOT NULL,
		duree_s INTEGER NOT NULL, ordre_cartes TEXT NOT NULL, donnees TEXT NOT NULL, limitee INTEGER NOT NULL DEFAULT 0);
		CREATE TABLE pseudos (identifiant TEXT PRIMARY KEY, pseudo TEXT NOT NULL)`); err != nil {
		t.Fatal(err)
	}
	db.Close()
	if _, err := Ouvrir(dossier); !errors.Is(err, ErrSchemaAncien) {
		t.Errorf("base à rowid : %v", err)
	}
}

// M3 : la sauvegarde ne contient ni jetons ni empreintes d'IP, ni dans les tables ni dans le fichier.
func TestSauvegardeSansJetonsNiEmpreintes(t *testing.T) {
	b := ouvrir(t)
	remplir(t, b, 6)
	if n, _ := b.Compte(ctx, "jetons"); n != 6 {
		t.Fatalf("la base vivante garde ses jetons : %d", n)
	}
	dest := filepath.Join(b.Dossier(), "sauvegardes", "copie.db")
	if err := b.Sauvegarder(ctx, dest); err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite", "file:"+dest+"?mode=ro")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for table, attendu := range map[string]int{"jetons": 0, "empreintes_ip": 0, "reponses": 6} {
		var n int
		if err := db.QueryRow(`SELECT count(*) FROM ` + table).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != attendu {
			t.Errorf("copie, %s : %d lignes, attendu %d", table, n, attendu)
		}
	}
	brut, _ := os.ReadFile(dest)
	for i := 1; i <= 6; i++ {
		if strings.Contains(string(brut), EmpreinteJeton(jetonDeTest(i))) {
			t.Errorf("l'empreinte du jeton %d reste dans le fichier (pages non compactées)", i)
		}
	}
	for _, s := range []string{"-wal", "-shm"} {
		if _, err := os.Stat(dest + s); err == nil {
			t.Errorf("fichier %s laissé à côté de la copie", s)
		}
	}
	if st, _ := os.Stat(dest); st.Mode().Perm() != 0o600 {
		t.Errorf("copie en %v", st.Mode().Perm())
	}
}

// M2 : l'effacement supprime sauvegardes/ et les exports hors agregats-*, et il est idempotent.
func TestEffacementSupprimeExportsEtSauvegardes(t *testing.T) {
	b := ouvrir(t)
	remplir(t, b, 3)
	d := b.Dossier()
	for _, f := range []string{"exports/analyse-2026-12-16.csv", "exports/pseudos-2026-12-16.csv", "exports/agregats-2026-12-16.csv",
		"exports/agregats-2026-12-16.json", "exports/divers/essai.txt", "sauvegardes/copie.db"} {
		p := filepath.Join(d, f)
		if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte("pseudo en clair"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	fermeture := time.Date(2026, 12, 15, 22, 0, 0, 0, time.UTC)
	for i := 0; i < 2; i++ { // la seconde exécution ne change rien
		if err := b.Effacement(ctx, fermeture, fermeture.Add(time.Second), instantane); err != nil {
			t.Fatal(err)
		}
	}
	reste := func(f string) bool { _, err := os.Stat(filepath.Join(d, f)); return err == nil }
	for _, f := range []string{"exports/analyse-2026-12-16.csv", "exports/pseudos-2026-12-16.csv", "exports/divers", "sauvegardes"} {
		if reste(f) {
			t.Errorf("%s survit à l'effacement", f)
		}
	}
	for _, f := range []string{"exports/agregats-2026-12-16.csv", "exports/agregats-2026-12-16.json", FichierAgregats} {
		if !reste(f) {
			t.Errorf("%s doit être gardé", f)
		}
	}
	// Sans dossiers : sans effet, sans erreur.
	b2 := ouvrir(t)
	if err := b2.Effacement(ctx, fermeture, fermeture.Add(time.Second), instantane); err != nil {
		t.Errorf("sans exports ni sauvegardes : %v", err)
	}
}

// F1 : après une fermeture exécutée, aucune UX_FERMETURE plus tardive n'est acceptée, quel que soit le décalage horaire.
func TestFermetureExecuteeNeRouvrePas(t *testing.T) {
	b := ouvrir(t)
	remplir(t, b, 2)
	// Fermeture exécutée à 2026-11-15T00:00:01+01:00 (23:00:01Z la veille).
	f := time.Date(2026, 11, 15, 0, 0, 1, 0, time.FixedZone("", 3600))
	if err := b.Fermeture(ctx, f, f.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	// Même jour calendaire, mais le 15 à 23:59:59 en -12:00 : plus de 36 heures plus tard.
	loin := time.Date(2026, 11, 15, 23, 59, 59, 0, time.FixedZone("", -12*3600))
	if JourFermeture(loin) != JourFermeture(f) {
		t.Fatal("le cas d'essai doit garder le même jour")
	}
	if err := b.VerifierFermeture(ctx, loin); !errors.Is(err, ErrReouverture) {
		t.Errorf("la valeur -12:00 rouvre le formulaire : %v", err)
	}
	if err := b.VerifierFermeture(ctx, f.Add(time.Second)); !errors.Is(err, ErrReouverture) {
		t.Errorf("une seconde plus tard rouvre aussi : %v", err)
	}
	if err := b.VerifierFermeture(ctx, f); err != nil {
		t.Errorf("la même valeur : %v", err)
	}
	if err := b.VerifierFermeture(ctx, f.Add(-time.Hour)); err != nil {
		t.Errorf("avancer reste permis : %v", err)
	}
}

// Le même indicateur est posé par l'effacement (commande effacer sans passer par fermer).
func TestEffacementPoseIndicateur(t *testing.T) {
	b := ouvrir(t)
	f := time.Date(2026, 12, 15, 22, 0, 0, 0, time.UTC)
	if err := b.Effacement(ctx, f, f.Add(time.Second), instantane); err != nil {
		t.Fatal(err)
	}
	if err := b.VerifierFermeture(ctx, f.Add(24*time.Hour)); !errors.Is(err, ErrReouverture) {
		t.Errorf("après effacement : %v", err)
	}
}

func jetonDeTest(n int) string { return testutil.Jeton(n) }
