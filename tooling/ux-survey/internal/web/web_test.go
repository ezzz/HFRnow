package web_test

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	uxsurvey "github.com/ezzz/hfrnow/tooling/ux-survey"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/contenu"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/stockage"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/testutil"
	"github.com/ezzz/hfrnow/tooling/ux-survey/internal/web"
)

type horloge struct {
	mu sync.Mutex
	t  time.Time
}

func (h *horloge) Now() time.Time  { h.mu.Lock(); defer h.mu.Unlock(); return h.t }
func (h *horloge) Set(t time.Time) { h.mu.Lock(); h.t = t; h.mu.Unlock() }

type banc struct {
	s    *web.Serveur
	h    http.Handler
	cfg  *contenu.Config
	hor  *horloge
	logs *bytes.Buffer
	dir  string
}

const origine = "https://sondage.exemple.fr"

func nouveau(t *testing.T, env map[string]string) *banc {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "donnees")
	e := map[string]string{
		"UX_ORIGINE": origine, "UX_PROXY_DE_CONFIANCE": "172.31.250.1", "UX_DONNEES": dir,
		"UX_FERMETURE": "2026-12-15T23:00:00+01:00", "UX_MENTION_MAJ": "2026-11-09",
	}
	for k, v := range env {
		e[k] = v
	}
	cfg, err := contenu.ChargerConfig(func(k string) string { return e[k] })
	if err != nil {
		t.Fatal(err)
	}
	base, err := stockage.Ouvrir(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { base.Fermer() })
	hor := &horloge{t: time.Date(2026, 12, 1, 10, 0, 0, 0, time.FixedZone("", 3600))}
	logs := &bytes.Buffer{}
	s, err := web.Nouveau(cfg, testutil.Questionnaire(t), uxsurvey.ContenuJSON(), uxsurvey.Web(), base, slog.New(slog.NewJSONHandler(logs, nil)), hor.Now)
	if err != nil {
		t.Fatal(err)
	}
	return &banc{s: s, h: s.Handler(), cfg: cfg, hor: hor, logs: logs, dir: dir}
}

func (b *banc) requete(t *testing.T, methode, chemin string, corps any, mod ...func(*http.Request)) *httptest.ResponseRecorder {
	t.Helper()
	var r io.Reader
	if corps != nil {
		if s, ok := corps.(string); ok {
			r = strings.NewReader(s)
		} else {
			j, _ := json.Marshal(corps)
			r = bytes.NewReader(j)
		}
	}
	req := httptest.NewRequest(methode, chemin, r)
	req.RemoteAddr = "192.0.2.1:4000"
	if methode == http.MethodPost {
		req.Header.Set("Origin", origine)
		req.Header.Set("Content-Type", "application/json")
	}
	for _, m := range mod {
		m(req)
	}
	rec := httptest.NewRecorder()
	b.h.ServeHTTP(rec, req)
	return rec
}

func (b *banc) envoi(t *testing.T, n int, m map[string]any, mod ...func(*http.Request)) *httptest.ResponseRecorder {
	t.Helper()
	q := testutil.Questionnaire(t)
	rep := map[string]any{}
	for k, v := range m {
		rep[k] = v
	}
	return b.requete(t, http.MethodPost, "/api/reponses", map[string]any{"version": q.Version, "jeton": testutil.Jeton(n), "site_web": "", "duree_s": 120, "reponses": rep}, mod...)
}

func depuis(ip string) func(*http.Request) {
	return func(r *http.Request) { r.RemoteAddr = ip + ":4000" }
}

func derriere(client string) func(*http.Request) {
	return func(r *http.Request) {
		r.RemoteAddr = "172.31.250.1:5000"
		r.Header.Set("X-Forwarded-For", "10.9.9.9, "+client)
	}
}

func compte(t *testing.T, b *banc, table string) int {
	t.Helper()
	n, err := b.s.Base.Compte(t.Context(), table)
	if err != nil {
		t.Fatal(err)
	}
	return n
}

func TestEnvoiNominal(t *testing.T) {
	b := nouveau(t, nil)
	rec := b.envoi(t, 1, map[string]any{"P1": "iphone", "G1": "texte"})
	if rec.Code != 201 || !strings.Contains(rec.Body.String(), `"stats"`) {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	// Test 8 par HTTP : même jeton -> 409 deja_recu, une seule ligne
	rec = b.envoi(t, 1, map[string]any{"P1": "ipad"})
	if rec.Code != 409 || !strings.Contains(rec.Body.String(), `"deja_recu":true`) || compte(t, b, "reponses") != 1 {
		t.Errorf("doublon : %d %s", rec.Code, rec.Body)
	}
	// version différente : 409 « rechargez »
	rec = b.requete(t, "POST", "/api/reponses", map[string]any{"version": "autre", "jeton": testutil.Jeton(2), "reponses": map[string]any{}})
	if rec.Code != 409 || !strings.Contains(rec.Body.String(), "rechargez") {
		t.Errorf("version : %d %s", rec.Code, rec.Body)
	}
}

func TestValidationHTTP(t *testing.T) {
	b := nouveau(t, nil)
	if rec := b.envoi(t, 1, map[string]any{"Z9": "x"}); rec.Code != 400 {
		t.Errorf("clé inconnue : %d", rec.Code)
	}
	gros := `{"version":"x","jeton":"y","reponses":{"G1":"` + strings.Repeat("a", 17000) + `"}}`
	if rec := b.requete(t, "POST", "/api/reponses", gros); rec.Code != 413 {
		t.Errorf("trop gros : %d", rec.Code)
	}
	if rec := b.requete(t, "POST", "/api/reponses", "{}", func(r *http.Request) { r.Header.Set("Content-Type", "text/plain") }); rec.Code != 400 {
		t.Errorf("content-type : %d", rec.Code)
	}
	if rec := b.requete(t, "POST", "/api/reponses", "pas du json"); rec.Code != 400 {
		t.Errorf("json invalide : %d", rec.Code)
	}
	if compte(t, b, "reponses") != 0 {
		t.Error("aucune ligne pour un refus")
	}
}

// Test 9 : quatrième envoi d'une même IP.
func TestLimiteParAdresse(t *testing.T) {
	b := nouveau(t, nil)
	for i := 1; i <= 3; i++ {
		if rec := b.envoi(t, i, nil, depuis("198.51.100.5")); rec.Code != 201 {
			t.Fatalf("envoi %d : %d", i, rec.Code)
		}
	}
	if rec := b.envoi(t, 4, nil, depuis("198.51.100.5")); rec.Code != 429 {
		t.Errorf("quatrième : %d", rec.Code)
	}
	if rec := b.envoi(t, 5, nil, depuis("198.51.100.6")); rec.Code != 201 {
		t.Errorf("autre adresse : %d", rec.Code)
	}
}

// Test 10 : proxy.
func TestProxy(t *testing.T) {
	cfgSans := map[string]string{"UX_PROXY_DE_CONFIANCE": ""}
	if _, err := contenu.ChargerConfig(func(k string) string {
		return map[string]string{"UX_ORIGINE": origine, "UX_FERMETURE": "2026-12-15T23:00:00+01:00", "UX_MENTION_MAJ": "2026-11-09"}[k]
	}); err == nil {
		t.Error("démarrage refusé sans UX_PROXY_DE_CONFIANCE")
	}
	_ = cfgSans
	// derrière le proxy : deux clients, deux compteurs
	b := nouveau(t, nil)
	for i := 1; i <= 3; i++ {
		if rec := b.envoi(t, i, nil, derriere("203.0.113.1")); rec.Code != 201 {
			t.Fatalf("%d", rec.Code)
		}
	}
	if rec := b.envoi(t, 4, nil, derriere("203.0.113.2")); rec.Code != 201 {
		t.Errorf("deux clients aux IP différentes ont deux compteurs : %d", rec.Code)
	}
	if rec := b.envoi(t, 5, nil, derriere("203.0.113.1")); rec.Code != 429 {
		t.Errorf("même client : %d", rec.Code)
	}
	// X-Forwarded-For ignoré d'une connexion hors du proxy
	b = nouveau(t, nil)
	hors := func(r *http.Request) { r.Header.Set("X-Forwarded-For", "203.0.113.77") }
	for i := 1; i <= 3; i++ {
		b.envoi(t, i, nil, hors, depuis("192.0.2.9"))
	}
	if rec := b.envoi(t, 4, nil, func(r *http.Request) { r.Header.Set("X-Forwarded-For", "203.0.113.88"); r.RemoteAddr = "192.0.2.9:1" }); rec.Code != 429 {
		t.Errorf("en-tête ignoré hors du proxy : %d", rec.Code)
	}
	// valeur aucun : ignoré même depuis l'adresse du proxy
	b = nouveau(t, map[string]string{"UX_PROXY_DE_CONFIANCE": "aucun"})
	for i := 1; i <= 3; i++ {
		b.envoi(t, i, nil, derriere("203.0.113."+string(rune('0'+i))))
	}
	if rec := b.envoi(t, 4, nil, derriere("203.0.113.9")); rec.Code != 429 {
		t.Errorf("aucun : en-tête ignoré : %d", rec.Code)
	}
}

// Test 11 : champ piège.
func TestChampPiege(t *testing.T) {
	b := nouveau(t, nil)
	q := testutil.Questionnaire(t)
	rec := b.requete(t, "POST", "/api/reponses", map[string]any{"version": q.Version, "jeton": testutil.Jeton(1), "site_web": "http://spam", "reponses": map[string]any{"P1": "iphone"}})
	if rec.Code != 201 || compte(t, b, "reponses") != 0 || compte(t, b, "jetons") != 0 {
		t.Errorf("piège : %d, %d lignes", rec.Code, compte(t, b, "reponses"))
	}
	if !strings.Contains(b.logs.String(), `"refus":"honeypot"`) {
		t.Error("raison honeypot au journal")
	}
}

// Test 12 : débit, et limiteur actif après la fermeture.
func TestDebit(t *testing.T) {
	b := nouveau(t, nil)
	var rec *httptest.ResponseRecorder
	for i := 0; i < 11; i++ {
		rec = b.envoi(t, 100+i, nil, depuis("198.51.100."+string(rune('1'+i%9))+"0"))
	}
	// 10 par heure et par client : tout depuis le même
	b = nouveau(t, nil)
	codes := []int{}
	for i := 0; i < 11; i++ {
		codes = append(codes, b.requete(t, "POST", "/api/reponses", "{}").Code)
	}
	if codes[9] == 429 || codes[10] != 429 {
		t.Errorf("11e envoi : %v", codes)
	}
	rec = b.requete(t, "POST", "/api/reponses", "{}")
	if rec.Header().Get("Retry-After") == "" {
		t.Error("Retry-After attendu")
	}
	// stats : 60 par minute
	b = nouveau(t, nil)
	var dernier *httptest.ResponseRecorder
	for i := 0; i < 61; i++ {
		dernier = b.requete(t, "GET", "/api/stats", nil)
	}
	if dernier.Code != 429 {
		t.Errorf("61e lecture de stats : %d", dernier.Code)
	}
	// la fenêtre passe
	b.hor.Set(b.hor.Now().Add(2 * time.Minute))
	if b.requete(t, "GET", "/api/stats", nil).Code != 200 {
		t.Error("après la fenêtre")
	}
	// après la fermeture et la tâche : cle-ip détruite, le limiteur marche encore
	b.hor.Set(time.Date(2026, 12, 16, 0, 0, 0, 0, time.UTC))
	b.s.Entretien(t.Context())
	var c int
	for i := 0; i < 130; i++ {
		c = b.requete(t, "GET", "/api/etat", nil).Code
	}
	if c != 429 {
		t.Errorf("limiteur après la fermeture : %d", c)
	}
	_ = rec
}

// Test 13 : origine.
func TestOrigine(t *testing.T) {
	b := nouveau(t, nil)
	for _, o := range []string{"https://autre.exemple.fr", "", origine + ".evil.com"} {
		rec := b.envoi(t, 1, nil, func(r *http.Request) {
			if o == "" {
				r.Header.Del("Origin")
			} else {
				r.Header.Set("Origin", o)
			}
		})
		if rec.Code != 403 {
			t.Errorf("origine %q : %d", o, rec.Code)
		}
	}
	if compte(t, b, "reponses") != 0 {
		t.Error("rien stocké")
	}
}

// Test 15 : fermeture.
func TestFermeture(t *testing.T) {
	b := nouveau(t, nil)
	b.envoi(t, 1, nil)
	ferm := b.cfg.Fermeture
	b.hor.Set(ferm.Add(-time.Second))
	if rec := b.envoi(t, 2, nil); rec.Code != 201 {
		t.Fatalf("une seconde avant : %d", rec.Code)
	}
	b.hor.Set(ferm.Add(time.Second))
	if rec := b.envoi(t, 3, nil); rec.Code != 410 {
		t.Errorf("après la fermeture : %d", rec.Code)
	}
	var etat map[string]any
	_ = json.Unmarshal(b.requete(t, "GET", "/api/etat", nil).Body.Bytes(), &etat)
	if etat["ouvert"] != false {
		t.Errorf("ouvert : %v", etat["ouvert"])
	}
	b.s.Entretien(t.Context())
	if _, err := os.Stat(filepath.Join(b.dir, stockage.FichierCleIP)); !os.IsNotExist(err) {
		t.Error("cle-ip doit être absente")
	}
	if compte(t, b, "jetons") != 0 || compte(t, b, "empreintes_ip") != 0 {
		t.Error("jetons et empreintes vidés")
	}
	if compte(t, b, "reponses") != 2 {
		t.Error("les réponses restent jusqu'à la date d'effacement")
	}
	// l'effacement vient avec la tâche, à fermeture + 2 mois ; les stats viennent alors de agregats.json
	b.hor.Set(b.cfg.Effacement().Add(time.Second))
	b.s.Entretien(t.Context())
	if compte(t, b, "reponses") != 0 {
		t.Error("réponses effacées à la date prévue")
	}
	if _, err := os.Stat(filepath.Join(b.dir, stockage.FichierAgregats)); err != nil {
		t.Error("agregats.json écrit")
	}
	// Test 17 : /api/stats sert l'instantané avec les mêmes seuils (2 réponses : sous le seuil)
	b.hor.Set(b.hor.Now().Add(time.Hour))
	if got := strings.TrimSpace(b.requete(t, "GET", "/api/stats", nil).Body.String()); got != `{"disponible":false,"seuil":10}` {
		t.Errorf("stats après effacement : %s", got)
	}
}

func TestStatsApresEffacementSeuil(t *testing.T) {
	b := nouveau(t, nil)
	for i := 1; i <= 12; i++ {
		b.envoi(t, i, map[string]any{"P1": "iphone"}, depuis("198.51.100."+string(rune('0'+i%10))+string(rune('0'+i/10))))
	}
	b.hor.Set(b.cfg.Effacement().Add(time.Second))
	b.s.Entretien(t.Context())
	b.hor.Set(b.hor.Now().Add(time.Hour))
	body := b.requete(t, "GET", "/api/stats", nil).Body.String()
	if !strings.Contains(body, `"total":12`) || !strings.Contains(body, `"iphone":100`) {
		t.Errorf("stats servies par l'instantané : %s", body)
	}
	if compte(t, b, "reponses") != 0 {
		t.Error("effacé")
	}
}

var entetesAttendus = map[string]string{
	"Content-Security-Policy":      "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
	"X-Content-Type-Options":       "nosniff",
	"Referrer-Policy":              "no-referrer",
	"Permissions-Policy":           "camera=(), microphone=(), geolocation=()",
	"Cross-Origin-Opener-Policy":   "same-origin",
	"Cross-Origin-Resource-Policy": "same-origin",
}

// Test 20 : en-têtes.
func TestEntetes(t *testing.T) {
	b := nouveau(t, nil)
	verifier := func(nom string, rec *httptest.ResponseRecorder, noStore bool) {
		for k, v := range entetesAttendus {
			if rec.Header().Get(k) != v {
				t.Errorf("%s : %s = %q", nom, k, rec.Header().Get(k))
			}
		}
		if (rec.Header().Get("Cache-Control") == "no-store") != noStore {
			t.Errorf("%s : Cache-Control %q", nom, rec.Header().Get("Cache-Control"))
		}
		if rec.Header().Get("Strict-Transport-Security") != "max-age=31536000" {
			t.Errorf("%s : HSTS attendu avec une origine https", nom)
		}
	}
	verifier("page", b.requete(t, "GET", "/", nil), false)
	verifier("données", b.requete(t, "GET", "/donnees", nil), true)
	verifier("api", b.requete(t, "GET", "/api/etat", nil), true)
	rec := b.requete(t, "GET", "/nimporte", nil)
	if rec.Code != 404 {
		t.Errorf("404 : %d", rec.Code)
	}
	verifier("404", rec, false)
	b2 := nouveau(t, nil)
	for i := 0; i < 11; i++ {
		rec = b2.requete(t, "POST", "/api/reponses", "{}")
	}
	if rec.Code != 429 {
		t.Fatalf("429 attendu : %d", rec.Code)
	}
	verifier("429", rec, true)
	// HSTS absent sans https
	h := nouveau(t, map[string]string{"UX_ORIGINE": "http://127.0.0.1:8080"})
	if h.requete(t, "GET", "/", nil).Header().Get("Strict-Transport-Security") != "" {
		t.Error("pas de HSTS en http")
	}
}

// Test 19 : pages sans valeur restante.
func TestPagesEtValeurs(t *testing.T) {
	b := nouveau(t, nil)
	re := regexp.MustCompile(`\{[a-z_]+\}`)
	for _, p := range []string{"/", "/donnees"} {
		rec := b.requete(t, "GET", p, nil)
		if rec.Code != 200 || re.MatchString(rec.Body.String()) {
			t.Errorf("%s : %d, motif restant %q", p, rec.Code, re.FindString(rec.Body.String()))
		}
	}
	d := b.requete(t, "GET", "/donnees", nil).Body.String()
	for _, attendu := range []string{"15 décembre 2026", "15 février 2027", "9 novembre 2026"} {
		if !strings.Contains(d, attendu) {
			t.Errorf("/donnees : %q absent", attendu)
		}
	}
	if !strings.Contains(b.requete(t, "GET", "/", nil).Body.String(), "15 février 2027") {
		t.Error("/ : date d'effacement absente du paragraphe du pseudo")
	}
	for _, f := range []string{"/static/app.js", "/static/style.css", "/static/questionnaire.json", "/static/visuels/L1-pages-ameliorees-iphone.png", "/static/logique.js"} {
		if rec := b.requete(t, "GET", f, nil); rec.Code != 200 || rec.Header().Get("Content-Type") == "" {
			t.Errorf("%s : %d", f, rec.Code)
		}
	}
	if b.requete(t, "GET", "/static/logique.test.mjs", nil).Code != 404 {
		t.Error("les tests ne sont pas servis")
	}
	if rec := b.requete(t, "GET", "/healthz", nil); rec.Code != 200 || rec.Body.String() != "ok" {
		t.Errorf("healthz : %d", rec.Code)
	}
}

// Test 21 : journaux.
func TestJournaux(t *testing.T) {
	b := nouveau(t, nil)
	rec := b.envoi(t, 1, map[string]any{"G1": "SecretG1 irritant", "L2": "SecretL2", "C11": "SecretC11", "F1": "SecretF1", "I1": "PseudoSecret"},
		depuis("203.0.113.7"), func(r *http.Request) {
			r.Header.Set("User-Agent", "AgentSecret/1.0")
			r.Header.Set("Referer", "https://referent.exemple/secret")
		})
	if rec.Code != 201 {
		t.Fatal(rec.Code)
	}
	b.envoi(t, 1, nil, depuis("203.0.113.7")) // doublon : raison au journal
	l := b.logs.String()
	for _, interdit := range []string{"203.0.113.7", "PseudoSecret", "SecretG1", "SecretL2", "SecretC11", "SecretF1", "AgentSecret", "referent.exemple", testutil.Jeton(1)} {
		if strings.Contains(l, interdit) {
			t.Errorf("le journal contient %q", interdit)
		}
	}
	if !strings.Contains(l, `"refus":"doublon-jeton"`) || !strings.Contains(l, `"chemin":"/api/reponses"`) || !strings.Contains(l, `"statut":201`) {
		t.Errorf("journal incomplet : %s", l)
	}
	b.requete(t, "GET", "/healthz", nil)
	if strings.Contains(b.logs.String(), "healthz") {
		t.Error("healthz ne journalise pas")
	}
}

// Test 23 : accès restreint.
func TestAccesRestreint(t *testing.T) {
	b := nouveau(t, map[string]string{"UX_CODE_ACCES": "motdepasse-de-test"})
	if b.requete(t, "GET", "/", nil).Code != 401 || b.requete(t, "GET", "/api/etat", nil).Code != 401 {
		t.Error("401 sans authentification")
	}
	auth := func(u, p string) func(*http.Request) { return func(r *http.Request) { r.SetBasicAuth(u, p) } }
	if b.requete(t, "GET", "/", nil, auth("test", "motdepasse-de-test")).Code != 200 {
		t.Error("200 avec authentification")
	}
	if b.requete(t, "GET", "/", nil, auth("test", "faux")).Code != 401 || b.requete(t, "GET", "/", nil, auth("autre", "motdepasse-de-test")).Code != 401 {
		t.Error("mauvais identifiants")
	}
	if b.requete(t, "GET", "/healthz", nil).Code != 200 {
		t.Error("/healthz toujours ouvert")
	}
	if rec := b.envoi(t, 1, nil); rec.Code != 401 {
		t.Errorf("POST sans authentification : %d", rec.Code)
	}
}

// Test 14 (HTTP) : 9 réponses -> indisponible, 10 -> publiées, aucune clé de texte.
func TestStatsHTTP(t *testing.T) {
	b := nouveau(t, nil)
	for i := 1; i <= 9; i++ {
		b.envoi(t, i, map[string]any{"P1": "iphone", "G1": "texte"}, depuis("198.51.100."+string(rune('0'+i))))
	}
	rec := b.envoi(t, 10, map[string]any{"P1": "iphone", "G1": "texte"}, depuis("198.51.100.20"))
	if rec.Code != 201 || !strings.Contains(rec.Body.String(), `"disponible":true`) {
		t.Errorf("la 10e réponse voit les résultats : %s", rec.Body)
	}
	if strings.Contains(rec.Body.String(), "G1") || strings.Contains(rec.Body.String(), "texte") {
		t.Error("texte libre dans les stats")
	}
}
