package web

import (
	"sync"
	"time"
)

// plafondHoraire est le disjoncteur global (M1) : nombre d'envois acceptés par heure, tous clients confondus.
// Il borne ce qu'un attaquant à beaucoup d'adresses peut stocker, quels que soient les compteurs par adresse.
type plafondHoraire struct {
	max     int
	horloge func() time.Time

	mu    sync.Mutex
	debut time.Time
	n     int
	// signale est vrai une fois la ligne de journal écrite pour la fenêtre en cours.
	signale bool
}

// atteint dit si la fenêtre d'une heure en cours a déjà accepté max envois ; premiere est vrai la première fois
// (pour écrire une seule ligne de journal par fenêtre), attente donne le délai avant la prochaine fenêtre.
func (p *plafondHoraire) atteint() (atteint, premiere bool, attente time.Duration) {
	p.mu.Lock()
	defer p.mu.Unlock()
	now := p.horloge()
	if p.debut.IsZero() || now.Sub(p.debut) >= time.Hour {
		p.debut, p.n, p.signale = now, 0, false
	}
	if p.n < p.max {
		return false, false, 0
	}
	premiere = !p.signale
	p.signale = true
	return true, premiere, p.debut.Add(time.Hour).Sub(now)
}

// compter note un envoi accepté.
func (p *plafondHoraire) compter() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.n++
}
