package web

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"sync"
	"time"
)

// maxEntrees est le nombre de clients suivis en mémoire ; les plus anciens sont oubliés d'abord.
const maxEntrees = 1000

// Catégories de limitation et leurs plafonds (§6).
type regle struct {
	max     int
	fenetre time.Duration
}

var (
	reglePost   = regle{10, time.Hour}
	regleStats  = regle{60, time.Minute}
	regleAutres = regle{120, time.Minute}
)

type entree struct {
	debut time.Time
	n     int
}

// Limiteur limite le débit par client, en mémoire. Il est indexé par un HMAC de l'IP sous une clé propre au
// processus, tirée au démarrage et jamais écrite : il marche donc encore après la destruction de cle-ip,
// et aucune adresse en clair n'y figure.
type Limiteur struct {
	mu      sync.Mutex
	cle     []byte
	entrees map[string]*entree
	horloge func() time.Time
}

// NouveauLimiteur tire la clé du processus.
func NouveauLimiteur(horloge func() time.Time) (*Limiteur, error) {
	cle := make([]byte, 32)
	if _, err := rand.Read(cle); err != nil {
		return nil, err
	}
	return &Limiteur{cle: cle, entrees: map[string]*entree{}, horloge: horloge}, nil
}

func (l *Limiteur) cleClient(categorie, ip string) string {
	m := hmac.New(sha256.New, l.cle)
	m.Write([]byte(categorie + "|" + ip))
	return hex.EncodeToString(m.Sum(nil))
}

// Autoriser compte une requête ; il renvoie faux et le délai d'attente quand la limite est dépassée.
func (l *Limiteur) Autoriser(categorie, ip string, r regle) (bool, time.Duration) {
	cle := l.cleClient(categorie, ip)
	now := l.horloge()
	l.mu.Lock()
	defer l.mu.Unlock()
	e := l.entrees[cle]
	if e == nil || now.Sub(e.debut) >= r.fenetre {
		if e == nil && len(l.entrees) >= maxEntrees {
			l.oublierLaPlusAncienne()
		}
		e = &entree{debut: now}
		l.entrees[cle] = e
	}
	if e.n >= r.max {
		return false, e.debut.Add(r.fenetre).Sub(now)
	}
	e.n++
	return true, 0
}

func (l *Limiteur) oublierLaPlusAncienne() {
	var cle string
	var plus time.Time
	for k, e := range l.entrees {
		if cle == "" || e.debut.Before(plus) {
			cle, plus = k, e.debut
		}
	}
	delete(l.entrees, cle)
}
