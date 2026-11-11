package reponse

import "encoding/json"

// Envoi est le corps JSON de POST /api/reponses (§5.1).
type Envoi struct {
	Version  string                     `json:"version"`
	Jeton    string                     `json:"jeton"`
	SiteWeb  string                     `json:"site_web"`
	DureeS   json.RawMessage            `json:"duree_s"`
	Reponses map[string]json.RawMessage `json:"reponses"`
}

// SectionD1 est l'état d'une section de la barre latérale, avec son rang pour les sections gardées.
type SectionD1 struct {
	Code string `json:"code"`
	Etat string `json:"etat"`
	Rang int    `json:"rang,omitempty"`
}

// D1 est la réponse au tri de la barre latérale.
type D1 struct {
	ComeAujourdhui bool        `json:"comme_aujourdhui"`
	Sections       []SectionD1 `json:"sections,omitempty"`
}

// Etats de D1.
const (
	EtatGarder  = "garder"
	EtatDeplier = "deplier"
	EtatEcarter = "ecarter"
)

// Ligne est une réponse stockée, telle que lue en base (sans pseudo).
type Ligne struct {
	Identifiant string
	RecueLe     string
	Version     string
	DureeS      int
	OrdreCartes []string
	Donnees     map[string]json.RawMessage
	Limitee     bool // R13 : conservée mais exclue des statistiques et de tous les exports
}

// Normalisee est le résultat de la validation, prêt à être écrit.
type Normalisee struct {
	Donnees     map[string]json.RawMessage // sans I1
	Pseudo      string
	OrdreCartes []string // nil si absent ou invalide
	DureeS      int
}
