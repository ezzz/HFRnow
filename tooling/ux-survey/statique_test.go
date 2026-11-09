package uxsurvey

import (
	"io/fs"
	"regexp"
	"strings"
	"testing"
)

// Test 22 : poids, domaines, CSP. web/ hors visuels pèse 200 Ko au plus, aucune URL absolue vers un autre
// domaine, aucun innerHTML, insertAdjacentHTML, document.write, attribut style ni gestionnaire on…=.
func TestWebPoidsDomainesEtCSP(t *testing.T) {
	total := 0
	reURL := regexp.MustCompile(`https?://[^\s"'<>)]+`)
	reOn := regexp.MustCompile(`(?i)\son[a-z]+\s*=`)
	reStyle := regexp.MustCompile(`(?i)\sstyle\s*=`)
	err := fs.WalkDir(Web(), ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || strings.HasPrefix(p, "visuels/") {
			return err
		}
		b, err := fs.ReadFile(Web(), p)
		if err != nil {
			return err
		}
		total += len(b)
		if strings.HasSuffix(p, ".test.mjs") {
			return nil // les tests décrivent les motifs interdits
		}
		s := string(b)
		for _, interdit := range []string{"innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "setAttribute('style'", `setAttribute("style"`, "eval(", "new Function"} {
			if strings.Contains(s, interdit) {
				t.Errorf("%s contient %s", p, interdit)
			}
		}
		if strings.HasSuffix(p, ".html") {
			if reOn.MatchString(s) {
				t.Errorf("%s : gestionnaire d'événement en attribut", p)
			}
			if reStyle.MatchString(s) || strings.Contains(s, "<style") {
				t.Errorf("%s : style en ligne", p)
			}
			if regexp.MustCompile(`(?s)<script(?:\s[^>]*)?>[^<]`).MatchString(s) {
				t.Errorf("%s : script en ligne", p)
			}
		}
		for _, u := range reURL.FindAllString(s, -1) {
			// seul lien sortant autorisé : la CNIL, dans un <a href> de la page des données (jamais une ressource)
			if p == "donnees.html" && strings.HasPrefix(u, "https://www.cnil.fr") && strings.Contains(s, `<a href="`+u+`"`) {
				continue
			}
			t.Errorf("%s : URL absolue %s", p, u)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if total > 200*1024 {
		t.Errorf("web/ hors visuels pèse %d octets, 200 Ko au plus", total)
	}
}
