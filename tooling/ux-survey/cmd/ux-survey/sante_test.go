package main

import (
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// adresseDe renvoie l'adresse hôte:port d'un serveur de test.
func adresseDe(t *testing.T, s *httptest.Server) string {
	t.Helper()
	return strings.TrimPrefix(s.URL, "http://")
}

func TestSanteRepondOK(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/healthz" {
			t.Errorf("chemin %q, attendu /healthz", r.URL.Path)
		}
		_, _ = w.Write([]byte("ok"))
	}))
	defer s.Close()
	t.Setenv("UX_ADRESSE", adresseDe(t, s))
	if err := lancer("sante", nil); err != nil {
		t.Fatalf("service sain, erreur %v", err)
	}
}

func TestSanteAdresseJokerVisee127(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	defer s.Close()
	_, port, _ := net.SplitHostPort(adresseDe(t, s))
	t.Setenv("UX_ADRESSE", "0.0.0.0:"+port) // l'adresse d'écoute du conteneur
	if err := lancer("sante", nil); err != nil {
		t.Fatalf("0.0.0.0 doit viser la boucle locale : %v", err)
	}
}

func TestSanteEchecSiStatutOuServiceAbsent(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(500) }))
	t.Setenv("UX_ADRESSE", adresseDe(t, s))
	if err := lancer("sante", nil); err == nil {
		t.Error("un statut 500 doit échouer")
	}
	s.Close()
	if err := lancer("sante", nil); err == nil {
		t.Error("un service arrêté doit échouer")
	}
}

func TestSanteNeToucheNiBaseNiConfig(t *testing.T) {
	// Sans variables obligatoires ni dossier de données : la sonde ne doit lire que UX_ADRESSE.
	s := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	defer s.Close()
	for _, v := range []string{"UX_ORIGINE", "UX_PROXY_DE_CONFIANCE", "UX_FERMETURE", "UX_MENTION_MAJ"} {
		t.Setenv(v, "")
	}
	t.Setenv("UX_DONNEES", "/n-existe-pas/donnees")
	t.Setenv("UX_ADRESSE", adresseDe(t, s))
	if err := lancer("sante", nil); err != nil {
		t.Fatal(err)
	}
}
