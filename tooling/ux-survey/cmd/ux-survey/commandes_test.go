package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stockage"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/testutil"
)

// preparer fixe l'environnement des commandes dans un dossier temporaire et renvoie ce dossier.
func preparer(t *testing.T, fermeture time.Time) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "donnees")
	t.Setenv("UX_DONNEES", dir)
	t.Setenv("UX_ORIGINE", "http://127.0.0.1:8080")
	t.Setenv("UX_PROXY_DE_CONFIANCE", "aucun")
	t.Setenv("UX_FERMETURE", fermeture.Format(time.RFC3339))
	t.Setenv("UX_MENTION_MAJ", "2026-11-09")
	t.Setenv("UX_ADRESSE", "127.0.0.1:0")
	return dir
}

// remplir écrit des réponses : la première avec le pseudo « Alice », la seconde limitée (R13).
func remplir(t *testing.T, dir string, fermeture time.Time, n int) (ids []string) {
	t.Helper()
	b, err := stockage.Ouvrir(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer b.Fermer()
	cle, err := stockage.ChargerCleIP(dir, true)
	if err != nil {
		t.Fatal(err)
	}
	q := testutil.Questionnaire(t)
	for i := 1; i <= n; i++ {
		norm, err := (&reponse.Validateur{Q: q}).Valider(testutil.Envoi(t, q, testutil.Jeton(i), map[string]any{"P1": "iphone", "G1": "texte" + string(rune('A'+i))}))
		if err != nil {
			t.Fatal(err)
		}
		if i == 1 {
			norm.Pseudo = "Alice"
		}
		id, err := b.Ecrire(context.Background(), stockage.Envoi{
			Normalisee: *norm, Version: q.Version, Jeton: testutil.Jeton(i),
			EmpreinteIP: stockage.EmpreinteIP(cle, "203.0.113."+string(rune('0'+i))), MaxParIP: 3,
			RecueLe: "2026-11-20", Fermeture: stockage.JourFermeture(fermeture),
		})
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, id)
	}
	return ids
}

func TestExportAnalyseNomMode0600ExclutLesLimitees(t *testing.T) {
	ferm := time.Now().Add(48 * time.Hour).Truncate(time.Second)
	dir := preparer(t, ferm)
	ids := remplir(t, dir, ferm, 2)
	if err := lancer("pseudo", []string{"--limiter", ids[1]}); err != nil {
		t.Fatal(err)
	}
	sortie := filepath.Join(t.TempDir(), "analyse")
	if err := lancer("export", []string{"--format", "analyse", "--sortie", sortie}); err != nil {
		t.Fatal(err)
	}
	date := time.Now().In(ferm.Location()).Format(time.DateOnly)
	for _, ext := range []string{"csv", "json"} {
		nom := sortie + "-" + date + "." + ext
		info, err := os.Stat(nom)
		if err != nil {
			t.Fatalf("fichier attendu %s : %v", nom, err)
		}
		if info.Mode().Perm() != 0o600 {
			t.Errorf("%s : mode %v, 0600 attendu", nom, info.Mode().Perm())
		}
		contenu, _ := os.ReadFile(nom)
		if !strings.Contains(string(contenu), ids[0]) || strings.Contains(string(contenu), ids[1]) {
			t.Errorf("%s : la réponse normale y est, la limitée n'y est pas", nom)
		}
		if strings.Contains(string(contenu), "Alice") {
			t.Errorf("%s : aucun pseudo dans l'export d'analyse", nom)
		}
	}
	// un export existant n'est jamais écrasé
	if err := lancer("export", []string{"--format", "analyse", "--sortie", sortie}); err == nil {
		t.Error("le second export du jour doit refuser d'écraser le premier")
	}
	// lever la limite remet la réponse dans les exports
	if err := lancer("pseudo", []string{"--lever-limite", ids[1]}); err != nil {
		t.Fatal(err)
	}
	autre := filepath.Join(t.TempDir(), "analyse")
	if err := lancer("export", []string{"--format", "analyse", "--sortie", autre}); err != nil {
		t.Fatal(err)
	}
	c, _ := os.ReadFile(autre + "-" + date + ".csv")
	if !strings.Contains(string(c), ids[1]) {
		t.Error("après --lever-limite, la réponse revient dans l'export")
	}
}

func TestFermerEtEffacerRefusesAvantLaDate(t *testing.T) {
	ferm := time.Now().Add(48 * time.Hour).Truncate(time.Second)
	dir := preparer(t, ferm)
	remplir(t, dir, ferm, 1)
	for _, c := range []string{"fermer", "effacer"} {
		if err := lancer(c, nil); err == nil {
			t.Errorf("%s doit être refusé avant UX_FERMETURE", c)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "cle-ip")); err != nil {
		t.Error("cle-ip n'est pas supprimée par une commande refusée")
	}
}

func TestEffacementIdempotentEtAgregatsApres(t *testing.T) {
	ferm := time.Now().AddDate(0, 0, -90).Truncate(time.Second) // fermeture + 2 mois est passée
	dir := preparer(t, ferm)
	remplir(t, dir, ferm, 6)
	if err := lancer("fermer", nil); err != nil {
		t.Fatal(err)
	}
	if err := lancer("effacer", nil); err != nil {
		t.Fatal(err)
	}
	snap := filepath.Join(dir, "agregats.json")
	avant, err := os.ReadFile(snap)
	if err != nil {
		t.Fatalf("agregats.json attendu après l'effacement : %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "cle-ip")); !os.IsNotExist(err) {
		t.Error("cle-ip doit être supprimée")
	}
	// idempotent : un second effacement réussit et ne réécrit jamais l'instantané
	if err := lancer("effacer", nil); err != nil {
		t.Errorf("second effacement : %v", err)
	}
	apres, _ := os.ReadFile(snap)
	if string(avant) != string(apres) {
		t.Error("l'instantané ne doit jamais être réécrit")
	}
	// l'export d'ensemble relit l'instantané, la base ne contient plus de réponses
	sortie := filepath.Join(t.TempDir(), "agregats")
	if err := lancer("export", []string{"--format", "agregats", "--sortie", sortie}); err != nil {
		t.Fatal(err)
	}
	date := time.Now().In(ferm.Location()).Format(time.DateOnly)
	j, err := os.ReadFile(sortie + "-" + date + ".json")
	if err != nil || len(j) == 0 {
		t.Fatalf("export agregats après effacement : %v", err)
	}
	if err := lancer("export", []string{"--format", "analyse", "--sortie", filepath.Join(t.TempDir(), "a")}); err != nil {
		t.Fatal(err)
	}
}

// R5 : toute commande refuse une UX_FERMETURE repoussée après la première réponse.
func TestFermetureRepousseeRefuseeParToutesLesCommandes(t *testing.T) {
	ferm := time.Now().Add(48 * time.Hour).Truncate(time.Second)
	dir := preparer(t, ferm)
	remplir(t, dir, ferm, 1)
	t.Setenv("UX_FERMETURE", ferm.Add(72*time.Hour).Format(time.RFC3339))
	commandes := map[string][]string{
		"export":      {"--format", "pseudos", "--sortie", filepath.Join(t.TempDir(), "p")},
		"sauvegarder": {filepath.Join(t.TempDir(), "copie.db")},
		"fermer":      nil,
		"effacer":     nil,
		"pseudo":      {"--chercher", "Alice"},
	}
	for c, args := range commandes {
		err := lancer(c, args)
		if err == nil || !strings.Contains(err.Error(), "repoussée") {
			t.Errorf("%s : refus attendu pour une date repoussée, obtenu %v", c, err)
		}
	}
	// une date plus proche est acceptée
	t.Setenv("UX_FERMETURE", ferm.Add(-24*time.Hour).Format(time.RFC3339))
	if err := lancer("pseudo", []string{"--chercher", "Alice"}); err != nil {
		t.Errorf("date avancée : %v", err)
	}
}

func TestSauvegarderEtSansEcraser(t *testing.T) {
	ferm := time.Now().Add(48 * time.Hour).Truncate(time.Second)
	dir := preparer(t, ferm)
	remplir(t, dir, ferm, 1)
	copie := filepath.Join(t.TempDir(), "copie.db")
	if err := lancer("sauvegarder", []string{copie}); err != nil {
		t.Fatal(err)
	}
	if info, err := os.Stat(copie); err != nil || info.Mode().Perm() != 0o600 {
		t.Errorf("copie en 0600 : %v %v", info, err)
	}
	if err := lancer("sauvegarder", []string{copie}); err == nil {
		t.Error("une sauvegarde existante n'est pas écrasée")
	}
	if err := lancer("inconnue", nil); err == nil {
		t.Error("commande inconnue refusée")
	}
}
