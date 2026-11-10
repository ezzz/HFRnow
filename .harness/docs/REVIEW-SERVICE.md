# Service de revue : l'équivalent maison de CodeRabbit

Définition du service de revue automatique des PR du cadre. Il **complète** la revue adversariale de la session
([ORCHESTRATION](ORCHESTRATION.md) §3) et ne la remplace pas. Implémentation : workflow réutilisable
`.github/workflows/ai-review.yml` (action `anthropics/claude-code-action`, épinglée par SHA).

## 1. Contrat du service

| Élément | Définition |
|---|---|
| Déclencheur | PR **prête** (`ready_for_review`, puis `synchronize`) ; jamais un brouillon ; label `revue: aucune` → sautée |
| Entrées | Diff `base...tête`, spec liée (`Closes`/`Refs`), `CLAUDE.md`, `ESSENTIEL.md`, `LESSONS.md`, consignes du projet (`.harness/review-instructions.md`) |
| Sortie | **Un** commentaire de revue par tête : verdict `APPROUVÉ` / `CHANGEMENTS DEMANDÉS`, constats numérotés (Haute / Moyenne / Basse / Détail, `fichier:ligne`, scénario d'échec, correctif), liste « Vérifié » |
| Droits | Lecture du code ; un **commentaire** de PR seulement (`gh pr comment`), jamais une revue GitHub : il ne peut pas approuver, même sous injection de prompt. Ni commit, ni push, ni merge |
| Modèle | Niveau ≥ celui de l'issue, **autre** que l'auteur si possible ; défaut : solide ; frontière pour les flux à risque |
| Secrets | `ANTHROPIC_API_KEY` ou `CLAUDE_CODE_OAUTH_TOKEN` (secret de dépôt ou d'organisation) |
| Forks | Pas de secret → job sauté ; c'est pourquoi le contrôle n'est **jamais requis** dans le ruleset |
| Coût | 1 job Linux + les jetons d'une revue ; annulé par un nouveau push (`concurrency`) ; tours bornés |

## 2. Ce qui le distingue d'un bot générique
- Il juge contre **nos** règles : leçons (`L..`), conventions, définition de fini, sources citées, budget CI.
- Il ne commente pas le style qu'un linter attrape, et regroupe les cas d'une même classe (moins de cycles).
- Une faille exploitable n'est jamais détaillée publiquement.
- Ses constats suivent [REVIEW-ROUNDS](REVIEW-ROUNDS.md) comme ceux de CodeRabbit : affirmation à vérifier, un commit
  par cycle, une réponse par fil.

## 3. Optimiser les cycles (volume agentique)
Un dépôt où les agents poussent l'essentiel des commits multiplie les revues. Leviers, du plus rentable au moins :
1. **Prévenir** : `/lessons-check` et la revue adversariale **avant** « Ready » ; le service ne doit trouver que ce qui
   a échappé aux deux. Un constat déjà dans LESSONS = l'auto-relecture est à resserrer.
2. **Une revue par tête prête**, pas par push : pushes fréquents sur le brouillon pendant le travail (pas de revue), un push par cycle une fois prête.
3. **Revue incrémentale** : au cycle suivant, consigne de ne relire que `dernier-sha-relu...tête` (le service lit sa
   revue précédente).
4. **Borne** : au-delà de 3 cycles, l'orchestrateur arrête la boucle ([FINOPS](FINOPS.md) §3).
5. **Graduer** : label `revue: aucune` pour les PR triviales (Dependabot de patch, typo), modèle frontière seulement
   sur les labels `sécurité`, `modèle: opus` ou `modèle: fable`.

## 4. Mise en place dans un projet
1. Secret `ANTHROPIC_API_KEY` (ou jeton OAuth Claude Code) ; app GitHub Claude installée par le propriétaire (L57).
2. Dans `.github/workflows/harness.yml`, activer le job `review` (gabarit commenté).
3. Facultatif : `.harness/review-instructions.md` (règles par dossier, comme les `path_instructions` de CodeRabbit).
4. Si CodeRabbit reste installé : garder les deux un temps, comparer les constats pertinents sur 10 PR, puis n'en
   garder qu'un (on ne paie pas deux fois).
