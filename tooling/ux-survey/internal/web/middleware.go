package web

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"log/slog"
	"math"
	"net/http"
	"strconv"
	"strings"
)

const csp = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; connect-src 'self'; " +
	"form-action 'self'; base-uri 'none'; frame-ancestors 'none'"

type cleRaison struct{}

// enregistreur relève le statut, la taille et la raison d'un refus pour le journal.
type enregistreur struct {
	http.ResponseWriter
	statut int
	taille int
	raison string
}

func (e *enregistreur) WriteHeader(code int) {
	if e.statut == 0 {
		e.statut = code
	}
	e.ResponseWriter.WriteHeader(code)
}

func (e *enregistreur) Write(b []byte) (int, error) {
	if e.statut == 0 {
		e.statut = http.StatusOK
	}
	n, err := e.ResponseWriter.Write(b)
	e.taille += n
	return n, err
}

// Unwrap laisse http.ResponseController atteindre le vrai écrivain.
func (e *enregistreur) Unwrap() http.ResponseWriter { return e.ResponseWriter }

// refuser note la raison d'un refus dans le journal (honeypot, doublon-jeton, limite-ip, debit, origine).
func refuser(r *http.Request, raison string) {
	if p, ok := r.Context().Value(cleRaison{}).(*string); ok {
		*p = raison
	}
}

// Handler assemble les routes et les intergiciels : en-têtes, récupération, journal, limitation, accès restreint.
func (s *Serveur) Handler() http.Handler {
	return s.entetes(s.recuperer(s.journal(s.limiter(s.acces(http.HandlerFunc(s.routes))))))
}

// entetes pose les en-têtes du §9 sur toutes les réponses, erreurs comprises.
func (s *Serveur) entetes(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Security-Policy", csp)
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		h.Set("Cross-Origin-Opener-Policy", "same-origin")
		h.Set("Cross-Origin-Resource-Policy", "same-origin")
		if r.URL.Path == "/donnees" || strings.HasPrefix(r.URL.Path, "/api/") {
			h.Set("Cache-Control", "no-store")
		}
		if s.Cfg.HTTPS() {
			h.Set("Strict-Transport-Security", "max-age=31536000")
		}
		next.ServeHTTP(w, r)
	})
}

// recuperer transforme une panique en 500 sans détail.
func (s *Serveur) recuperer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recover() != nil {
				s.Log.Error("panique")
				http.Error(w, "erreur interne", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// journal écrit une ligne JSON par requête : méthode, chemin sans paramètres, statut, durée, taille et
// raison d'un refus. Jamais d'IP, d'empreinte, de jeton, d'agent utilisateur, de référent, de corps ni de texte.
func (s *Serveur) journal(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" {
			next.ServeHTTP(w, r)
			return
		}
		debut := s.Horloge()
		raison := ""
		e := &enregistreur{ResponseWriter: w}
		next.ServeHTTP(e, r.WithContext(context.WithValue(r.Context(), cleRaison{}, &raison)))
		attrs := []any{
			slog.String("methode", r.Method), slog.String("chemin", r.URL.Path), slog.Int("statut", e.statut),
			slog.Int64("duree_ms", s.Horloge().Sub(debut).Milliseconds()), slog.Int("taille", e.taille),
		}
		if raison != "" {
			attrs = append(attrs, slog.String("refus", raison))
		}
		s.Log.Info("requete", attrs...)
	})
}

// limiter applique la limitation de débit (§6) ; /static/ et /healthz ne sont pas limités.
func (s *Serveur) limiter(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if p == "/healthz" || strings.HasPrefix(p, "/static/") {
			next.ServeHTTP(w, r)
			return
		}
		cat, reg := "autres", regleAutres
		switch {
		case p == "/api/reponses" && r.Method == http.MethodPost:
			cat, reg = "post", reglePost
		case p == "/api/stats":
			cat, reg = "stats", regleStats
		}
		if ok, attente := s.Lim.Autoriser(cat, s.IPClient(r), reg); !ok {
			refuser(r, "debit")
			w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(attente.Seconds()))))
			ecrireJSON(w, http.StatusTooManyRequests, map[string]string{"erreur": "trop de requêtes, réessayez plus tard"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

// acces exige l'authentification HTTP Basic (utilisateur « test ») quand UX_CODE_ACCES est défini, sauf /healthz.
func (s *Serveur) acces(next http.Handler) http.Handler {
	if s.Cfg.CodeAcces == "" {
		return next
	}
	attendu := sha256.Sum256([]byte(s.Cfg.CodeAcces))
	utilisateur := sha256.Sum256([]byte("test"))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" {
			next.ServeHTTP(w, r)
			return
		}
		u, mdp, ok := r.BasicAuth()
		hu, hm := sha256.Sum256([]byte(u)), sha256.Sum256([]byte(mdp))
		bon := subtle.ConstantTimeCompare(hu[:], utilisateur[:]) & subtle.ConstantTimeCompare(hm[:], attendu[:])
		if !ok || bon != 1 {
			w.Header().Set("WWW-Authenticate", `Basic realm="Questionnaire", charset="UTF-8"`)
			http.Error(w, "authentification requise", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}
