# Conventions : commits, PR, commentaires, persistance

Sources : `AGENTS.md` §5, §8 de HFRnow (PR, merge, doublons, prises en charge, registre #620) ; pratique éprouvée
sur d'autres projets (conventions de commit, version et Nouveautés, compatibilité des sauvegardes).

## Langue
Français partout : interface, code (commentaires, noms métier), commits, issues, PR, docs. Un projet peut décider
autrement (projet ouvert à des contributeurs anglophones) : il l'écrit dans son `CLAUDE.md`, qui l'emporte.

## Branches
`<type>/<nom-court>` pour tout le monde, agent ou humain : `lot/` (un lot du plan, ex. `lot/082-reader-links`),
`fix/`, `feat/`, `chore/`, `docs/` ; `hotfix/<sujet>` depuis la branche de production (modèle A). Les types se
règlent dans `.harness/config.json` (`branch_types`). Le nom ne dit pas qui travaille : c'est la prise en charge
(`/claim`) et la ligne `Claim:` de la PR qui le disent. Une branche part de la branche d'intégration **à jour**.
Détail et promotions : [BRANCHING-RELEASE](BRANCHING-RELEASE.md).

## Commits
- Un commit **atomique par issue** (ou par étape logique d'une issue), message en français, au présent, dans le style
  des commits existants (`git log`) : `Onglet : ce qui change (#n)` ou `Zone : ce qui change`. Dire **pourquoi** quand ce
  n'est pas évident.
- Attribution en fin de message selon la consigne de la session, par exemple :
  ```
  Co-Authored-By: Claude <modèle> <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_…
  ```
- Jamais d'artefact généré, de `DerivedData`, `.build`, ni de fichier ignoré par `.gitignore`.
- Commits petits, **poussés souvent** sur la PR en brouillon (un plantage perd des minutes, pas des heures) ; rien de
  coûteux ne tourne sur un brouillon ([CI-BUDGET](CI-BUDGET.md) §2). Une fois la PR prête : un commit par cycle de
  revue.

## Pull requests
- Ouverte **en brouillon** dès le premier push (rien de coûteux ne tourne), passée « Ready for review » quand tout est
  fini, relu, compilé.
- **Titre** dans le style des PR précédentes : `Zone : résumé (#n)`, `Relecture 0.6.0 (3) : …`, `LOT-012 : …`.
- **Corps**, court, dans cet ordre (gabarit `templates/.github/pull_request_template.md`) :
  1. `LOT-XXX` pour une PR de lot ;
  2. `Closes #n`, **une ligne par issue** (`Refs #n` pour un travail partiel, en disant ce qui reste ; `Direct-PR: <raison>`
     pour un petit correctif sans issue, jamais pour un lot) ;
  3. `Claim: <id>` sur sa propre ligne, égal à la prise en charge active de l'issue (§Commentaires) ;
  4. le problème, la cause, ce qui change et pourquoi si large et pas plus ;
  5. les tests : noms, ce qu'ils vérifient, montrés en échec sans le changement ; commandes lancées ; points de
     vigilance / non testé (ex. app non compilée dans le conteneur Linux, à valider sur iPhone) ;
  6. section **`### Ledger`** seulement si le projet tient un registre (§Registre) ; sinon rien ;
  7. modèles auteur et relecteur ; la ligne de génération en dernier.
- On ne merge pas soi-même sauf politique contraire du projet (selon le projet : le mainteneur merge, ou l'auteur
  merge une PR prête et approuvée, sauf flux à risque).
- Pas de nouvelle PR tant qu'une des siennes a un commentaire de revue sans réponse.
- Avant d'ouvrir : chercher les doublons (issues et PR, ouvertes et fermées) et les PR qui touchent les mêmes fichiers.

## Registre (« ledger ») : jamais de conflit sur un fichier partagé
Brique facultative, pour les projets qui tiennent un fichier partagé de type journal (CHANGELOG, Nouveautés, rapport
d'écarts, tableau de suivi) que beaucoup de PR voudraient modifier en même temps.
- Une PR de travail **ne touche jamais** ces fichiers. Ses entrées vont dans une section `### Ledger` du **corps de la
  PR**, en blocs délimités dont le type d'entrée est le langage (ex. ` ```changelog `, ` ```gap-new `), et la PR porte
  le label `ledger`. Pas d'entrée : ni section, ni label.
- Après les merges, un **steward** (rôle d'entretien, [STEWARDS](STEWARDS.md)) lance le script du projet qui lit les
  PR mergées labellisées `ledger`, **replie** leurs entrées dans les fichiers et ouvre **une seule PR de docs**, qui
  ne touche que ces fichiers ; puis il remplace `ledger` par `ledger: done` sur chaque PR repliée.
- Cette PR se vérifie sans revue adversariale : **le script doit la reproduire** (sur sa base, la commande inscrite
  dans sa description, puis `git diff --exit-code <tête>`, ne montre aucune différence) ; elle se merge sur CI verte.
- Pas de verrou, pas de conflit, pas de push tardif pour rebaser un journal, pas de CI relancée pour une ligne.
- Le relecteur adversarial relit la section `### Ledger` comme le code. Une entrée mal formée est signalée et sautée
  par le steward (les autres se replient) : l'auteur corrige le corps de la PR, pas les fichiers.

Brancher la brique : le cadre fournit la convention et les contrôles de corps de PR (`pr-hygiene.yml`, entrée
`ledger-label`) ; le projet fournit son script de repli (format des blocs, fichiers cibles, ordre, idempotence),
déclaré dans `.harness/config.json` → `ledger` (`enabled`, `label`, `fold_command`), et un contrôle de CI qui refuse
qu'une PR hors branche du steward touche les fichiers du registre. Les labels `ledger` et `ledger: done` vont dans
`.github/labels.local.json`. Exemple complet (format des blocs, script, contrôle) : `tooling/docs/README.md` de HFRnow
(branche `dev-swift`, #620). Sans registre (`ledger.enabled` absent ou faux),
rien de tout cela ne s'applique.

## Commentaires GitHub
- **Prise en charge** : un commentaire dont la **première ligne** est `/claim <id>`, suivie du plan en 3 à 5 puces.
  `<id>` est l'identifiant de l'agent ([ORCHESTRATION](ORCHESTRATION.md) §7), ou `human/<login>` pour un humain ; il
  ne change pas jusqu'à la fin du travail. Les commentaires de l'issue se **rejouent dans l'ordre** : la première prise
  gagne, une autre `/claim` est refusée tant que la première tient ; `/release` (ou `/release <id>`) la rend. Seuls
  les commentaires des membres du dépôt (propriétaire, membres, collaborateurs) comptent : un contributeur sans droits
  demande à un membre de prendre pour lui. Un projet peut automatiser le rejeu (workflow qui pose et retire le label
  de statut, et répond à une prise refusée) ; sans automatisation, l'orchestrateur ou le mainteneur pose le label.
- Fin : fait, lien de la PR, ce qui reste, décisions prises, à valider sur l'appareil.
- Issue résolue sans `Closes` : « Résolu par #PR ». Merge sur une branche qui ne ferme pas les issues : « Fait dans
  #PR (mergée en `<sha>`) », puis vérifier qu'elle est fermée.
- Blocage : commentaire qui commence par `BLOQUÉ :` avec la question exacte ou la liste de ce qui manque.
- Décision attendue de l'opérateur, en session autonome : une ligne finissant par « Décision attendue (opérateur) »,
  puis passer au point suivant.
- Ne jamais `@mentionner` une personne ou un bot sans raison (cela envoie des e-mails) ; depuis le cloud, les mentions
  sont altérées (LESSONS L46).
- **Tout commentaire écrit par un agent se termine par un pied d'attribution qui nomme l'agent.** Claude Code :
  ```
  ---
  _Generated by [Claude Code](https://claude.ai/code)_
  ```

## Persistance : compatibilité ascendante
**Une sauvegarde écrite par une version publiée doit rester lisible par toutes les versions suivantes.**
- Nouveau champ → optionnel ou avec une valeur par défaut, décodé de façon tolérante (`decodeIfPresent`).
- Champ renommé ou supprimé → migration à la lecture (ancienne clé lue puis convertie, fonction dédiée du type
  `migrate(legacy:)`), testée avec une sauvegarde réelle de l'ancienne version (fichier de test figé).
- La version de format (`payloadVersion`) ne s'incrémente que pour un changement impossible à migrer, et cela demande
  une décision produit (issue `à clarifier`).
- Contrepartie acceptée : une version plus ancienne peut ne pas relire une sauvegarde plus récente (appareils non à jour
  qui partagent iCloud).
- SwiftData + CloudKit : jamais `@Attribute(.unique)`, propriétés optionnelles ou par défaut, relations optionnelles.

## Version et « Nouveautés »
Les PR de lot ne touchent **ni** la version (`MARKETING_VERSION` ou équivalent) **ni** le fichier des Nouveautés : ils
sont gérés à l'intégration (version posée sur la branche d'intégration par une PR dédiée, Nouveautés repliées depuis
les sections `### Ledger` des PR par le steward, ou rédigées depuis leurs descriptions sans registre), puis tag
`vX.Y.Z` après la promotion. Détail : [BRANCHING-RELEASE](BRANCHING-RELEASE.md).

## Docs
- Un fichier, un rôle ; `CLAUDE.md` (ou `AGENTS.md`) est l'entrée unique, tout le reste s'y rattache.
- Les `.md` portent le contexte durable et renvoient aux issues `#n` ; un TODO vit dans une issue.
- Les règles métier se sourcent (fichier de réglementation ou de protocole tenu à jour, faits datés).
- Une décision structurante = un ADR (`docs/adr/NNNN-titre.md`, gabarit [adr/TEMPLATE.md](adr/TEMPLATE.md)). Un ADR
  accepté ne se réécrit pas : il est remplacé par un autre.
- Les instructions personnelles d'un opérateur vont dans un `CLAUDE.local.md` non versionné, pas dans le dépôt.

## Secrets
Aucun secret dans le dépôt. Secrets de CI dans les secrets GitHub ; en local, dans des fichiers de configuration
ignorés par git ; clés d'API tierces injectées, jamais commitées. gitleaks et la protection au push bloquent : ne jamais
les contourner. Une faille se signale en privé (SECURITY.md), jamais dans une issue publique.
