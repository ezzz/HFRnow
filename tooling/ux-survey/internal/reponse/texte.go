// Package reponse valide et normalise une réponse envoyée, côté serveur, sans faire confiance au front.
package reponse

import (
	"golang.org/x/text/unicode/norm"
	"strings"
	"unicode"
	"unicode/utf8"
)

// NormaliserTexte met un texte libre en forme : NFC, caractères de contrôle retirés sauf le retour à la
// ligne, marques d'orientation du texte retirées, espaces de bord retirés. Avec ligneUnique, les retours à
// la ligne deviennent des espaces (pseudo). Un texte vide en sortie vaut « absent ».
func NormaliserTexte(s string, ligneUnique bool) string {
	if !utf8.ValidString(s) {
		s = strings.ToValidUTF8(s, "")
	}
	s = strings.NewReplacer("\r\n", "\n", "\r", "\n").Replace(norm.NFC.String(s))
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
