// Package exporter produit les exports : analyse (pseudonymisée), agrégats (publication) et pseudos.
package exporter

import (
	"bytes"
	"encoding/csv"
	"strings"
)

// bom est la marque d'ordre des octets UTF-8, pour que les tableurs lisent l'accentuation.
var bom = []byte{0xEF, 0xBB, 0xBF}

// Neutraliser préfixe d'une apostrophe toute cellule qui commence par un caractère de formule
// (=, +, -, @, tabulation, retour chariot) : protection contre l'injection de formules.
func Neutraliser(cellule string) string {
	if cellule != "" && strings.ContainsRune("=+-@\t\r", rune(cellule[0])) {
		return "'" + cellule
	}
	return cellule
}

// EcrireCSV renvoie un CSV UTF-8 avec BOM, RFC 4180 (fins de ligne CRLF), cellules neutralisées.
func EcrireCSV(lignes [][]string) ([]byte, error) {
	var buf bytes.Buffer
	buf.Write(bom)
	w := csv.NewWriter(&buf)
	w.UseCRLF = true
	for _, l := range lignes {
		sortie := make([]string, len(l))
		for i, c := range l {
			sortie[i] = Neutraliser(c)
		}
		if err := w.Write(sortie); err != nil {
			return nil, err
		}
	}
	w.Flush()
	return buf.Bytes(), w.Error()
}
