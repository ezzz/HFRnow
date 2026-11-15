package web

import (
	"net/http"
	"net/netip"
	"strings"
)

// IPClient renvoie l'adresse du client (§6), ramenée à son groupe (voir groupe). Si la connexion vient du proxy de confiance, c'est la
// dernière adresse de X-Forwarded-For, celle que le proxy a ajoutée ; sinon, ou si la valeur « aucun »
// est configurée, c'est l'adresse de la connexion et l'en-tête est ignoré.
func (s *Serveur) IPClient(r *http.Request) string {
	conn, err := netip.ParseAddrPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	ip := conn.Addr().Unmap()
	if s.deConfiance(ip) {
		if valeurs := r.Header.Values("X-Forwarded-For"); len(valeurs) > 0 {
			dernier := valeurs[len(valeurs)-1]
			if i := strings.LastIndexByte(dernier, ','); i >= 0 {
				dernier = dernier[i+1:]
			}
			if a, err := netip.ParseAddr(strings.TrimSpace(dernier)); err == nil {
				return groupe(a.Unmap())
			}
		}
	}
	return groupe(ip)
}

func (s *Serveur) deConfiance(ip netip.Addr) bool {
	for _, p := range s.Cfg.Proxy {
		if p.Contains(ip) {
			return true
		}
	}
	return false
}

// groupe ramène une adresse IPv6 à son préfixe /64 (celui d'une ligne ou d'un foyer, dans lequel un téléphone
// change d'adresse à volonté) ; une adresse IPv4 reste telle quelle. Le compteur d'envois et le limiteur de débit
// comptent par groupe.
func groupe(a netip.Addr) string {
	if a.Is6() {
		return netip.PrefixFrom(a, 64).Masked().Addr().String()
	}
	return a.String()
}
