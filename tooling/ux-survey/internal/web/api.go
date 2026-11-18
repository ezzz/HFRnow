package web

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"math"
	"mime"
	"net/http"
	"strconv"
	"time"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stockage"
)

// MaxCorps est la taille maximale du corps d'un envoi : 16 Ko.
const MaxCorps = 16 * 1024

func (s *Serveur) etat(w http.ResponseWriter, _ *http.Request) {
	ecrireJSON(w, http.StatusOK, map[string]any{
		"ouvert":      s.Ouvert(),
		"fermeture":   s.Cfg.Fermeture.Format(time.RFC3339),
		"effacement":  s.Cfg.Effacement().Format(time.RFC3339),
		"mention_maj": s.Cfg.MentionMaj.Format(time.DateOnly),
		"seuil":       s.Cfg.SeuilStats,
		"version":     s.Q.Version,
	})
}

func (s *Serveur) charge(r *http.Request) (any, error) {
	a, err := s.cache.Agregats(r.Context())
	if err != nil {
		return nil, err
	}
	return a.Publier(s.Cfg.SeuilStats), nil
}

func (s *Serveur) stats(w http.ResponseWriter, r *http.Request) {
	c, err := s.charge(r)
	if err != nil {
		s.erreurInterne(w, "stats", err)
		return
	}
	ecrireJSON(w, http.StatusOK, c)
}

func (s *Serveur) erreurInterne(w http.ResponseWriter, ou string, err error) {
	s.Log.Error("erreur interne", "ou", ou, "erreur", err.Error())
	ecrireJSON(w, http.StatusInternalServerError, map[string]string{"erreur": "erreur interne"})
}

// frais calcule les statistiques sur la base, sans passer par le cache : réservé à la réponse 201, qui ne
// montre que le résultat du répondant qui vient d'envoyer (F2). Le GET public reste servi par le cache d'une minute.
func (s *Serveur) frais(r *http.Request) (any, error) {
	a, err := s.sourceAgregats(r.Context())
	if err != nil {
		return nil, err
	}
	return a.Publier(s.Cfg.SeuilStats), nil
}

// recevoir traite POST /api/reponses : origine, fermeture, corps, champ piège, validation, doublons, écriture.
func (s *Serveur) recevoir(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Origin") != s.Cfg.Origine {
		refuser(r, "origine")
		ecrireJSON(w, http.StatusForbidden, map[string]string{"erreur": "origine refusée"})
		return
	}
	if !s.Ouvert() {
		ecrireJSON(w, http.StatusGone, map[string]string{"erreur": "Questionnaire fermé"})
		return
	}
	if t, _, err := mime.ParseMediaType(r.Header.Get("Content-Type")); err != nil || t != "application/json" {
		ecrireJSON(w, http.StatusBadRequest, map[string]string{"erreur": "Content-Type application/json attendu"})
		return
	}
	corps, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxCorps))
	if err != nil {
		var trop *http.MaxBytesError
		if errors.As(err, &trop) {
			ecrireJSON(w, http.StatusRequestEntityTooLarge, map[string]string{"erreur": "envoi trop gros"})
		} else {
			ecrireJSON(w, http.StatusBadRequest, map[string]string{"erreur": "corps illisible"})
		}
		return
	}
	var e reponse.Envoi
	if err := decoderStrict(corps, &e); err != nil {
		ecrireJSON(w, http.StatusBadRequest, map[string]string{"erreur": "JSON invalide"})
		return
	}
	if e.SiteWeb != "" { // champ piège : même réponse qu'un envoi accepté, rien n'est stocké
		refuser(r, "honeypot")
		c, err := s.charge(r)
		if err != nil {
			s.erreurInterne(w, "stats", err)
			return
		}
		ecrireJSON(w, http.StatusCreated, map[string]any{"stats": c})
		return
	}
	norm, err := s.val.Valider(&e)
	if err != nil {
		var inv *reponse.ErrInvalide
		switch {
		case errors.Is(err, reponse.ErrVersion):
			ecrireJSON(w, http.StatusConflict, map[string]string{"erreur": err.Error()})
		case errors.As(err, &inv):
			ecrireJSON(w, http.StatusBadRequest, map[string]string{"erreur": inv.Raison})
		default:
			s.erreurInterne(w, "validation", err)
		}
		return
	}
	// Un jeton déjà enregistré reçoit « déjà reçu » avant le plafond : un nouvel essai après coupure réseau ne doit
	// pas voir un 503 pour un envoi qui est déjà dans la base.
	if connu, err := s.Base.JetonConnu(r.Context(), e.Jeton); err != nil {
		s.erreurInterne(w, "jeton", err)
		return
	} else if connu {
		s.dejaRecu(w, r)
		return
	}
	if atteint, premiere, attente := s.plafond.atteint(); atteint {
		if premiere {
			s.Log.Warn("plafond horaire d'envois atteint", "plafond", s.Cfg.PlafondH)
		}
		refuser(r, "plafond-horaire")
		w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(attente.Seconds()))))
		ecrireJSON(w, http.StatusServiceUnavailable, map[string]string{"erreur": "service très sollicité, réessayez plus tard"})
		return
	}
	s.mu.RLock()
	cle := s.cleIP
	s.mu.RUnlock()
	if cle == nil {
		ecrireJSON(w, http.StatusGone, map[string]string{"erreur": "Questionnaire fermé"})
		return
	}
	_, err = s.Base.Ecrire(r.Context(), stockage.Envoi{
		Normalisee:  *norm,
		Version:     s.Q.Version,
		Jeton:       e.Jeton,
		EmpreinteIP: stockage.EmpreinteIP(cle, s.IPCompteur(r)),
		MaxParIP:    s.Cfg.MaxParIP,
		Fermeture:   stockage.JourFermeture(s.Cfg.Fermeture),
		RecueLe:     s.Horloge().In(s.Cfg.Fermeture.Location()).Format(time.DateOnly),
	})
	switch {
	case errors.Is(err, stockage.ErrDoublonJeton):
		s.dejaRecu(w, r)
	case errors.Is(err, stockage.ErrLimiteIP):
		refuser(r, "limite-ip")
		ecrireJSON(w, http.StatusTooManyRequests, map[string]string{"erreur": "trop d'envois depuis cette adresse"})
	case err != nil:
		s.erreurInterne(w, "ecriture", err)
	default:
		s.plafond.compter()
		c, cerr := s.frais(r)
		if cerr != nil {
			s.erreurInterne(w, "stats", cerr)
			return
		}
		ecrireJSON(w, http.StatusCreated, map[string]any{"stats": c})
	}
}

// dejaRecu répond 409 pour un jeton déjà enregistré, avec les statistiques du cache (jamais de chiffres frais).
func (s *Serveur) dejaRecu(w http.ResponseWriter, r *http.Request) {
	refuser(r, "doublon-jeton")
	c, err := s.charge(r)
	if err != nil {
		s.erreurInterne(w, "stats", err)
		return
	}
	ecrireJSON(w, http.StatusConflict, map[string]any{"deja_recu": true, "stats": c})
}

func decoderStrict(corps []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(corps))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return err
	}
	if dec.More() {
		return errors.New("données après le JSON")
	}
	return nil
}
