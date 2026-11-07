# 0001 — Distribuer le cadre : vendorisation versionnée + plugin + workflows réutilisables

**Statut :** Accepté — 2026-11-07 (François)

## Contexte
- Les règles de travail agentique sont nées dans deux dépôts (HFRnow, ios-app_credit-immo) et y divergent. On veut une
  source unique, versionnée, que chaque projet récupère et met à jour, sans perdre ce qui lui est propre.
- La plupart des sessions sont des **sessions cloud** (claude.ai/code). D'après la documentation Claude Code
  (« Install plugins », onglet *Cloud session*, consultée le 07/11/2026), une session cloud **ne charge pas** les plugins
  installés sur la machine de l'utilisateur ni ceux qu'active le `.claude/settings.json` du dépôt ; seuls les réglages
  gérés par serveur (offre Team/Enterprise) y installent des plugins. En revanche, une session cloud lit bien le
  `CLAUDE.md`, ses imports `@chemin` situés **dans** le dépôt, `.claude/skills/` et les hooks de `.claude/settings.json`.
- Un import `@chemin` qui sort du dépôt (`~/…`, chemin absolu) est « externe » : une fenêtre d'approbation s'affiche,
  et il n'existe pas en cloud.
- Une session cloud n'a accès GitHub qu'aux dépôts qui lui sont attachés ; un workflow Actions n'accède à un autre dépôt
  privé qu'avec un jeton dédié.
- Les fichiers sous `.github/workflows/` ne peuvent pas être poussés avec le `GITHUB_TOKEN` d'Actions.
- HFRnow vit sur `ezzz/HFRnow` (pas un dépôt de François) et ses docs sont en anglais.

## Options
1. **Sous-module git** : versionné, mais lourd pour les agents (init, détaché), invisible en cloud si non initialisé,
   et un import `@` vers un sous-module non cloné échoue en silence.
2. **Plugin Claude Code seul** (marketplace) : mise à jour propre, mais rien en session cloud ; aucun contrôle GitHub.
3. **Copie manuelle** : divergence garantie.
4. **Vendorisation versionnée par script + plugin + workflows réutilisables** (retenu).

## Décision
Trois canaux complémentaires, une seule source (ce dépôt, tags `vX.Y.Z`) :
1. **Vendorisation** (canal principal, marche partout, cloud compris) : `scripts/harness-sync.sh` copie à une version
   donnée les docs dans `.harness/docs/`, la taxonomie dans `.harness/labels.json`, les skills dans `.claude/skills/`,
   les hooks dans `.harness/hooks/` (déclarés par fusion dans `.claude/settings.json`), et gère un **bloc balisé**
   `<!-- harness:begin cadre -->…<!-- harness:end cadre -->` dans `CLAUDE.md` et `AGENTS.md`, qui importe
   `@.harness/docs/ESSENTIEL.md`. Tout ce qui est hors des balises appartient au projet et n'est jamais touché. Version
   et empreintes dans `.harness/VERSION` et `.harness/lock` : une modification locale d'un fichier du cadre est détectée
   et jamais écrasée sans `--force`.
2. **Plugin** `harness@agentic-harness` (ce dépôt est une marketplace) : les mêmes skills et hooks pour les sessions
   **locales** (Mac, terminal) et les dépôts qui n'ont pas encore adopté le cadre. Si un dépôt a les deux, la copie
   vendorisée fait foi (le hook de session du plugin se tait).
3. **Workflows réutilisables** (`on: workflow_call`) appelés par un `harness.yml` fin du projet : synchro des labels
   (cadre + `labels.local.json`), hygiène des issues, hygiène des PR (flux de branches, `Closes`, Changelog), socle docs
   et sécurité. Ils lisent les fichiers **vendorisés** du projet : seul l'appel `uses:` touche ce dépôt. Un workflow
   `harness-sync.yml` du projet propose chaque semaine une PR en brouillon vers le dernier tag.

## Conséquences
- 🟢 Fonctionne en cloud sans réglage ; versions explicites et relues par PR ; le projet garde la main (bloc balisé,
  fichiers `seed`, `labels.local.json`, `.harness/config.json`) ; pas de doublon de règles à maintenir à la main.
- 🟠 Fichiers dupliqués dans chaque dépôt (quelques dizaines de Ko) : c'est le prix du fonctionnement en cloud.
- 🟠 **Accès si ce dépôt est privé** :
  - Actions : les dépôts consommateurs doivent appartenir à `francoisgn` et ce dépôt doit autoriser l'accès (Settings →
    Actions → General → Access : « Accessible from repositories owned by the user »). Un dépôt d'un autre propriétaire
    (ex. `ezzz/HFRnow`) ou un dépôt **public** ne peut pas appeler un workflow réutilisable d'un dépôt privé : il garde
    des copies locales des workflows, ou ce dépôt devient public ;
  - `harness-sync.yml` : secret `HARNESS_TOKEN` (jeton fine-grained, lecture du contenu de ce dépôt) ; sans lui, seul un
    cadre public se lit ;
  - session cloud : attacher ce dépôt à la session (`add_repo`) pour lancer `harness-sync.sh --ref` ;
  - plugin : `git` de la machine doit pouvoir cloner ce dépôt sans invite (`gh auth login` + `gh auth setup-git`, ou clé
    SSH chargée) ; la mise à jour automatique en arrière-plan échoue en silence sinon.
  Rendre ce dépôt public lève toutes ces limites ; il ne contient aucun secret ni rien de propre à un produit.
- 🟠 Le `GITHUB_TOKEN` ne pousse pas `.github/workflows/` : la PR de synchro saute ces fichiers (et le dit) sauf jeton
  avec « Workflows: write » et variable `HARNESS_SYNC_WORKFLOWS=true`.
- 🟠 Un projet en anglais (HFRnow) : le bloc et les docs vendorisés sont en français ; HFRnow peut n'adopter que les
  workflows et la taxonomie (avec `apply-aliases` quand ses docs sont prêts), ou attendre une édition anglaise (issue à
  ouvrir si besoin).
- Les `version` du plugin (`plugin.json`) et du cadre (`VERSION`) avancent ensemble : sans changement de `version`, les
  utilisateurs du plugin ne reçoivent pas les nouveaux commits. La CI du cadre vérifie l'égalité.
