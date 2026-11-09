// Package web porte les routes, les en-têtes, les limites de débit et les journaux du service.
package web

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/contenu"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/exporter"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stats"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stockage"
)

// Serveur est le service HTTP du questionnaire.
type Serveur struct {
	Cfg     *contenu.Config
	Q       *contenu.Questionnaire
	Base    *stockage.Base
	Log     *slog.Logger
	Horloge func() time.Time
	Lim     *Limiteur

	val       *reponse.Validateur
	cache     *stats.Cache
	pages     map[string][]byte // "/" et "/donnees", valeurs de configuration déjà remplacées
	statiques map[string]*fichier
	contenuJS []byte

	mu         sync.RWMutex
	cleIP      []byte // nil après la fermeture
	fermeFait  bool
	effaceFait bool
}

type fichier struct {
	contenu []byte
	mime    string
	etag    string
}

var mimes = map[string]string{
	".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
	".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
	".png": "image/png", ".webp": "image/webp", ".mp4": "video/mp4", ".svg": "image/svg+xml",
}

// Nouveau charge les pages et les fichiers statiques en mémoire, remplace les valeurs de configuration
// (R5), et prépare la clé des empreintes d'IP. Il échoue si une valeur reste ou si le contenu est invalide.
func Nouveau(cfg *contenu.Config, q *contenu.Questionnaire, contenuJSON []byte, web fs.FS, base *stockage.Base, log *slog.Logger, horloge func() time.Time) (*Serveur, error) {
	lim, err := NouveauLimiteur(horloge)
	if err != nil {
		return nil, err
	}
	s := &Serveur{Cfg: cfg, Q: q, Base: base, Log: log, Horloge: horloge, Lim: lim,
		val: &reponse.Validateur{Q: q}, pages: map[string][]byte{}, statiques: map[string]*fichier{}}
	s.cache = &stats.Cache{Source: s.sourceAgregats, Horloge: horloge, TTL: time.Minute}

	for chemin, nom := range map[string]string{"/": "index.html", "/donnees": "donnees.html"} {
		brut, err := fs.ReadFile(web, nom)
		if err != nil {
			return nil, err
		}
		rempli, err := contenu.Remplacer(string(brut), cfg.Valeurs())
		if err != nil {
			return nil, fmt.Errorf("%s : %w", nom, err)
		}
		s.pages[chemin] = []byte(rempli)
	}
	err = fs.WalkDir(web, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || p == "index.html" || p == "donnees.html" || strings.HasSuffix(p, ".test.mjs") {
			return err
		}
		mime, ok := mimes[strings.ToLower(path.Ext(p))]
		if !ok {
			return fmt.Errorf("web/%s : type MIME non déclaré", p)
		}
		brut, err := fs.ReadFile(web, p)
		if err != nil {
			return err
		}
		s.statiques["/static/"+p] = nouveauFichier(brut, mime)
		return nil
	})
	if err != nil {
		return nil, err
	}
	s.statiques["/static/questionnaire.json"] = nouveauFichier(contenuJSON, mimes[".json"])

	// La clé n'est créée qu'avant la fermeture : détruite, elle ne revient jamais.
	if horloge().Before(cfg.Fermeture) {
		if s.cleIP, err = stockage.ChargerCleIP(cfg.Donnees, true); err != nil {
			return nil, err
		}
	}
	return s, nil
}

func nouveauFichier(b []byte, mime string) *fichier {
	h := sha256.Sum256(b)
	return &fichier{contenu: b, mime: mime, etag: `"` + hex.EncodeToString(h[:8]) + `"`}
}

// Ouvert dit si le questionnaire accepte des réponses : comparé à UX_FERMETURE à chaque requête.
func (s *Serveur) Ouvert() bool { return s.Horloge().Before(s.Cfg.Fermeture) }

func (s *Serveur) routes(w http.ResponseWriter, r *http.Request) {
	p := r.URL.Path
	switch {
	case p == "/healthz":
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		fmt.Fprint(w, "ok")
	case p == "/" || p == "/donnees":
		if !lecture(w, r) {
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(s.pages[p]))
	case strings.HasPrefix(p, "/static/"):
		f, ok := s.statiques[p]
		if !ok {
			http.NotFound(w, r)
			return
		}
		if !lecture(w, r) {
			return
		}
		w.Header().Set("Content-Type", f.mime)
		w.Header().Set("ETag", f.etag)
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(f.contenu))
	case p == "/api/etat":
		if lecture(w, r) {
			s.etat(w, r)
		}
	case p == "/api/stats":
		if lecture(w, r) {
			s.stats(w, r)
		}
	case p == "/api/reponses":
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			ecrireJSON(w, http.StatusMethodNotAllowed, map[string]string{"erreur": "méthode non permise"})
			return
		}
		s.recevoir(w, r)
	default:
		http.NotFound(w, r)
	}
}

// lecture accepte GET et HEAD ; sinon elle répond 405.
func lecture(w http.ResponseWriter, r *http.Request) bool {
	if r.Method == http.MethodGet || r.Method == http.MethodHead {
		return true
	}
	w.Header().Set("Allow", "GET, HEAD")
	http.Error(w, "méthode non permise", http.StatusMethodNotAllowed)
	return false
}

func ecrireJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

// sourceAgregats lit l'instantané agregats.json s'il existe (après l'effacement), sinon calcule sur la base.
func (s *Serveur) sourceAgregats(ctx context.Context) (stats.Agregats, error) {
	brut, err := os.ReadFile(filepath.Join(s.Cfg.Donnees, stockage.FichierAgregats))
	if err == nil {
		var a stats.Agregats
		return a, json.Unmarshal(brut, &a)
	}
	if !errors.Is(err, os.ErrNotExist) {
		return stats.Agregats{}, err
	}
	lignes, err := s.Base.Reponses(ctx)
	if err != nil {
		return stats.Agregats{}, err
	}
	return stats.Calculer(s.Q, lignes), nil
}

// Instantane produit le contenu de agregats.json, identique à l'export agregats.
func (s *Serveur) Instantane(lignes []reponse.Ligne) ([]byte, error) {
	return exporter.AgregatsJSON(stats.Calculer(s.Q, lignes))
}

// Entretien est la tâche horaire : fermeture, puis effacement à la date prévue. Chaque passage est
// sans effet si c'est déjà fait ; une erreur (point de contrôle occupé) est reprise au passage suivant.
func (s *Serveur) Entretien(ctx context.Context) {
	now := s.Horloge()
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.fermeFait && !now.Before(s.Cfg.Fermeture) {
		if err := s.Base.Fermeture(ctx, s.Cfg.Fermeture, now); err != nil {
			s.Log.Error("fermeture incomplète, reprise au prochain passage", "erreur", err.Error())
			return
		}
		s.cleIP, s.fermeFait = nil, true
		s.Log.Info("fermeture faite")
	}
	if !s.effaceFait && !now.Before(s.Cfg.Effacement()) {
		if err := s.Base.Effacement(ctx, s.Cfg.Fermeture, now, s.Instantane); err != nil {
			s.Log.Error("effacement incomplet, reprise au prochain passage", "erreur", err.Error())
			return
		}
		s.cache.Invalider()
		s.effaceFait = true
		s.Log.Info("effacement terminé")
	}
}

// Boucle lance Entretien au démarrage puis toutes les heures, jusqu'à l'annulation du contexte.
func (s *Serveur) Boucle(ctx context.Context) {
	s.Entretien(ctx)
	t := time.NewTicker(time.Hour)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			s.Entretien(ctx)
		}
	}
}
