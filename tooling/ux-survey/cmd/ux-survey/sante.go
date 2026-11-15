package main

import (
	"fmt"
	"net"
	"net/http"
	"os"
	"time"
)

// commandeSante est la sonde du conteneur (HEALTHCHECK) : l'image n'a ni shell ni curl, le binaire s'interroge lui-même.
// Elle ne lit que UX_ADRESSE : ni configuration complète, ni base (rien à ouvrir, rien à écrire).
func commandeSante() error {
	adresse := os.Getenv("UX_ADRESSE")
	if adresse == "" {
		adresse = "127.0.0.1:8080"
	}
	hote, port, err := net.SplitHostPort(adresse)
	if err != nil {
		return fmt.Errorf("UX_ADRESSE invalide : %w", err)
	}
	if ip := net.ParseIP(hote); hote == "" || (ip != nil && ip.IsUnspecified()) {
		hote = "127.0.0.1" // 0.0.0.0 ou :: écoutent partout ; la sonde passe par la boucle locale
	}
	c := http.Client{Timeout: 3 * time.Second}
	rep, err := c.Get("http://" + net.JoinHostPort(hote, port) + "/healthz")
	if err != nil {
		return err
	}
	defer rep.Body.Close()
	if rep.StatusCode != http.StatusOK {
		return fmt.Errorf("/healthz : statut %d", rep.StatusCode)
	}
	return nil
}
