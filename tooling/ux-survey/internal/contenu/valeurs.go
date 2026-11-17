package contenu

import (
	"fmt"
	"regexp"
	"strings"
	"time"
)

var reValeur = regexp.MustCompile(`\{[a-z_]+\}`)

var mois = [...]string{"janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"}

// DateFrancaise écrit une date en toutes lettres : « 15 décembre 2026 », « 1er janvier 2027 ».
func DateFrancaise(t time.Time) string {
	jour := fmt.Sprint(t.Day())
	if t.Day() == 1 {
		jour = "1er"
	}
	return fmt.Sprintf("%s %s %d", jour, mois[t.Month()-1], t.Year())
}

// Valeurs renvoie les valeurs de configuration des textes (R5) : les seules connues de donnees.md.
func (c *Config) Valeurs() map[string]string {
	return map[string]string{
		"{date_fermeture}":     DateFrancaise(c.Fermeture),
		"{date_effacement}":    DateFrancaise(c.Effacement()),
		"{date_mise_a_jour}":   DateFrancaise(c.MentionMaj),
		"{seuil_statistiques}": fmt.Sprint(c.SeuilStats),
	}
}

// Remplacer substitue les valeurs dans un texte ; un motif inconnu, ou qui subsiste, est une erreur.
func Remplacer(texte string, valeurs map[string]string) (string, error) {
	for _, motif := range reValeur.FindAllString(texte, -1) {
		if _, ok := valeurs[motif]; !ok {
			return "", fmt.Errorf("valeur inconnue %s", motif)
		}
	}
	for motif, v := range valeurs {
		texte = strings.ReplaceAll(texte, motif, v)
	}
	if m := reValeur.FindString(texte); m != "" {
		return "", fmt.Errorf("valeur %s restante après remplacement", m)
	}
	return texte, nil
}
