package web

import (
	"net/http"
	"net/netip"
	"strings"
)

// adresse renvoie l'adresse du client (§6). Si la connexion vient du proxy de confiance, c'est la
// dernière adresse de X-Forwarded-For, celle que le proxy a ajoutée ; sinon, ou si la valeur « aucun »
// est configurée, c'est l'adresse de la connexion et l'en-tête est ignoré.
func (s *Serveur) adresse(r *http.Request) (netip.Addr, bool) {
	conn, err := netip.ParseAddrPort(r.RemoteAddr)
	if err != nil {
		return netip.Addr{}, false
	}
	ip := conn.Addr().Unmap()
	if s.deConfiance(ip) {
		if valeurs := r.Header.Values("X-Forwarded-For"); len(valeurs) > 0 {
			dernier := valeurs[len(valeurs)-1]
			if i := strings.LastIndexByte(dernier, ','); i >= 0 {
				dernier = dernier[i+1:]
			}
			if a, err := netip.ParseAddr(strings.TrimSpace(dernier)); err == nil {
				return a.Unmap(), true
			}
		}
	}
	return ip, true
}

// IPClient renvoie l'adresse du client ramenée à son /64 en IPv6 : clé du limiteur de débit.
func (s *Serveur) IPClient(r *http.Request) string {
	a, ok := s.adresse(r)
	if !ok {
		return r.RemoteAddr
	}
	return groupe(a, 64)
}

// IPCompteur renvoie l'adresse du client ramenée à son /56 en IPv6 : clé de l'empreinte qui compte les envois
// acceptés en base (M1). Une box française reçoit un /56 : compter par /64 y donnerait 256 compteurs.
func (s *Serveur) IPCompteur(r *http.Request) string {
	a, ok := s.adresse(r)
	if !ok {
		return r.RemoteAddr
	}
	return groupe(a, 56)
}

func (s *Serveur) deConfiance(ip netip.Addr) bool {
	for _, p := range s.Cfg.Proxy {
		if p.Contains(ip) {
			return true
		}
	}
	return false
}

// groupe ramène une adresse IPv6 à son préfixe de bits bits (64 pour le débit, celui d'une ligne dans lequel un
// téléphone change d'adresse à volonté ; 56 pour le compteur d'envois, celui d'un foyer) ; une adresse IPv4
// reste telle quelle.
func groupe(a netip.Addr, bits int) string {
	if a.Is6() {
		return netip.PrefixFrom(a, bits).Masked().Addr().String()
	}
	return a.String()
}
