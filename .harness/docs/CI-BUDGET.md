# Budget CI et socle de sécurité

Sources : `docs/CI.md`, `ci.yml`, `security.yml`, `scripts/ci/local-check.sh` de ios-app_credit-immo ; `ci.yml`,
ADR 0005 (et son amendement du 05/11, #477), `CONTRIBUTING.md` §4, `.pre-commit-config.yaml` de HFRnow.

## 1. Les deux règles de facturation
Sur un dépôt privé, le quota gratuit est de 2 000 minutes par mois, et :
- **une minute macOS en compte 10** ;
- **chaque job est arrondi à la minute supérieure** (un job de 7 s coûte 1 min).

Un **dépôt public ne consomme aucune minute** (runners standard, macOS compris) et donne gratuitement CodeQL et le
secret scanning : c'est le levier le plus fort quand le projet peut être public.

## 2. Règles 🟢
- **PR en brouillon** pendant le travail : rien ne tourne (jobs conditionnés par `github.event.pull_request.draft != true`,
  et `ready_for_review` dans les types d'événement pour lancer la CI au passage « Ready for review »).
- **Un seul push par lot**, après les contrôles locaux (`scripts/ci/local-check.sh` ou équivalent) et le build Mac si
  l'app change. Pas de push d'essai.
- **Regrouper** les contrôles Linux dans un job par workflow (tests + couverture + lint ; un seul job sécurité).
- **Le job macOS dépend du job Linux** (`needs:`) : un lint ou un test rouge n'allume pas de runner macOS.
- **Détection de changements** : le build iOS ne part que si l'app ou le moteur change (`git diff --quiet BASE...HEAD --
  <chemins>`) ; si la détection échoue, il part quand même (LESSONS L49). `paths-ignore` pour les PR de doc.
- Les étapes longues (configurations supplémentaires, tests sur simulateur) sont réservées aux **promotions** et au
  lancement manuel.
- Après un merge sur une branche protégée : les contrôles Linux seulement (deux PR vertes peuvent se casser réunies).
- `concurrency` avec `cancel-in-progress` sur les PR : un nouveau push annule le passage en cours ; jamais sur les
  branches protégées.
- Artefacts (journaux xcodebuild) téléversés **seulement en cas d'échec**, rétention courte.
- Bots de revue : pas de revue des brouillons ni des fichiers générés.
- Quand le quota est épuisé : rejouer la CI en local avant chaque merge (`local-check.sh` signale « INCOMPLET » s'il
  manque un outil, plutôt que de se dire vert).

Variante HFRnow (runners macOS rares) : sur un brouillon, les jobs macOS requis échouent **immédiatement** sur un
runner Linux (« Draft PR ») au lieu d'attendre ; ils tournent pour de vrai au passage « Ready for review ». CodeQL Swift
ne tourne que sur la branche d'intégration et sur les PR labellisées `codeql` (flux à risque).

**Ordre de grandeur (credit-immo, mesuré le 01/11)** : un push sur une PR coûtait 19 min de quota quoi qu'il touche ;
il en coûte 4 sans changement de l'app (ou en cas d'échec Linux), 14 sinon. Une promotion coûte 4 + 30 min.

## 3. Socle de sécurité
Tout gratuit, sans compte tiers. Workflow réutilisable du cadre : `docs-security.yml` (markdownlint, gitleaks, zizmor,
actionlint en un job).

| Besoin | Dépôt public | Dépôt privé (sans GHAS) |
|---|---|---|
| SAST | CodeQL | Semgrep CE (`p/swift`, `p/secrets`, `p/github-actions`) |
| Dépendances (SCA) | Dependabot + Dependency Review (échec dès `moderate`) | Dependabot + Trivy `fs` (HIGH/CRITICAL) |
| Secrets | secret scanning + protection au push + gitleaks | gitleaks (historique complet) |
| Workflows | zizmor + actionlint (+ shellcheck des `run:`) | idem |
| Scripts | ShellCheck via pre-commit | idem |
| Syntaxe | pre-commit : `check-yaml`, `check-json`, `check-merge-conflict`, `check-added-large-files`, `detect-private-key` | idem |

Le workflow de sécurité tourne aussi **chaque semaine** (nouvelles CVE sans commit) et sur les PR de doc (un secret peut
se glisser dans un `.md`).

Hygiène des workflows (vérifiée par zizmor et par la revue) :
- actions **épinglées par SHA complet**, version en commentaire (`@3d3c…b1 # v7.0.1`) ; Dependabot (`github-actions`,
  groupé) les met à jour ;
- `permissions: contents: read` (ou `{}`) en tête, droits élargis seulement au job qui en a besoin ;
- `actions/checkout` avec `persist-credentials: false` ;
- jamais de `${{ … }}` venant d'un événement dans un `run:` : passer par `env:` ;
- jamais de `pull_request_target` qui extrait le code de la PR ; tout contrôle requis passe **sans secret** (PR de fork) ;
- outils lancés en conteneur à version fixée (`semgrep/semgrep:1.122.0`, `aquasec/trivy:0.62.1`,
  `ghcr.io/gitleaks/gitleaks:v8.30.1`, `rhysd/actionlint:1.7.7`, `zizmor==1.31.1`) ou binaire avec empreinte SHA-256
  vérifiée (SwiftLint) ;
- pre-commit : dépôts de hooks figés par SHA (Dependabot ne lit pas ce fichier : mise à jour à la main) ; aucun hook de
  reformatage (les données de test restent à l'octet près).

## 4. Contrôles requis et merge
Les contrôles requis du ruleset portent les **noms de jobs** : renommer un job oblige à mettre à jour le ruleset. Un job
sauté (`if:` faux) compte comme réussi pour un contrôle requis : c'est ce qui permet de sauter le build iOS sans bloquer
la PR. La CI ne juge ni l'UX, ni les hypothèses sur un système externe, ni un réglage supprimé : la spec et la revue s'en
chargent (LESSONS L44).
