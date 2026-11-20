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
	"strings"

	_ "modernc.org/sqlite" // pilote Go pur, sans cgo : dépendance directe (go.mod en compte deux, plus leurs dépendances indirectes)
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

// reponses et pseudos sont WITHOUT ROWID (M4) : sans cela, l'ordre d'arrivée reste lisible dans le rowid, y compris
// dans une sauvegarde, et recoupé avec l'heure du journal il donnerait l'heure de chaque envoi. Les lignes sont
// rangées par identifiant aléatoire ; les tables d'anti-abus gardent leur rowid mais sont vidées à la fermeture.
const schema = `
CREATE TABLE IF NOT EXISTS reponses (
  identifiant  TEXT PRIMARY KEY,
  recue_le     TEXT NOT NULL,
  version      TEXT NOT NULL,
  duree_s      INTEGER NOT NULL,
  ordre_cartes TEXT NOT NULL,
  donnees      TEXT NOT NULL,
  limitee      INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS pseudos (
  identifiant TEXT PRIMARY KEY REFERENCES reponses(identifiant),
  pseudo      TEXT NOT NULL
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS jetons (
  empreinte TEXT PRIMARY KEY
);
CREATE TABLE IF NOT EXISTS empreintes_ip (
  empreinte TEXT PRIMARY KEY,
  envois    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
  cle    TEXT PRIMARY KEY,
  valeur TEXT NOT NULL
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
	if err := verifierSansRowid(db); err != nil {
		db.Close()
		return nil, err
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

// ErrSchemaAncien signale une base créée avant le passage de reponses et pseudos en WITHOUT ROWID (M4).
var ErrSchemaAncien = errors.New("base d'un ancien schéma (tables avec rowid, ordre d'arrivée lisible) : la supprimer avec cle-ip et la recréer")

func verifierSansRowid(db *sql.DB) error {
	for _, t := range []string{"reponses", "pseudos"} {
		var def string
		if err := db.QueryRow(`SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?`, t).Scan(&def); err != nil {
			return fmt.Errorf("schéma : %w", err)
		}
		if !strings.Contains(strings.ToUpper(def), "WITHOUT ROWID") {
			return fmt.Errorf("%w (table %s)", ErrSchemaAncien, t)
		}
	}
	return nil
}
