# Adopter le cadre dans un projet, le mettre à jour

Usage quotidien une fois adopté, avec l'exemple SwiftHFR : [UTILISATION](UTILISATION.md).

Pourquoi ce mécanisme (vendorisation + plugin + workflows réutilisables) et ses limites : [ADR 0001](adr/0001-mecanisme-de-distribution.md).

## Ce que le projet reçoit

| Chemin dans le projet | Mode | À qui |
|---|---|---|
| `.harness/docs/*.md` | copie | Cadre : remplacé à chaque synchro (modification locale détectée et refusée) |
| `.harness/labels.json` | copie | Cadre : taxonomie canonique |
| `.harness/hooks/guard-git.py`, `session-start.sh` | copie | Cadre |
| `.claude/skills/<skill>/SKILL.md` | copie | Cadre (`/intent`, `/lot-start`, `/lot-finish`, `/review-round`, `/feedback-triage`, `/lessons-check`, `/lesson-propose`, `/compliance-review`, `/status-report`, `/harness-update`) |
| `.claude/agents/*.md` | copie | Cadre : `adversarial-reviewer`, `issue-steward`, `doc-steward`, `flow-monitor`, `compliance-*` (exclure les référentiels inutiles) |
| `.harness/scripts/flow-metrics.py` | copie | Cadre : tableau de bord du flux (`flow-report.yml`, `/status-report`) |
| `.claude/settings.json` | fusion | Projet ; le cadre n'**ajoute** que ses deux hooks s'ils manquent |
| `CLAUDE.md`, `AGENTS.md` | bloc balisé | Projet, sauf le bloc `<!-- harness:begin cadre -->…<!-- harness:end cadre -->` |
| `.harness/config.json`, `.github/labels.local.json`, gabarits d'issue et de PR, `docs/lots/TEMPLATE.md`, `.markdownlint-cli2.jsonc`, `.github/workflows/harness.yml`, `.github/workflows/harness-sync.yml` | seed | Projet : créés s'ils manquent, jamais réécrits (sauf les références `@vX.Y.Z` de `harness.yml`) |
| `.harness/VERSION`, `.harness/lock` | généré | Version, commit du cadre, empreintes des fichiers copiés |

## Adoption (une fois, depuis le Mac ou une session cloud)

Prérequis : `bash`, `git`, `python3` ; accès en lecture à `francoisgn/agentic-harness` (en session cloud : l'attacher
à la session ; sur le Mac : `gh auth login && gh auth setup-git`).

1. **Branche** depuis la branche d'intégration à jour :
   ```bash
   git fetch origin && git switch -c chore/adoption-harness origin/develop
   ```
2. **Récupérer le cadre** à un tag, à côté du projet :
   ```bash
   git clone --depth 1 --branch v0.3.0 https://github.com/francoisgn/agentic-harness.git ../agentic-harness
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
   - `AGENTS.md` : section « Harness overrides » (créée par le gabarit, sinon l'ajouter) : chaque règle du cadre que
     le projet remplace, avec sa raison (convention de branches, taxonomie de labels, politique de merge…). C'est
     l'endroit que lisent les agents pour savoir où le projet s'écarte du cadre ; le bloc géré y renvoie.
   - `.harness/config.json` : `protected_branches`, `integration_branch`, `branch_model` (A ou B, BRANCHING-RELEASE.md).
   - `.github/labels.local.json` : les labels propres au projet (ex. `onglet: …`, `calcul`, `réglementaire`), au même
     format que `.harness/labels.json` (`axis` facultatif, utile pour l'hygiène des issues). Retirer l'ancien fichier de
     labels et son workflow s'il fait doublon avec le job `labels` de `harness.yml`.
   - `.github/workflows/harness.yml` : branche de `push`, `flow` (modèle A ou vide), jobs `docs`, `security` et `review`
     à activer seulement si le projet n'a pas déjà l'équivalent ; le job `flow` (tableau de bord) est actif d'office.
   - `.harness/config.json` → `compliance` : référentiels dont les relecteurs sont lancés ([COMPLIANCE](COMPLIANCE.md)). Supprimer les workflows qu'il remplace (ex. `branch-flow.yml`).
5. **Vérifier** : `../agentic-harness/scripts/harness-sync.sh --target . --check` sort en 0 ; `git diff --stat` ne
   montre que l'attendu ; lancer une session Claude et constater le message « Cadre agentic-harness » au démarrage.
6. **Commit unique**, puis PR en brouillon :
   `Cadre agentic-harness 0.3.0 : adoption` (corps : ce qui a été retiré du `CLAUDE.md`, workflows remplacés, labels
   déplacés ; pas de `### Ledger` : outillage).
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
    "agentic-harness": { "source": { "source": "github", "repo": "francoisgn/agentic-harness", "ref": "v0.3.0" } }
  },
  "enabledPlugins": { "harness@agentic-harness": true }
}
```
Dans un dépôt adopté, préférer ne **pas** l'activer (les skills existeraient en double, `/lot-start` et
`/harness:lot-start`).

## Mises à jour
- Skill `/harness-update` (guide pas à pas), ou à la main :
  ```bash
  git switch -c chore/harness-vX.Y.Z origin/develop
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
  "branch_model": "B",
  "labels": { "model_prefixes": [], "size_prefixes": ["difficulty:"] },
  "ledger": { "enabled": true, "label": "ledger", "fold_command": "python3 tooling/docs/ledger.py fold --apply --commit" }
}
```
- `language` : une source traduite `i18n/<langue>/<chemin>` du cadre remplace la source française quand elle existe.
  Aujourd'hui `en` couvre le bloc de `CLAUDE.md`/`AGENTS.md` et `ESSENTIEL.md` (le fichier chargé à chaque session) ;
  les autres docs restent en français.
- `exclude` : motifs glob sur les **destinations** (`*` traverse les `/`). Un fichier exclu n'est pas vendorisé ; s'il
  l'était déjà et n'a pas été modifié, la synchro suivante le retire. Exclure `CLAUDE.md` ou `AGENTS.md` supprime la
  gestion du bloc correspondant.

Autres clés, lues par les hooks et les skills (absentes : valeurs par défaut) :

| Clé | Défaut | Effet |
|---|---|---|
| `protected_branches` | `["main", "master", "develop", "beta"]` | Branches que le hook `guard-git` protège |
| `branch_types` | `["lot", "fix", "feat", "chore", "docs"]` | Types de branche `<type>/<nom-court>` proposés par `/lot-start` et le hook |
| `labels.model_prefixes` | `["modèle:"]` | Préfixes des labels de niveau de modèle ; `[]` = axe absent (niveau déduit du texte et du routage) |
| `labels.size_prefixes` | `["taille:"]` | Préfixes des labels de taille ou de difficulté (ex. `["difficulty:"]`) ; `[]` = axe absent |
| `ledger.enabled`, `ledger.label`, `ledger.fold_command` | `false`, `"ledger"`, `""` | Registre ([CONVENTIONS](CONVENTIONS.md) §Registre) : section `### Ledger` des PR, label, commande de repli du steward |

`.harness/config.json` est un fichier du projet (créé une fois) : une clé ajoutée par une nouvelle version du cadre ne
s'y ajoute pas d'elle-même ; sans elle, le défaut s'applique.

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
3. Garder la taxonomie de labels de HFRnow (`type:`, `priority:`, `difficulty:`…) : ne pas activer `apply-aliases` ;
   `labels` ci-dessus dit au cadre que la taille se lit dans `difficulty:` et que le niveau de modèle se déduit du
   routage d'`AGENTS.md` §6. Ses branches `lot/`, `fix/`, `feat/`, `chore/`, `docs/` sont celles du cadre ; son
   registre (#620) est la brique « ledger » du cadre, avec son propre script.
4. Les leçons génériques nées dans HFRnow remontent au cadre par PR sur agentic-harness ; les leçons du domaine HFR
   restent dans le projet.

## Brancher votre agent de code

Le cadre écrit ses règles une fois (`.harness/docs/`) et les expose par deux fichiers d'entrée : `CLAUDE.md` (bloc
balisé) et `AGENTS.md` (bloc balisé, [format ouvert](https://agents.md)). Selon l'outil :

| Agent | Comment il charge les règles | État |
|---|---|---|
| Claude Code | `CLAUDE.md` (import de `ESSENTIEL.md`), skills, agents et hooks vendorisés ; plugin en local | Adaptateur fourni, testé |
| Codex CLI, Cursor, GitHub Copilot (agent) | `AGENTS.md` à la racine, présenté comme lu nativement par ces outils | 🟠 à vérifier dans la doc de l'outil et la version utilisée |
| Gemini CLI | Lit `GEMINI.md` par défaut ; pointer le fichier de contexte vers `AGENTS.md` dans `.gemini/settings.json` | 🟠 réglage à confirmer dans la doc de Gemini CLI |
| Aider | Charger `AGENTS.md` comme fichier de conventions (`read: AGENTS.md` dans `.aider.conf.yml`) | 🟠 à confirmer dans la doc d'Aider |
| Autre | Lui faire lire `AGENTS.md`, ou y copier un renvoi vers `.harness/docs/ESSENTIEL.md` | — |

Sources consultées le 2026-11-07 : site du format [agents.md](https://agents.md) et articles secondaires (pas la doc
officielle de chaque outil) ; d'où l'état 🟠 tant qu'un projet ne l'a pas vérifié. Les skills, agents et hooks sont
propres à Claude Code ; pour un autre agent, la méthode, les labels, les gabarits, la CI et le tableau de bord
s'appliquent tels quels, et les skills se lisent comme des procédures (`.claude/skills/<nom>/SKILL.md`).

## Réglages du dépôt « as code »

Une session cloud ne peut pas modifier les réglages d'un dépôt (LESSONS L56) ; elle modifie
`.github/repo-settings.json` par PR, et le job `settings` de `harness.yml` (workflow réutilisable `repo-settings.yml`,
script `.harness/scripts/repo-settings.py`) l'applique au merge :

| Section | Effet |
|---|---|
| `repository` | Description, site, fonctions (wiki, discussions), politique de merge, suppression des branches mergées |
| `topics` | Liste complète des topics |
| `rulesets` | Rulesets gérés par nom (créés ou mis à jour, jamais supprimés automatiquement) : protection de la branche par défaut, contrôles requis |

- **Une fois, par le propriétaire** : créer un jeton fine-grained limité au dépôt, « Administration: read and write »,
  et l'enregistrer en secret de dépôt `REPO_ADMIN_TOKEN`. Sans lui, le job avertit et ne fait rien.
- **Dérive** : chaque lundi le job compare le dépôt au fichier et échoue si un réglage a été changé à la main.
- Contrôles requis : un nom de job direct d'un workflow déclenché par `pull_request` (le check d'un job de workflow
  réutilisable s'appelle `appelant / appelé`). Un nom faux bloquerait toutes les PR : `check-framework.py` le vérifie
  pour le cadre, pas pour le gabarit d'un projet (à vérifier à la main avant d'en ajouter).
- Aucun contournement (`bypass_actors`) n'est déclaré : en urgence, un admin désactive le ruleset dans Settings, puis
  le remet par le fichier.
- `--apply` absent (local) : `GH_TOKEN=… python3 .harness/scripts/repo-settings.py --repo owner/nom` affiche le plan.

## Remplacer ou étendre une brique

Le cadre est un **framework** : chaque brique a un point d'extension, aucune n'est imposée.

| Brique | Garder celle du cadre | La remplacer par celle de l'entreprise | La compléter |
|---|---|---|---|
| Relecteurs de conformité | `compliance: ["gdpr"]` | `{"id": …, "agent": "<son agent>"}` | `{"id": …, "spec": "docs/compliance/<id>.md"}` ([COMPLIANCE](COMPLIANCE.md) §2) |
| Relecteur adversarial, stewards | `.claude/agents/<nom>.md` vendorisé | Exclure le fichier (`exclude`) et poser le sien sous le même nom | Un agent du projet sous un autre nom |
| Skills | `.claude/skills/<nom>/` vendorisé | Exclure et poser le sien | Skills du projet sous d'autres noms |
| Service de revue | job `review` (`ai-review.yml`) | CodeRabbit ou autre bot : ne pas activer `review` | `.harness/review-instructions.md` |
| Sécurité | `security.yml`, `docs-security.yml` | Outils de l'entreprise (GHAS, SonarQube, Snyk) : ne pas activer ces jobs | Inputs (`semgrep-configs`, `trivy-severity`) |
| Réglages du dépôt | job `settings` + `.github/repo-settings.json` | Terraform / Safe-settings de l'entreprise : supprimer `settings` | Sections du fichier |
| Tableau de bord | job `flow` | Outil de pilotage maison : supprimer `flow` | Seuils en inputs (`stall-hours`, `max-ci-runs`…) |
| Labels | `.harness/labels.json` | Garder sa taxonomie (`apply-aliases: false`) | `.github/labels.local.json` |
| Leçons, règles | `.harness/docs/` | — (le `CLAUDE.md` du projet l'emporte) | Leçons et règles du projet dans ses propres fichiers |

Règle : on **n'édite jamais** une copie vendorisée (la synchro la refuse) ; on exclut et on remplace, ou on ajoute à
côté. Un remplacement utile à tous remonte au cadre par PR.

## Adoption partielle
- **Règles seulement** : exclure `.github/*` et `docs/lots/*`.
- **Workflows et labels seulement** : ne pas lancer la synchro ; appeler les workflows réutilisables depuis le
  `harness.yml` du projet en pointant `labels-file` vers une copie de la taxonomie (dépôt de `francoisgn` uniquement si
  le cadre reste privé).

## Retrait
Supprimer `.harness/`, le bloc balisé de `CLAUDE.md`/`AGENTS.md`, les skills vendorisés (liste dans `.harness/lock`), les
deux hooks de `.claude/settings.json` et `harness.yml` / `harness-sync.yml`.
