# Budget CI et socle de sécurité

Sources : `ci.yml`, ADR 0005 (et son amendement du 05/11, #477), `CONTRIBUTING.md` §4, `.pre-commit-config.yaml` de
HFRnow ; pratique éprouvée sur d'autres projets (workflows de CI et de sécurité, script de CI locale).

## 1. Les deux règles de facturation
Sur un dépôt privé, le quota gratuit est de 2 000 minutes par mois, et :
- **une minute macOS en compte 10** ;
- **chaque job est arrondi à la minute supérieure** (un job de 7 s coûte 1 min).

Un **dépôt public ne consomme aucune minute** (runners standard, macOS compris) et donne gratuitement CodeQL et le
secret scanning : c'est le levier le plus fort quand le projet peut être public.

## 2. Règles 🟢

### Pousser souvent, payer au passage « Ready »
Un push ne doit rien coûter ; ce qui coûte, c'est la CI qu'il déclenche. Donc :
- **Pousser tôt et souvent sur une PR en brouillon** : le travail survit à un plantage de session, il est visible des
  autres sessions et de l'opérateur. Sur un brouillon, **rien de coûteux ne tourne** (macOS, jobs longs, sécurité
  lourde) ; au plus un contrôle Linux de quelques secondes si le projet le veut.
- **La CI coûteuse tourne au passage « Ready for review »**, ou à la demande par un **label explicite** (ex.
  `ci: complète`) posé sur un brouillon quand on a vraiment besoin d'un verdict macOS avant la fin.
- **Un commit par cycle de revue** : tous les constats d'un cycle corrigés, contrôlés en local, puis un seul push.
- **Jamais de push « pour voir si la CI passe » sur une PR prête** : les contrôles rapides tournent en local avant
  (`local-check.sh` ou équivalent, pre-commit, build Mac si l'app change) ; la CI confirme, elle ne découvre pas.
  Besoin d'essayer ? Repasser la PR en brouillon, ou poser le label sur le brouillon.
- **Aucune minute gaspillée** : un passage annulé, un job sauté ou une PR de docs ne doit pas allumer de runner macOS.

Le mécanisme (recommandation à adapter ; le nom du label est au choix du projet) : la CI est un workflow
réutilisable, appelé par deux déclencheurs séparés.
```yaml
# .github/workflows/ci.yml : pushes et passage « Ready » ; un brouillon ne lance que s'il porte le label
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    if: ${{ !github.event.pull_request.draft || contains(github.event.pull_request.labels.*.name, 'ci: complète') }}
    uses: ./.github/workflows/ci-jobs.yml   # jobs `linux` puis `macos` (needs: linux), noms = contrôles requis
---
# .github/workflows/ci-label.yml : le label posé sur un brouillon lance la CI complète tout de suite
on:
  pull_request:
    types: [labeled]
jobs:
  ci-label:   # autre nom : ses contrôles (`ci-label / …`) ne remplacent jamais les contrôles requis
    if: ${{ github.event.label.name == 'ci: complète' && github.event.pull_request.draft }}
    concurrency:   # au niveau du job : un job sauté (autre label) ne rejoint aucun groupe, n'annule rien
      group: ci-label-${{ github.event.pull_request.number }}
      cancel-in-progress: true
    uses: ./.github/workflows/ci-jobs.yml
```
- `ready_for_review` dans les types : la CI part d'elle-même au passage « Ready ».
- Les labels sont dans un **workflow à part**, sans `concurrency` au niveau du workflow : un autre label (`ledger`,
  `pris en charge`…) n'y produit qu'un job sauté sous un autre nom, qui n'annule pas la CI en cours et ne publie pas
  de contrôle requis « sauté » sur la tête (un job sauté compte comme réussi pour un contrôle requis, §4). Les
  contrôles requis viennent seulement de `ci.yml`, qui repart au passage « Ready ».
- Un job sauté sur un brouillon ne gêne pas : un brouillon ne se merge pas, et le passage « Ready » relance tout.
- Variante quand les runners macOS sont rares et que le job macOS est requis : sur un brouillon, le faire tourner sur un
  runner Linux qui échoue tout de suite (« brouillon : CI macOS au passage Ready ») plutôt que d'attendre un runner.

### Le reste
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
- CodeQL et l'analyse lourde peuvent ne tourner que sur la branche d'intégration et sur les PR d'un label dédié (flux à
  risque).

**Ordre de grandeur** : mesurer ce que coûte un push sur une PR prête, avec et sans changement de l'app ; le chiffre
guide les réglages (détection de changements, `needs:`, étapes réservées aux promotions). Le tableau de bord
([FINOPS](FINOPS.md) §4) suit les minutes facturées.

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

Pipeline complet en un appel : `security.yml` (Semgrep CE, Trivy `fs`, gitleaks, en un job ; règles Semgrep par défaut
`p/default p/secrets p/github-actions`, ajouter celles du langage, ex. `p/swift`) ; `docs-security.yml`
pour les docs et les workflows. Appeler l'un et l'autre sans doubler gitleaks (input `gitleaks: false` sur l'un).

### Secrets et variables : rien en dur
- **Aucun secret dans le dépôt**, même chiffré à la main, même en test : secrets GitHub (dépôt, environnement,
  organisation) ou coffre ; en session cloud, les secrets réseau de l'environnement, jamais collés dans le chat.
- **Configuration non secrète** (URL, identifiant de projet, région, nom de bucket) dans des **variables** :
  `vars.NOM` dans les workflows, variables d'environnement ou fichier de configuration par environnement côté code ;
  jamais une valeur d'environnement en dur dans le code.
- Dans un workflow : secret et variable passent par `env:`, jamais interpolés dans `run:` ; un secret n'est donné
  qu'au job qui en a besoin, et jamais sur un événement de fork.
- Un secret commité est **compromis** : le révoquer d'abord, réécrire l'historique ensuite si besoin (gitleaks
  l'aurait signalé : comprendre pourquoi il est passé).
- Fichiers d'exemple (`.env.example`) avec des valeurs factices évidentes ; `.env` dans `.gitignore`.

## 4. Contrôles requis et merge
Les contrôles requis du ruleset portent les **noms de jobs** : renommer un job oblige à mettre à jour le ruleset. Un job
sauté (`if:` faux) compte comme réussi pour un contrôle requis : c'est ce qui permet de sauter le build iOS sans bloquer
la PR. La CI ne juge ni l'UX, ni les hypothèses sur un système externe, ni un réglage supprimé : la spec et la revue s'en
chargent (LESSONS L44).

## 5. Volume agentique : beaucoup de commits, peu de passages

Des agents produisent bien plus de commits qu'un humain (ratio suivi par le tableau de bord, [FINOPS](FINOPS.md) §4).
La CI doit coûter par **lot prêt**, pas par commit :
- les commits restent fins et sont **poussés souvent sur le brouillon** (rien de coûteux n'y tourne) ; la CI complète
  part au passage « Ready for review » ou sur le label explicite (§2) ; ensuite, un push par cycle de revue ;
- les contrôles rapides (lint, secrets, tests unitaires) tournent **en local avant le push** (pre-commit,
  `local-check.sh`) : la CI confirme, elle ne découvre pas ;
- détection de changements et `paths-ignore` : une PR de docs ne lance pas le build ; la sécurité lourde (SAST, SCA)
  tourne sur les PR prêtes, la branche d'intégration et chaque semaine, pas sur chaque push ;
- revue automatique une fois par tête prête ([REVIEW-SERVICE](REVIEW-SERVICE.md) §3) ;
- au-delà de 6 pushes testés par la CI sur une PR, la boucle s'arrête ([FINOPS](FINOPS.md) §3).
