// Package stockage garde les réponses dans SQLite : schéma, écriture, lecture, fermeture et effacement.
// Toutes les requêtes sont paramétrées ; aucune n'est construite par concaténation.
package stockage

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"

	_ "modernc.org/sqlite" // pilote Go pur, sans cgo : seule dépendance tierce (spec §1)
)

// Noms de fichiers du dossier de données.
const (
	FichierBase      = "reponses.db"
	FichierCleIP     = "cle-ip"
	FichierAgregats  = "agregats.json"
	tailleCleIP      = 32
	tentativesIdent  = 8
	tailleIdentifian = 8 // octets, soit 16 caractères hexadécimaux
)

// Erreurs de l'écriture.
var (
	ErrDoublonJeton = errors.New("jeton déjà reçu")
	ErrLimiteIP     = errors.New("limite d'envois par adresse atteinte")
	ErrIntrouvable  = errors.New("réponse introuvable")
)

const schema = `
CREATE TABLE IF NOT EXISTS reponses (
  identifiant  TEXT PRIMARY KEY,
  recue_le     TEXT NOT NULL,
  version      TEXT NOT NULL,
  duree_s      INTEGER NOT NULL,
  ordre_cartes TEXT NOT NULL,
  donnees      TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS pseudos (
  identifiant TEXT PRIMARY KEY REFERENCES reponses(identifiant),
  pseudo      TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS jetons (
  empreinte TEXT PRIMARY KEY
);
CREATE TABLE IF NOT EXISTS empreintes_ip (
  empreinte TEXT PRIMARY KEY,
  envois    INTEGER NOT NULL
);`

// Base est la base de réponses ; une seule connexion d'écriture.
type Base struct {
	db      *sql.DB
	dossier string

	// pointDeControle est remplaçable dans les tests pour simuler un point de contrôle « occupé ».
	pointDeControle func(ctx context.Context) error
}

// Ouvrir crée le dossier de données (0700) et ouvre la base, en mode WAL avec un délai d'attente de 5 s.
// Le processus doit tourner avec umask 077 pour que la base, -wal et -shm soient en 0600.
func Ouvrir(dossier string) (*Base, error) {
	if err := os.MkdirAll(dossier, 0o700); err != nil {
		return nil, fmt.Errorf("dossier de données : %w", err)
	}
	chemin, err := filepath.Abs(filepath.Join(dossier, FichierBase))
	if err != nil {
		return nil, err
	}
	q := url.Values{}
	q.Add("_pragma", "journal_mode(WAL)")
	q.Add("_pragma", "busy_timeout(5000)")
	q.Add("_pragma", "foreign_keys(1)")
	db, err := sql.Open("sqlite", (&url.URL{Scheme: "file", Path: chemin, RawQuery: q.Encode()}).String())
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("schéma : %w", err)
	}
	b := &Base{db: db, dossier: dossier}
	b.pointDeControle = b.checkpointTronque
	return b, nil
}

// Fermer ferme la base.
func (b *Base) Fermer() error { return b.db.Close() }

// Dossier renvoie le dossier de données.
func (b *Base) Dossier() string { return b.dossier }

// DB donne accès à la base pour les tests.
func (b *Base) DB() *sql.DB { return b.db }

func nouvelIdentifiant() (string, error) {
	var o [tailleIdentifian]byte
	if _, err := rand.Read(o[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(o[:]), nil
}
