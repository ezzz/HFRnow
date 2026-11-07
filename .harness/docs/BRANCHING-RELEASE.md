# Branches, versions et livraisons

Sources : `docs/BRANCHING.md` et workflow `branch-flow.yml` de ios-app_credit-immo (modèle A) ; `AGENTS.md` §8,
`CONTRIBUTING.md` §2 et rulesets de HFRnow (modèle B).

## Deux modèles, un choix par projet
Le projet écrit son modèle dans `CLAUDE.md` et dans `.harness/config.json` (`branch_model`, `integration_branch`,
`protected_branches` : la liste que le hook `guard-git` protège).

### Modèle A : intégration → candidate → production (app publiée)
```
claude/*, feature/*, dependabot/*  ──PR──▶  develop  ──PR──▶  beta  ──PR──▶  master
                                         intégration     TestFlight      App Store
hotfix/* (depuis master) ──PR──▶ master, puis report master → beta → develop
```
- `develop` est la branche par défaut (les PR, Dependabot, les workflows planifiés la visent).
- **Promotion** = PR `develop → beta` puis `beta → master` en **merge commit**, jamais en squash : les historiques restent
  identiques d'une branche à l'autre.
- **Hotfix** : `hotfix/<sujet>` depuis `master`, PR vers `master`, puis PR `master → beta` et `beta → develop` (ou
  cherry-pick) pour ne pas perdre le correctif.
- Garde-fou : `pr-hygiene.yml` avec `flow: "beta:develop beta:hotfix/* master:beta master:hotfix/*"` refuse toute PR vers
  `beta` ou `master` hors flux ; vers `develop`, rien n'est imposé automatiquement.

### Modèle B : une seule branche d'intégration (moteur, bibliothèque, projet partagé)
- Une branche d'intégration protégée par ruleset : PR obligatoire, contrôles requis, squash seulement, pas de
  force-push, conversations résolues. L'exigence « à jour avec la base » peut être retirée pour ne pas relancer la CI à
  chaque merge voisin (HFRnow, 28/10).
- Merge en **squash** (une PR = un commit). L'auto-merge, s'il est permis, est une décision de merge.
- Si les merges ne ferment pas les issues (branche d'intégration qui n'est pas la branche par défaut), celui qui merge
  ferme l'issue avec « Fait dans #PR (mergée en `<sha>`) » et vérifie qu'elle est fermée.

## Règles communes
- **Aucun push direct** sur une branche protégée ; **jamais de force-push** sur une branche partagée ; jamais
  contourner un ruleset, la protection au push ou gitleaks (hook `guard-git` côté agent, rulesets côté GitHub).
- Branches de travail : `claude/<lot>` (sessions Claude), `feature/<sujet>`, `fix/`, `docs/`, `hotfix/`. Une PR par lot,
  `Closes #n` pour chaque issue.
- Réglages GitHub (rulesets, merge commits permis, alertes Dependabot, auto-merge) : versionnés comme du code
  (`.github/rulesets/*.json` + `scripts/configure-repo.sh`, idempotent, lancé par le mainteneur ; une session cloud ne
  peut pas les changer). Suivi dans une issue `ci` tant que ce n'est pas fait.

## Versions et tags
- **Semver `MAJEUR.MINEUR.CORRECTIF`**, tag `vX.Y.Z` :
  - CORRECTIF : corrections sans changement visible de comportement attendu ;
  - MINEUR : fonctionnalités, changements visibles compatibles ;
  - MAJEUR : rupture (pour une app : format de sauvegarde non migrable, décision produit `à clarifier` préalable ;
    pour le cadre : changement qui demande une action dans les projets).
  Avant 1.0.0, un MINEUR peut casser : le CHANGELOG le dit.
- La version (`MARKETING_VERSION` des configurations du projet, ou `VERSION`) et l'entrée « Nouveautés » ne sont **pas**
  modifiées par les PR de lot. À l'intégration :
  1. une PR « Version : <branche> passe en X.Y.Z » pose la version sur la branche d'intégration ;
  2. l'entrée Nouveautés (ou `CHANGELOG.md`) est rédigée depuis les sections « Changelog » des PR mergées depuis la
     dernière version ;
  3. promotion (modèle A) ou merge (modèle B) ;
  4. tag annoté `vX.Y.Z` sur la branche de production **après** le merge, par l'opérateur (action conséquente) ;
  5. issue de suivi de la release (`release`) fermée, avec le lien du tag et du build publié.
- Numéro de build : incrémenté à chaque envoi TestFlight / App Store, indépendant de la version.

## Déploiement
TestFlight sur la branche candidate, App Store sur la branche de production : compte Apple Developer, puis clé d'API App
Store Connect (secrets GitHub) ou Xcode Cloud. Tant que ce n'est pas branché, une issue `release` le suit.
