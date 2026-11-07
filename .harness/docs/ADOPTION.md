# Adopter le cadre dans un projet, le mettre à jour

Pourquoi ce mécanisme (vendorisation + plugin + workflows réutilisables) et ses limites : [ADR 0001](adr/0001-mecanisme-de-distribution.md).

## Ce que le projet reçoit

| Chemin dans le projet | Mode | À qui |
|---|---|---|
| `.harness/docs/*.md` | copie | Cadre : remplacé à chaque synchro (modification locale détectée et refusée) |
| `.harness/labels.json` | copie | Cadre : taxonomie canonique |
| `.harness/hooks/guard-git.py`, `session-start.sh` | copie | Cadre |
| `.claude/skills/<skill>/SKILL.md` | copie | Cadre (`/lot-start`, `/lot-finish`, `/review-round`, `/feedback-triage`, `/lessons-check`, `/harness-update`) |
| `.claude/settings.json` | fusion | Projet ; le cadre n'**ajoute** que ses deux hooks s'ils manquent |
| `CLAUDE.md`, `AGENTS.md` | bloc balisé | Projet, sauf le bloc `<!-- harness:begin cadre -->…<!-- harness:end cadre -->` |
| `.harness/config.json`, `.github/labels.local.json`, gabarits d'issue et de PR, `docs/lots/TEMPLATE.md`, `.markdownlint-cli2.jsonc`, `.github/workflows/harness.yml`, `.github/workflows/harness-sync.yml` | seed | Projet : créés s'ils manquent, jamais réécrits (sauf les références `@vX.Y.Z` de `harness.yml`) |
| `.harness/VERSION`, `.harness/lock` | généré | Version, commit du cadre, empreintes des fichiers copiés |

## Adoption (une fois, depuis le Mac ou une session cloud)

Prérequis : `bash`, `git`, `python3` ; accès en lecture à `francoisgn/agentic-harness` (en session cloud : l'attacher
à la session ; sur le Mac : `gh auth login && gh auth setup-git`).

1. **Branche** depuis la branche d'intégration à jour :
   ```bash
   git fetch origin && git switch -c claude/adoption-harness origin/develop
   ```
2. **Récupérer le cadre** à un tag, à côté du projet :
   ```bash
   git clone --depth 1 --branch v0.1.0 https://github.com/francoisgn/agentic-harness.git ../agentic-harness
   ```
3. **Voir avant d'écrire**, puis appliquer :
   ```bash
   ../agentic-harness/scripts/harness-sync.sh --target . --dry-run
   ../agentic-harness/scripts/harness-sync.sh --target .
   ```
   Code 3 = conflits : un fichier du cadre existe déjà dans le projet (ex. un skill du même nom). Renommer celui du
   projet, ou relancer avec `--force` si le remplacer est voulu.
4. **Adapter** (fichiers du projet) :
   - `CLAUDE.md` : le bloc du cadre a été ajouté **en fin** de fichier s'il existait ; le remonter en tête (marqueurs
     compris) et retirer de la partie projet ce qui double désormais `ESSENTIEL.md` (workflow générique, pied de
     commentaire, labels génériques). Garder le spécifique : build, design system, règles métier, modèle de branches.
   - `.harness/config.json` : `protected_branches`, `integration_branch`, `branch_model` (A ou B, BRANCHING-RELEASE.md).
   - `.github/labels.local.json` : les labels propres au projet (ex. `onglet: …`, `calcul`, `réglementaire`), au même
     format que `.harness/labels.json` (`axis` facultatif, utile pour l'hygiène des issues). Retirer l'ancien fichier de
     labels et son workflow s'il fait doublon avec le job `labels` de `harness.yml`.
   - `.github/workflows/harness.yml` : branche de `push`, `flow` (modèle A ou vide), job `security` à activer seulement
     si le projet n'a pas déjà l'équivalent. Supprimer les workflows qu'il remplace (ex. `branch-flow.yml`).
5. **Vérifier** : `../agentic-harness/scripts/harness-sync.sh --target . --check` sort en 0 ; `git diff --stat` ne
   montre que l'attendu ; lancer une session Claude et constater le message « Cadre agentic-harness » au démarrage.
6. **Commit unique**, puis PR en brouillon :
   `Cadre agentic-harness 0.1.0 : adoption` (corps : ce qui a été retiré du `CLAUDE.md`, workflows remplacés, labels
   déplacés ; `## Changelog` : « Aucun (outillage) »).
7. **Après le merge** (opérateur) : lancer le workflow « Cadre » à la main (`workflow_dispatch`) pour créer les labels ;
   si ce dépôt du cadre est privé, vérifier l'accès Actions ([ADR 0001](adr/0001-mecanisme-de-distribution.md)).

### Facultatif : PR de mise à jour automatique
`harness-sync.yml` (créé à l'adoption) regarde chaque lundi le dernier tag et ouvre une PR en brouillon. Réglages :
- cadre privé : secret `HARNESS_TOKEN` (jeton fine-grained : *Contents: read* sur `agentic-harness` ; *Contents* et
  *Pull requests: write* sur le projet ; *Workflows: write* si l'on veut aussi les références de `harness.yml`, avec la
  variable de dépôt `HARNESS_SYNC_WORKFLOWS=true`) ;
- avec le seul `GITHUB_TOKEN` : Settings → Actions → General → « Allow GitHub Actions to create and approve pull requests ».

### Facultatif : le plugin pour les sessions locales
Dans un dépôt qui a adopté le cadre, les skills et hooks vendorisés suffisent (et marchent en cloud). Le plugin sert sur
le Mac pour les dépôts **pas encore** adoptés :
```bash
claude plugin marketplace add francoisgn/agentic-harness
claude plugin install harness@agentic-harness            # portée utilisateur
```
Ses skills s'appellent alors `/harness:lot-start`, etc. Mise à jour automatique : `/plugin` → Marketplaces →
agentic-harness → Enable auto-update. Pour le déclarer dans un dépôt (sessions locales seulement ; une session cloud
l'ignore), ajouter à `.claude/settings.json` :
```json
{
  "extraKnownMarketplaces": {
    "agentic-harness": { "source": { "source": "github", "repo": "francoisgn/agentic-harness", "ref": "v0.1.0" } }
  },
  "enabledPlugins": { "harness@agentic-harness": true }
}
```
Dans un dépôt adopté, préférer ne **pas** l'activer (les skills existeraient en double, `/lot-start` et
`/harness:lot-start`).

## Mises à jour
- Skill `/harness-update` (guide pas à pas), ou à la main :
  ```bash
  git switch -c claude/harness-vX.Y.Z origin/develop
  ../agentic-harness/scripts/harness-sync.sh --ref vX.Y.Z --target .     # ou --source <clone à ce tag>
  ```
  Lire le `CHANGELOG.md` du cadre, relire `git diff`, un commit `Cadre agentic-harness : passage en vX.Y.Z`, PR brouillon.
- Une modification d'un fichier du cadre dans le projet est refusée à la synchro suivante : la proposer au cadre (PR sur
  `agentic-harness`), ou la garder hors du cadre (fichier du projet), jamais en modifiant la copie vendorisée.
- `--check` en CI (facultatif) : signale une copie vendorisée modifiée ou en retard sur `.harness/VERSION`.

## Réglages par projet : langue et exclusions
`.harness/config.json` (créé par la première synchro ; le créer **avant** elle pour que ses réglages s'appliquent dès
la première fois) :
```json
{
  "language": "en",
  "exclude": [".claude/skills/feedback-triage/*", ".github/ISSUE_TEMPLATE/*", "docs/lots/TEMPLATE.md"],
  "protected_branches": ["master", "dev-swift"],
  "integration_branch": "dev-swift",
  "branch_model": "B"
}
```
- `language` : une source traduite `i18n/<langue>/<chemin>` du cadre remplace la source française quand elle existe.
  Aujourd'hui `en` couvre le bloc de `CLAUDE.md`/`AGENTS.md` et `ESSENTIEL.md` (le fichier chargé à chaque session) ;
  les autres docs restent en français.
- `exclude` : motifs glob sur les **destinations** (`*` traverse les `/`). Un fichier exclu n'est pas vendorisé ; s'il
  l'était déjà et n'a pas été modifié, la synchro suivante le retire. Exclure `CLAUDE.md` ou `AGENTS.md` supprime la
  gestion du bloc correspondant.

### Exemple : ezzz/HFRnow (branche `dev-swift`, docs en anglais, leçons et lots propres)
1. Branche depuis `dev-swift` (jamais `master`, qui est l'app historique) ; créer `.harness/config.json` comme ci-dessus,
   en excluant ce que HFRnow a déjà en mieux : ses formulaires d'issue (`.github/ISSUE_TEMPLATE/*`), son gabarit de PR
   (`.github/pull_request_template.md`), son gabarit de lot (`docs/lots/TEMPLATE.md`), `.markdownlint-cli2.jsonc`, et
   les workflows du cadre (`.github/workflows/harness*.yml`) : `ezzz/HFRnow` n'appartient pas à `francoisgn`, il ne peut
   pas appeler un workflow réutilisable d'un cadre privé, et les événements `issues` ne tournent que depuis `master`.
2. Lancer la synchro : `AGENTS.md` (l'entrée de HFRnow) reçoit le bloc anglais en fin de fichier, `CLAUDE.md` (qui
   importe déjà `@AGENTS.md`) le bloc anglais qui importe `ESSENTIEL.md` ; `.harness/docs/LESSONS.md` du cadre complète
   `docs/agents/LESSONS.md` du projet, qui reste la référence (les deux se lisent à l'auto-relecture ; `/lessons-check`
   le fait).
3. Garder la taxonomie de labels de HFRnow (`type:`, `priority:`, `difficulty:`…) : ne pas activer `apply-aliases`.
4. Les leçons génériques nées dans HFRnow remontent au cadre par PR sur agentic-harness ; les leçons du domaine HFR
   restent dans le projet.

## Adoption partielle
- **Règles seulement** : exclure `.github/*` et `docs/lots/*`.
- **Workflows et labels seulement** : ne pas lancer la synchro ; appeler les workflows réutilisables depuis le
  `harness.yml` du projet en pointant `labels-file` vers une copie de la taxonomie (dépôt de `francoisgn` uniquement si
  le cadre reste privé).

## Retrait
Supprimer `.harness/`, le bloc balisé de `CLAUDE.md`/`AGENTS.md`, les skills vendorisés (liste dans `.harness/lock`), les
deux hooks de `.claude/settings.json` et `harness.yml` / `harness-sync.yml`.
