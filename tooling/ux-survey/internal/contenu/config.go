package contenu

import (
	"fmt"
	"net/netip"
	"strconv"
	"strings"
	"time"
)

// SeuilMinimal est le plus petit UX_SEUIL_STATS accepté (décision D3).
const SeuilMinimal = 10

// Config est la configuration lue dans l'environnement (§10). Aucun secret n'est dans le dépôt.
type Config struct {
	Adresse    string
	Donnees    string
	Origine    string
	Proxy      []netip.Prefix // vide si UX_PROXY_DE_CONFIANCE vaut « aucun »
	Fermeture  time.Time
	MentionMaj time.Time // date seule, à minuit UTC
	SeuilStats int
	MaxParIP   int
	CodeAcces  string
}

// ChargerConfig lit la configuration ; get renvoie la valeur d'une variable (os.Getenv en production).
// Elle échoue si une variable obligatoire manque ou est invalide.
func ChargerConfig(get func(string) string) (*Config, error) {
	c := &Config{
		Adresse:    defaut(get("UX_ADRESSE"), "127.0.0.1:8080"),
		Donnees:    defaut(get("UX_DONNEES"), "./donnees"),
		Origine:    strings.TrimRight(get("UX_ORIGINE"), "/"),
		SeuilStats: SeuilMinimal,
		MaxParIP:   3,
		CodeAcces:  get("UX_CODE_ACCES"),
	}
	if c.Origine == "" {
		return nil, fmt.Errorf("UX_ORIGINE est obligatoire (par exemple https://sondage.exemple.fr)")
	}
	if !strings.HasPrefix(c.Origine, "https://") && !strings.HasPrefix(c.Origine, "http://") {
		return nil, fmt.Errorf("UX_ORIGINE doit commencer par https:// ou http://")
	}
	proxy := strings.TrimSpace(get("UX_PROXY_DE_CONFIANCE"))
	if proxy == "" {
		return nil, fmt.Errorf("UX_PROXY_DE_CONFIANCE est obligatoire (IP ou CIDR du proxy, ou « aucun »)")
	}
	if proxy != "aucun" {
		for _, p := range strings.Split(proxy, ",") {
			p = strings.TrimSpace(p)
			if pf, err := netip.ParsePrefix(p); err == nil {
				c.Proxy = append(c.Proxy, pf)
			} else if ip, err := netip.ParseAddr(p); err == nil {
				c.Proxy = append(c.Proxy, netip.PrefixFrom(ip.Unmap(), ip.Unmap().BitLen()))
			} else {
				return nil, fmt.Errorf("UX_PROXY_DE_CONFIANCE : %q n'est ni une IP ni un CIDR", p)
			}
		}
	}
	f, err := time.Parse(time.RFC3339, get("UX_FERMETURE"))
	if err != nil {
		return nil, fmt.Errorf("UX_FERMETURE est obligatoire, en RFC 3339 avec décalage horaire : %w", err)
	}
	c.Fermeture = f
	m, err := time.Parse(time.DateOnly, get("UX_MENTION_MAJ"))
	if err != nil {
		return nil, fmt.Errorf("UX_MENTION_MAJ est obligatoire, au format AAAA-MM-JJ : %w", err)
	}
	c.MentionMaj = m
	if v := get("UX_SEUIL_STATS"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < SeuilMinimal {
			return nil, fmt.Errorf("UX_SEUIL_STATS doit être un entier d'au moins %d", SeuilMinimal)
		}
		c.SeuilStats = n
	}
	if v := get("UX_MAX_PAR_IP"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 {
			return nil, fmt.Errorf("UX_MAX_PAR_IP doit être un entier positif")
		}
		c.MaxParIP = n
	}
	return c, nil
}

func defaut(v, d string) string {
	if v == "" {
		return d
	}
	return v
}

// Effacement renvoie la date d'effacement : fermeture + 2 mois, au même jour du mois ou au dernier jour
// du mois s'il n'existe pas (31 décembre donne le 28 ou 29 février).
func (c *Config) Effacement() time.Time {
	return PlusDeuxMois(c.Fermeture)
}

// PlusDeuxMois ajoute deux mois civils sans déborder sur le mois suivant.
func PlusDeuxMois(t time.Time) time.Time {
	y, m, d := t.Date()
	premier := time.Date(y, m+2, 1, t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), t.Location())
	dernier := time.Date(premier.Year(), premier.Month()+1, 0, 0, 0, 0, 0, t.Location()).Day()
	return time.Date(premier.Year(), premier.Month(), min(d, dernier), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), t.Location())
}

// HTTPS dit si l'origine publique est en https (HSTS).
func (c *Config) HTTPS() bool { return strings.HasPrefix(c.Origine, "https://") }
