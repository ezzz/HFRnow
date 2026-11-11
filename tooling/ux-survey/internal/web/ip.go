package web

import (
	"net/http"
	"net/netip"
	"strings"
)

// IPClient renvoie l'adresse du client (§6). Si la connexion vient du proxy de confiance, c'est la
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
				return a.Unmap().String()
			}
		}
	}
	return ip.String()
}

func (s *Serveur) deConfiance(ip netip.Addr) bool {
	for _, p := range s.Cfg.Proxy {
		if p.Contains(ip) {
			return true
		}
	}
	return false
}
