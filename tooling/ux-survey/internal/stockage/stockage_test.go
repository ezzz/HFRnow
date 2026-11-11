package stockage

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/reponse"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/testutil"
)

var ctx = context.Background()

func ouvrir(t *testing.T) *Base {
	t.Helper()
	b, err := Ouvrir(filepath.Join(t.TempDir(), "donnees"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { b.Fermer() })
	return b
}

func ecrire(t *testing.T, b *Base, n int, ip, pseudo string, m map[string]any) (string, error) {
	t.Helper()
	q := testutil.Questionnaire(t)
	norm, err := (&reponse.Validateur{Q: q}).Valider(testutil.Envoi(t, q, testutil.Jeton(n), m))
	if err != nil {
		t.Fatal(err)
	}
	norm.Pseudo = pseudo
	return b.Ecrire(ctx, Envoi{Normalisee: *norm, Version: q.Version, Jeton: testutil.Jeton(n),
		EmpreinteIP: EmpreinteIP([]byte("cle-de-test-0123456789abcdef0123"), ip), MaxParIP: 3, RecueLe: "2026-11-20"})
}

func contenuFichiers(t *testing.T, b *Base) []byte {
	t.Helper()
	var tout []byte
	for _, s := range []string{"", "-wal", "-shm"} {
		if c, err := os.ReadFile(filepath.Join(b.Dossier(), FichierBase+s)); err == nil {
			tout = append(tout, c...)
		}
	}
	return tout
}

// Test 7 : enregistrement.
func TestEnregistrement(t *testing.T) {
	b := ouvrir(t)
	id, err := ecrire(t, b, 1, "203.0.113.7", "Pseudo-Test", map[string]any{"P1": "iphone", "G1": "texte libre"})
	if err != nil {
		t.Fatal(err)
	}
	if !regexp.MustCompile(`^[0-9a-f]{16}$`).MatchString(id) {
		t.Errorf("identifiant %q", id)
	}
	var recue, donnees string
	if err := b.DB().QueryRow(`SELECT recue_le, donnees FROM reponses WHERE identifiant = ?`, id).Scan(&recue, &donnees); err != nil {
		t.Fatal(err)
	}
	if !regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`).MatchString(recue) {
		t.Errorf("recue_le doit être une date sans heure : %q", recue)
	}
	if strings.Contains(donnees, "Pseudo-Test") {
		t.Error("le pseudo ne doit pas être dans les réponses")
	}
	var p string
	if err := b.DB().QueryRow(`SELECT pseudo FROM pseudos WHERE identifiant = ?`, id).Scan(&p); err != nil || p != "Pseudo-Test" {
		t.Errorf("pseudo dans pseudos : %q %v", p, err)
	}
	if bytes.Contains(contenuFichiers(t, b), []byte(testutil.Jeton(1))) {
		t.Error("le jeton en clair ne doit pas être dans la base")
	}
	// sans pseudo : aucune ligne dans pseudos
	if _, err := ecrire(t, b, 2, "203.0.113.8", "", map[string]any{"P1": "ipad"}); err != nil {
		t.Fatal(err)
	}
	if n, _ := b.Compte(ctx, "pseudos"); n != 1 {
		t.Errorf("pseudos : %d", n)
	}
}

// Test 8 : doublon par jeton.
func TestDoublonJeton(t *testing.T) {
	b := ouvrir(t)
	if _, err := ecrire(t, b, 1, "203.0.113.7", "", nil); err != nil {
		t.Fatal(err)
	}
	if _, err := ecrire(t, b, 1, "203.0.113.9", "", nil); !errors.Is(err, ErrDoublonJeton) {
		t.Errorf("deuxième envoi du même jeton : %v", err)
	}
	if n, _ := b.Compte(ctx, "reponses"); n != 1 {
		t.Errorf("%d lignes, une attendue", n)
	}
}

// Test 9 : doublon par adresse, IP jamais en clair, clé hors du fichier SQLite.
func TestLimiteIP(t *testing.T) {
	b := ouvrir(t)
	for i := 1; i <= 3; i++ {
		if _, err := ecrire(t, b, i, "203.0.113.7", "", nil); err != nil {
			t.Fatalf("envoi %d : %v", i, err)
		}
	}
	if _, err := ecrire(t, b, 4, "203.0.113.7", "", nil); !errors.Is(err, ErrLimiteIP) {
		t.Errorf("quatrième envoi : %v", err)
	}
	if _, err := ecrire(t, b, 5, "198.51.100.1", "", nil); err != nil {
		t.Errorf("autre adresse : %v", err)
	}
	if n, _ := b.Compte(ctx, "reponses"); n != 4 {
		t.Errorf("%d réponses, 4 attendues (le quatrième envoi du même IP n'écrit rien)", n)
	}
	if n, _ := b.Compte(ctx, "jetons"); n != 4 {
		t.Errorf("un refus ne doit pas laisser son jeton : %d", n)
	}
	if bytes.Contains(contenuFichiers(t, b), []byte("203.0.113.7")) {
		t.Error("l'IP en clair est dans la base")
	}
}

func TestEmpreintesEtCle(t *testing.T) {
	a, c := []byte(strings.Repeat("a", 32)), []byte(strings.Repeat("b", 32))
	if EmpreinteIP(a, "203.0.113.7") == EmpreinteIP(c, "203.0.113.7") {
		t.Error("deux clés doivent donner deux empreintes")
	}
	if EmpreinteIP(a, "203.0.113.7") == EmpreinteIP(a, "203.0.113.8") {
		t.Error("deux adresses, deux empreintes")
	}
	dossier := t.TempDir()
	cle, err := ChargerCleIP(dossier, true)
	if err != nil || len(cle) != 32 {
		t.Fatal(err)
	}
	if st, _ := os.Stat(filepath.Join(dossier, FichierCleIP)); st.Mode().Perm() != 0o600 {
		t.Errorf("cle-ip en %v", st.Mode().Perm())
	}
	b, _ := Ouvrir(filepath.Join(dossier, "d"))
	defer b.Fermer()
	if _, err := b.Ecrire(ctx, Envoi{Normalisee: reponse.Normalisee{Donnees: map[string]json.RawMessage{}}, Version: "v", Jeton: testutil.Jeton(1), EmpreinteIP: EmpreinteIP(cle, "203.0.113.7"), MaxParIP: 3, RecueLe: "2026-11-20"}); err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(contenuFichiers(t, b), cle) {
		t.Error("la clé des empreintes est dans le fichier SQLite")
	}
	// après la fermeture la clé ne doit pas revenir
	if err := os.Remove(filepath.Join(dossier, FichierCleIP)); err != nil {
		t.Fatal(err)
	}
	if _, err := ChargerCleIP(dossier, false); err == nil {
		t.Error("sans création, une clé absente reste absente")
	}
}

func remplir(t *testing.T, b *Base, n int) {
	t.Helper()
	for i := 1; i <= n; i++ {
		if _, err := ecrire(t, b, i, "203.0.113."+string(rune('0'+i%10))+string(rune('0'+i/10)), "", map[string]any{"P1": "iphone", "O1": "oser"}); err != nil {
			t.Fatal(err)
		}
	}
}

func instantane(l []reponse.Ligne) ([]byte, error) {
	return json.Marshal(map[string]int{"total": len(l)})
}

// Test 15 (stockage) : la fermeture supprime cle-ip et vide les tables d'anti-abus, mais pas les réponses.
func TestFermeture(t *testing.T) {
	b := ouvrir(t)
	if _, err := ChargerCleIP(b.Dossier(), true); err != nil {
		t.Fatal(err)
	}
	remplir(t, b, 3)
	fermeture := time.Date(2026, 12, 15, 22, 0, 0, 0, time.UTC)
	if err := b.Fermeture(ctx, fermeture, fermeture.Add(-time.Second)); !errors.Is(err, ErrAvantFermeture) {
		t.Errorf("fermeture avant l'heure : %v", err)
	}
	if err := b.Fermeture(ctx, fermeture, fermeture.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(b.Dossier(), FichierCleIP)); !errors.Is(err, os.ErrNotExist) {
		t.Error("cle-ip doit être supprimée")
	}
	for table, attendu := range map[string]int{"jetons": 0, "empreintes_ip": 0, "reponses": 3} {
		if n, _ := b.Compte(ctx, table); n != attendu {
			t.Errorf("%s : %d, attendu %d", table, n, attendu)
		}
	}
	if err := b.Fermeture(ctx, fermeture, fermeture.Add(time.Hour)); err != nil {
		t.Errorf("idempotente : %v", err)
	}
}

// Test 17 : effacement.
func TestEffacement(t *testing.T) {
	b := ouvrir(t)
	remplir(t, b, 4)
	if _, err := ecrire(t, b, 50, "198.51.100.50", "Pseudo", nil); err != nil {
		t.Fatal(err)
	}
	fermeture := time.Date(2026, 12, 15, 22, 0, 0, 0, time.UTC)
	if err := b.Effacement(ctx, fermeture, fermeture.Add(-time.Second), instantane); !errors.Is(err, ErrAvantFermeture) {
		t.Fatalf("effacement avant fermeture : %v", err)
	}
	if _, err := os.Stat(filepath.Join(b.Dossier(), FichierAgregats)); err == nil {
		t.Fatal("refusé avant la fermeture : aucun instantané")
	}
	if n, _ := b.Compte(ctx, "reponses"); n != 5 {
		t.Fatalf("rien ne doit être effacé avant la fermeture : %d", n)
	}
	if err := b.Effacement(ctx, fermeture, fermeture.Add(time.Second), instantane); err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"reponses", "pseudos", "jetons", "empreintes_ip"} {
		if n, _ := b.Compte(ctx, table); n != 0 {
			t.Errorf("%s : %d lignes après l'effacement", table, n)
		}
	}
	if st, err := os.Stat(filepath.Join(b.Dossier(), FichierBase+"-wal")); err == nil && st.Size() != 0 {
		t.Errorf("-wal non vide : %d octets", st.Size())
	}
	if bytes.Contains(contenuFichiers(t, b), []byte("Pseudo")) {
		t.Error("le pseudo reste dans les fichiers après VACUUM")
	}
	agr, _ := os.ReadFile(filepath.Join(b.Dossier(), FichierAgregats))
	if string(agr) != `{"total":5}` {
		t.Errorf("agregats.json : %s", agr)
	}
	// relancé : les totaux d'avant l'effacement restent
	if err := b.Effacement(ctx, fermeture, fermeture.Add(2*time.Second), instantane); err != nil {
		t.Fatal(err)
	}
	if agr, _ = os.ReadFile(filepath.Join(b.Dossier(), FichierAgregats)); string(agr) != `{"total":5}` {
		t.Errorf("après une seconde exécution : %s", agr)
	}
}

func TestEffacementReprise(t *testing.T) {
	b := ouvrir(t)
	remplir(t, b, 3)
	fermeture := time.Date(2026, 12, 15, 22, 0, 0, 0, time.UTC)
	b.pointDeControle = func(context.Context) error { return ErrPointOccupe }
	if err := b.Effacement(ctx, fermeture, fermeture.Add(time.Second), instantane); !errors.Is(err, ErrPointOccupe) {
		t.Fatalf("point de contrôle occupé : %v", err)
	}
	// l'instantané est acquis, les lignes sont déjà vidées : la reprise ne doit pas le remplacer par des zéros
	if n, _ := b.Compte(ctx, "reponses"); n != 0 {
		t.Fatalf("étape 2 déjà faite : %d", n)
	}
	b.pointDeControle = b.checkpointTronque
	if err := b.Effacement(ctx, fermeture, fermeture.Add(time.Hour), instantane); err != nil {
		t.Fatal(err)
	}
	if agr, _ := os.ReadFile(filepath.Join(b.Dossier(), FichierAgregats)); string(agr) != `{"total":3}` {
		t.Errorf("la reprise a remplacé l'instantané : %s", agr)
	}
}

// Test 18 : droits des répondants.
func TestDroits(t *testing.T) {
	b := ouvrir(t)
	q := testutil.Questionnaire(t)
	v := &reponse.Validateur{Q: q}
	a, _ := ecrire(t, b, 1, "203.0.113.1", "  Jean-Pierre ", map[string]any{"P1": "ipad", "L2": "ancien", "O1": "oser", "D1": testutil.D1(false, testutil.Sec("favoris", "garder", 1))})
	a2, _ := ecrire(t, b, 2, "203.0.113.2", "JEAN-PIERRE", map[string]any{"P1": "iphone"})
	autre, _ := ecrire(t, b, 3, "203.0.113.3", "Autre", map[string]any{"P1": "iphone", "L2": "intact"})

	l, err := b.Chercher(ctx, "jean-pierre ")
	if err != nil || len(l) != 2 {
		t.Fatalf("recherche sans casse ni espaces : %d %v", len(l), err)
	}
	// corriger valide la valeur, objet D1 compris
	if err := b.Corriger(ctx, v, a, "O1", `"nimporte"`); err == nil {
		t.Error("une valeur invalide doit être refusée")
	}
	if err := b.Corriger(ctx, v, a, "D1", `{"comme_aujourdhui":false,"sections":[{"code":"mp","etat":"garder","rang":2}]}`); err == nil {
		t.Error("un objet D1 invalide doit être refusé")
	}
	if err := b.Corriger(ctx, v, a, "D1", `{"comme_aujourdhui":true}`); err != nil {
		t.Fatal(err)
	}
	if err := b.Corriger(ctx, v, a, "L2", `"nouveau texte"`); err != nil {
		t.Fatal(err)
	}
	ligne, _ := b.Reponse(ctx, a)
	if string(ligne.Donnees["D1"]) != `{"comme_aujourdhui":true}` || string(ligne.Donnees["L2"]) != `"nouveau texte"` || string(ligne.Donnees["O1"]) != `"oser"` {
		t.Errorf("corrections : %v", ligne.Donnees)
	}
	// P1 qui devient iphone : D1 retiré par la condition
	if err := b.Corriger(ctx, v, a, "P1", `"iphone"`); err != nil {
		t.Fatal(err)
	}
	if ligne, _ = b.Reponse(ctx, a); ligne.Donnees["D1"] != nil {
		t.Error("D1 doit disparaître quand P1 devient iphone")
	}
	// effacer-question : une seule réponse
	if err := b.EffacerQuestion(ctx, v, a, "L2"); err != nil {
		t.Fatal(err)
	}
	if ligne, _ = b.Reponse(ctx, a); ligne.Donnees["L2"] != nil || ligne.Donnees["O1"] == nil {
		t.Errorf("effacer-question : %v", ligne.Donnees)
	}
	// effacer-pseudo : seule la ligne de pseudos
	if err := b.SupprimerPseudo(ctx, a); err != nil {
		t.Fatal(err)
	}
	if n, _ := b.Compte(ctx, "pseudos"); n != 2 {
		t.Errorf("pseudos : %d", n)
	}
	if _, err := b.Reponse(ctx, a); err != nil {
		t.Error("la réponse doit rester")
	}
	// effacer : réponse et pseudo de la seule réponse visée
	if err := b.SupprimerReponse(ctx, a2); err != nil {
		t.Fatal(err)
	}
	if _, err := b.Reponse(ctx, a2); !errors.Is(err, ErrIntrouvable) {
		t.Error("réponse supprimée")
	}
	if n, _ := b.Compte(ctx, "pseudos"); n != 1 {
		t.Errorf("pseudos après effacement : %d", n)
	}
	if ligne, err = b.Reponse(ctx, autre); err != nil || string(ligne.Donnees["L2"]) != `"intact"` {
		t.Errorf("les autres réponses restent intactes : %v %v", ligne.Donnees, err)
	}
	if n, _ := b.Compte(ctx, "reponses"); n != 2 {
		t.Errorf("reponses : %d", n)
	}
}

func TestSauvegarde(t *testing.T) {
	b := ouvrir(t)
	remplir(t, b, 2)
	if _, err := ChargerCleIP(b.Dossier(), true); err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(t.TempDir(), "copie.db")
	if err := b.Sauvegarder(ctx, dest); err != nil {
		t.Fatal(err)
	}
	if st, _ := os.Stat(dest); st.Mode().Perm() != 0o600 {
		t.Errorf("sauvegarde en %v", st.Mode().Perm())
	}
	c, _ := os.ReadFile(dest)
	cle, _ := os.ReadFile(filepath.Join(b.Dossier(), FichierCleIP))
	if bytes.Contains(c, cle) {
		t.Error("cle-ip dans la sauvegarde")
	}
	if err := b.Sauvegarder(ctx, dest); err == nil {
		t.Error("une sauvegarde existante ne doit pas être écrasée")
	}
}

// R13 : une réponse limitée reste stockée mais sort des lectures d'analyse, de statistiques et d'instantané.
func TestReponseLimitee(t *testing.T) {
	b := ouvrir(t)
	a, _ := ecrire(t, b, 1, "203.0.113.1", "Pseudo", map[string]any{"P1": "iphone"})
	if _, err := ecrire(t, b, 2, "203.0.113.2", "", map[string]any{"P1": "iphone"}); err != nil {
		t.Fatal(err)
	}
	if err := b.Limiter(ctx, a, true); err != nil {
		t.Fatal(err)
	}
	if l, _ := b.Reponses(ctx); len(l) != 1 || l[0].Identifiant == a {
		t.Errorf("la réponse limitée est exclue : %v", l)
	}
	if l, _ := b.ToutesLesReponses(ctx); len(l) != 2 {
		t.Errorf("elle reste stockée : %d", len(l))
	}
	if l, _ := b.Chercher(ctx, "pseudo"); len(l) != 1 || !l[0].Limitee {
		t.Errorf("la recherche par pseudo la retrouve, marquée limitée : %v", l)
	}
	if err := b.Limiter(ctx, "inconnu", true); !errors.Is(err, ErrIntrouvable) {
		t.Errorf("identifiant inconnu : %v", err)
	}
	fermeture := time.Date(2026, 12, 15, 22, 0, 0, 0, time.UTC)
	if err := b.Effacement(ctx, fermeture, fermeture.Add(time.Second), instantane); err != nil {
		t.Fatal(err)
	}
	if agr, _ := os.ReadFile(filepath.Join(b.Dossier(), FichierAgregats)); string(agr) != `{"total":1}` {
		t.Errorf("l'instantané n'inclut pas la réponse limitée : %s", agr)
	}
	// levée de la limitation
	c, _ := ecrire(t, b, 3, "203.0.113.3", "", nil)
	_ = b.Limiter(ctx, c, true)
	_ = b.Limiter(ctx, c, false)
	if l, _ := b.Reponses(ctx); len(l) != 1 || l[0].Identifiant != c {
		t.Errorf("limitation levée : %v", l)
	}
}

// R5 : après la première réponse, la fermeture peut être avancée, jamais repoussée.
func TestFermeturePasRepoussee(t *testing.T) {
	b := ouvrir(t)
	f := time.Date(2026, 12, 15, 22, 0, 0, 0, time.UTC)
	if err := b.VerifierFermeture(ctx, f.Add(48*time.Hour)); err != nil {
		t.Errorf("avant toute réponse, toute date est acceptée : %v", err)
	}
	q := testutil.Questionnaire(t)
	norm, _ := (&reponse.Validateur{Q: q}).Valider(testutil.Envoi(t, q, testutil.Jeton(1), nil))
	if _, err := b.Ecrire(ctx, Envoi{Normalisee: *norm, Version: q.Version, Jeton: testutil.Jeton(1), EmpreinteIP: "x", MaxParIP: 3, RecueLe: "2026-11-20", Fermeture: f.Format(time.RFC3339)}); err != nil {
		t.Fatal(err)
	}
	if err := b.VerifierFermeture(ctx, f.Add(time.Second)); !errors.Is(err, ErrFermetureRepoussee) {
		t.Errorf("une date plus tardive est refusée : %v", err)
	}
	if err := b.VerifierFermeture(ctx, f); err != nil {
		t.Errorf("la même date : %v", err)
	}
	if err := b.VerifierFermeture(ctx, f.Add(-24*time.Hour)); err != nil {
		t.Errorf("avancer : %v", err)
	}
	if err := b.VerifierFermeture(ctx, f); !errors.Is(err, ErrFermetureRepoussee) {
		t.Errorf("après avoir avancé, revenir à l'ancienne date est repousser : %v", err)
	}
}
