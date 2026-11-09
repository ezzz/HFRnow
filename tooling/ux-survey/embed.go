// Package uxsurvey porte les fichiers embarqués dans le binaire : le front (web/) et le contenu du questionnaire.
package uxsurvey

import (
	"embed"
	"io/fs"
)

//go:embed web contenu
var fichiers embed.FS

// Web renvoie le front embarqué (index.html, donnees.html, app.js, style.css, visuels/…).
func Web() fs.FS {
	sub, err := fs.Sub(fichiers, "web")
	if err != nil {
		panic(err) // le dossier est embarqué à la compilation : jamais d'erreur à l'exécution
	}
	return sub
}

// ContenuJSON renvoie le fichier questionnaire.json embarqué.
func ContenuJSON() []byte {
	b, err := fichiers.ReadFile("contenu/questionnaire.json")
	if err != nil {
		panic(err)
	}
	return b
}
