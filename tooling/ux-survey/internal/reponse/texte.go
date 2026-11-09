// Package reponse valide et normalise une réponse envoyée, côté serveur, sans faire confiance au front.
package reponse

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

// composition liste les compositions NFC des lettres latines accentuées courantes. La bibliothèque
// standard n'a pas de normalisation Unicode (elle est dans golang.org/x/text, dépendance que la spec
// n'autorise pas) : ce sous-ensemble couvre le français et les langues voisines.
var composition = map[[2]rune]rune{}

func init() {
	ajouter := func(marque rune, bases, resultats string) {
		b, r := []rune(bases), []rune(resultats)
		for i := range b {
			composition[[2]rune{b[i], marque}] = r[i]
		}
	}
	ajouter('̀', "AEIOUaeiou", "ÀÈÌÒÙàèìòù")
	ajouter('́', "AEIOUYaeiouy", "ÁÉÍÓÚÝáéíóúý")
	ajouter('̂', "AEIOUaeiou", "ÂÊÎÔÛâêîôû")
	ajouter('̃', "ANOano", "ÃÑÕãñõ")
	ajouter('̈', "AEIOUaeiouyY", "ÄËÏÖÜäëïöüÿŸ")
	ajouter('̊', "Aa", "Åå")
	ajouter('̧', "Cc", "Çç")
}

// NFC compose les lettres accentuées décomposées (e + U+0301 donne é).
func NFC(s string) string {
	if !strings.ContainsFunc(s, func(r rune) bool { return r >= 0x300 && r <= 0x36F }) {
		return s
	}
	out := make([]rune, 0, len(s))
	for _, r := range s {
		if n := len(out); n > 0 {
			if c, ok := composition[[2]rune{out[n-1], r}]; ok {
				out[n-1] = c
				continue
			}
		}
		out = append(out, r)
	}
	return string(out)
}

// NormaliserTexte met un texte libre en forme : NFC, caractères de contrôle retirés sauf le retour à la
// ligne, marques d'orientation du texte retirées, espaces de bord retirés. Avec ligneUnique, les retours à
// la ligne deviennent des espaces (pseudo). Un texte vide en sortie vaut « absent ».
func NormaliserTexte(s string, ligneUnique bool) string {
	if !utf8.ValidString(s) {
		s = strings.ToValidUTF8(s, "")
	}
	s = strings.NewReplacer("\r\n", "\n", "\r", "\n").Replace(NFC(s))
	var b strings.Builder
	for _, r := range s {
		switch {
		case r == '\n':
			if ligneUnique {
				b.WriteRune(' ')
			} else {
				b.WriteRune(r)
			}
		case unicode.IsControl(r), r >= '‪' && r <= '‮', r >= '⁦' && r <= '⁩':
		default:
			b.WriteRune(r)
		}
	}
	return strings.TrimSpace(b.String())
}

// Longueur compte les caractères (points de code) d'un texte.
func Longueur(s string) int { return utf8.RuneCountInString(s) }
