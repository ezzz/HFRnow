package stats

import (
	"context"
	"sync"
	"time"
)

// Cache garde les agrégats en mémoire : recalcul au plus une fois par minute, sauf après une réponse
// acceptée (Invalider), pour que le répondant qui atteint le seuil voie les résultats.
type Cache struct {
	Source  func(ctx context.Context) (Agregats, error)
	Horloge func() time.Time
	TTL     time.Duration

	mu     sync.Mutex
	valeur Agregats
	calcul time.Time
	sale   bool
}

// Agregats renvoie les agrégats, recalculés si le cache est vieux d'une minute ou invalidé.
func (c *Cache) Agregats(ctx context.Context) (Agregats, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	maintenant := c.Horloge()
	if c.calcul.IsZero() || c.sale || maintenant.Sub(c.calcul) >= c.TTL {
		a, err := c.Source(ctx)
		if err != nil {
			return Agregats{}, err
		}
		c.valeur, c.calcul, c.sale = a, maintenant, false
	}
	return c.valeur, nil
}

// Invalider force le prochain appel à recalculer.
func (c *Cache) Invalider() {
	c.mu.Lock()
	c.sale = true
	c.mu.Unlock()
}
