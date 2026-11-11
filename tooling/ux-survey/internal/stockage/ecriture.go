package stockage

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
)

// Envoi décrit une réponse à enregistrer en une seule transaction.
type Envoi struct {
	reponse.Normalisee
	Version     string
	Jeton       string // le jeton en clair ; seule son empreinte est écrite
	EmpreinteIP string
	MaxParIP    int
	RecueLe     string // AAAA-MM-JJ
	Fermeture   string // UX_FERMETURE en RFC 3339 : mémorisée à la première réponse (R5)
}

// Ecrire enregistre réponse, pseudo, jeton et compteur d'adresse dans une seule transaction.
// Il renvoie ErrDoublonJeton ou ErrLimiteIP sans rien écrire.
func (b *Base) Ecrire(ctx context.Context, e Envoi) (string, error) {
	tx, err := b.db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback()

	res, err := tx.ExecContext(ctx, `INSERT INTO jetons (empreinte) VALUES (?) ON CONFLICT DO NOTHING`, EmpreinteJeton(e.Jeton))
	if err != nil {
		return "", err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return "", ErrDoublonJeton
	}
	var envois int
	err = tx.QueryRowContext(ctx, `SELECT envois FROM empreintes_ip WHERE empreinte = ?`, e.EmpreinteIP).Scan(&envois)
	if err != nil && err != sql.ErrNoRows {
		return "", err
	}
	if envois >= e.MaxParIP {
		return "", ErrLimiteIP
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO empreintes_ip (empreinte, envois) VALUES (?, 1)
		ON CONFLICT(empreinte) DO UPDATE SET envois = envois + 1`, e.EmpreinteIP); err != nil {
		return "", err
	}
	if e.Fermeture != "" {
		if _, err := tx.ExecContext(ctx, `INSERT INTO meta (cle, valeur) VALUES ('fermeture', ?) ON CONFLICT DO NOTHING`, e.Fermeture); err != nil {
			return "", err
		}
	}
	donnees, err := json.Marshal(e.Donnees)
	if err != nil {
		return "", err
	}
	ordre, _ := json.Marshal(e.OrdreCartes)
	if e.OrdreCartes == nil {
		ordre = []byte("[]")
	}
	var id string
	for range tentativesIdent {
		if id, err = nouvelIdentifiant(); err != nil {
			return "", err
		}
		res, err = tx.ExecContext(ctx, `INSERT INTO reponses (identifiant, recue_le, version, duree_s, ordre_cartes, donnees)
			VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT DO NOTHING`, id, e.RecueLe, e.Version, e.DureeS, string(ordre), string(donnees))
		if err != nil {
			return "", err
		}
		if n, _ := res.RowsAffected(); n == 1 {
			break
		}
		id = ""
	}
	if id == "" {
		return "", sql.ErrConnDone // collision d'identifiants répétée : pratiquement impossible
	}
	if e.Pseudo != "" {
		if _, err := tx.ExecContext(ctx, `INSERT INTO pseudos (identifiant, pseudo) VALUES (?, ?)`, id, e.Pseudo); err != nil {
			return "", err
		}
	}
	return id, tx.Commit()
}

// Reponses lit les réponses utilisables, sans pseudo, triées par identifiant (jamais par ordre d'arrivée) :
// celles marquées « limitées » (R13) en sont exclues. Statistiques, exports et instantané passent par elle.
func (b *Base) Reponses(ctx context.Context) ([]reponse.Ligne, error) {
	return b.lire(ctx, `WHERE limitee = 0`)
}

// ToutesLesReponses lit aussi les réponses limitées ; réservé aux commandes de droits.
func (b *Base) ToutesLesReponses(ctx context.Context) ([]reponse.Ligne, error) {
	return b.lire(ctx, ``)
}

func (b *Base) lire(ctx context.Context, filtre string) ([]reponse.Ligne, error) {
	rows, err := b.db.QueryContext(ctx, `SELECT identifiant, recue_le, version, duree_s, ordre_cartes, donnees, limitee FROM reponses `+filtre+` ORDER BY identifiant`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []reponse.Ligne
	for rows.Next() {
		l, err := lireLigne(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

// Reponse lit une réponse par identifiant.
func (b *Base) Reponse(ctx context.Context, id string) (reponse.Ligne, error) {
	row := b.db.QueryRowContext(ctx, `SELECT identifiant, recue_le, version, duree_s, ordre_cartes, donnees, limitee FROM reponses WHERE identifiant = ?`, id)
	l, err := lireLigne(row)
	if err == sql.ErrNoRows {
		return l, ErrIntrouvable
	}
	return l, err
}

type scanner interface{ Scan(...any) error }

func lireLigne(s scanner) (reponse.Ligne, error) {
	var l reponse.Ligne
	var ordre, donnees string
	var limitee int
	if err := s.Scan(&l.Identifiant, &l.RecueLe, &l.Version, &l.DureeS, &ordre, &donnees, &limitee); err != nil {
		return l, err
	}
	l.Limitee = limitee != 0
	if err := json.Unmarshal([]byte(ordre), &l.OrdreCartes); err != nil {
		return l, err
	}
	if err := json.Unmarshal([]byte(donnees), &l.Donnees); err != nil {
		return l, err
	}
	return l, nil
}

// Pseudo associe un pseudo à l'identifiant de sa réponse.
type Pseudo struct{ Identifiant, Pseudo string }

// Pseudos lit la table de correspondance (jamais exportée avec les réponses).
func (b *Base) Pseudos(ctx context.Context) ([]Pseudo, error) {
	rows, err := b.db.QueryContext(ctx, `SELECT identifiant, pseudo FROM pseudos ORDER BY identifiant`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Pseudo
	for rows.Next() {
		var p Pseudo
		if err := rows.Scan(&p.Identifiant, &p.Pseudo); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Chercher renvoie les réponses d'un pseudo, sans tenir compte de la casse ni des espaces de bord.
func (b *Base) Chercher(ctx context.Context, pseudo string) ([]reponse.Ligne, error) {
	tous, err := b.Pseudos(ctx)
	if err != nil {
		return nil, err
	}
	var out []reponse.Ligne
	for _, p := range tous {
		if strings.EqualFold(strings.TrimSpace(p.Pseudo), strings.TrimSpace(pseudo)) {
			l, err := b.Reponse(ctx, p.Identifiant)
			if err != nil {
				return nil, err
			}
			out = append(out, l)
		}
	}
	return out, nil
}

// MettreAJourDonnees remplace le JSON des réponses d'un identifiant (correction d'une réponse).
func (b *Base) MettreAJourDonnees(ctx context.Context, id string, donnees map[string]json.RawMessage) error {
	brut, err := json.Marshal(donnees)
	if err != nil {
		return err
	}
	res, err := b.db.ExecContext(ctx, `UPDATE reponses SET donnees = ? WHERE identifiant = ?`, string(brut), id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrIntrouvable
	}
	return nil
}

// RemplacerPseudo remplace (ou crée) le pseudo d'une réponse ; un pseudo vide supprime la ligne.
func (b *Base) RemplacerPseudo(ctx context.Context, id, pseudo string) error {
	if _, err := b.Reponse(ctx, id); err != nil {
		return err
	}
	if pseudo == "" {
		return b.SupprimerPseudo(ctx, id)
	}
	_, err := b.db.ExecContext(ctx, `INSERT INTO pseudos (identifiant, pseudo) VALUES (?, ?)
		ON CONFLICT(identifiant) DO UPDATE SET pseudo = excluded.pseudo`, id, pseudo)
	return err
}

// SupprimerPseudo supprime la seule ligne de pseudos d'une réponse.
func (b *Base) SupprimerPseudo(ctx context.Context, id string) error {
	_, err := b.db.ExecContext(ctx, `DELETE FROM pseudos WHERE identifiant = ?`, id)
	return err
}

// SupprimerReponse supprime la réponse et sa ligne de pseudos, dans une transaction.
func (b *Base) SupprimerReponse(ctx context.Context, id string) error {
	tx, err := b.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM pseudos WHERE identifiant = ?`, id); err != nil {
		return err
	}
	res, err := tx.ExecContext(ctx, `DELETE FROM reponses WHERE identifiant = ?`, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrIntrouvable
	}
	return tx.Commit()
}

// Compte renvoie le nombre de lignes d'une table du schéma (pour les tests et la sortie des commandes).
func (b *Base) Compte(ctx context.Context, table string) (int, error) {
	switch table {
	case "reponses", "pseudos", "jetons", "empreintes_ip":
	default:
		return 0, sql.ErrNoRows
	}
	var n int
	// le nom de table vient d'une liste fermée ci-dessus, jamais d'une entrée externe
	err := b.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+table).Scan(&n)
	return n, err
}

// Limiter marque (ou ne marque plus) une réponse comme « limitée » (R13) : elle reste stockée mais sort
// des statistiques de l'écran de fin, des exports suivants et de l'instantané des agrégats.
func (b *Base) Limiter(ctx context.Context, id string, limitee bool) error {
	v := 0
	if limitee {
		v = 1
	}
	res, err := b.db.ExecContext(ctx, `UPDATE reponses SET limitee = ? WHERE identifiant = ?`, v, id)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrIntrouvable
	}
	return nil
}

// ErrFermetureRepoussee signale une UX_FERMETURE plus tardive que celle déjà annoncée (R5).
var ErrFermetureRepoussee = errors.New("UX_FERMETURE ne peut pas être repoussée après la première réponse reçue : la date déjà annoncée reste la limite")

// VerifierFermeture applique R5 : une fois une réponse reçue, la date de fermeture peut être avancée, jamais
// repoussée. Une date plus tardive que la date mémorisée est refusée ; une date plus proche la remplace.
func (b *Base) VerifierFermeture(ctx context.Context, fermeture time.Time) error {
	var v string
	err := b.db.QueryRowContext(ctx, `SELECT valeur FROM meta WHERE cle = 'fermeture'`).Scan(&v)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return err
	}
	connue, err := time.Parse(time.RFC3339, v)
	if err != nil {
		return err
	}
	if fermeture.After(connue) {
		return fmt.Errorf("%w (mémorisée : %s)", ErrFermetureRepoussee, v)
	}
	if fermeture.Before(connue) {
		_, err = b.db.ExecContext(ctx, `UPDATE meta SET valeur = ? WHERE cle = 'fermeture'`, fermeture.Format(time.RFC3339))
	}
	return err
}
