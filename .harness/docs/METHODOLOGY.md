# Méthode : le travail piloté par les issues

Comment une idée devient une PR mergée, quel que soit le projet. Sources : `AGENTS.md` §5–§9 et `docs/LOTS.md` de
HFRnow (boucle de lot, plan, prises en charge, définition de « fini ») ; pratique éprouvée sur d'autres projets
(workflow piloté par les issues).

## 1. Où vit quoi : l'état partagé

Les sessions (cloud, Mac, humains, autres agents) ne se coordonnent **que** par de l'état visible. Le bloc-notes, la
mémoire d'un agent et `/tmp` ne comptent pas.

| Où | Rôle |
|---|---|
| **Issues** | Le **suivi** : une issue par lot, bug, point de retour, tâche ; prise en charge, labels de statut, blocages |
| **PR** | Le travail en cours et en revue ; le fil de la PR est la trace de ce qui a été fait et pourquoi |
| **`docs/LOTS.md`** (si le projet découpe en lots) | Le **plan** : périmètre, dépendances, modèle, priorité de chaque lot, lié à son issue. Jamais modifié pour un avancement |
| **`docs/lots/LOT-XXX-*.md`** | La **spec** d'un lot (gabarit : `templates/docs/lots/TEMPLATE.md`) |
| **`docs/adr/`** | Les décisions. Une décision hors ADR n'est pas une décision |
| **`.md` du projet** | Le contexte durable ; ils renvoient aux issues (`#n`) au lieu de porter des TODO |

## 2. La boucle (une issue, une PR)

1. **Issue** : titre clair, puis l'**intention** (§2 bis) : user story, comportements d'erreur, critères
   d'acceptation, définition de fini, sources. Labels obligatoires (§4). Skill : `/intent`.
   Chercher un doublon avant de créer (titres, corps, synonymes, issues et PR ouvertes **et** fermées) ; la plus
   ancienne est celle qu'on garde.
2. **Prête ?** Toutes ses dépendances sont faites, ses entrées existent (données, captures, accès), aucune décision
   produit ne manque (sinon `à clarifier`, on ne code pas), pas `hôte: mac` si on est en cloud.
3. **Prise en charge** avant d'écrire du code : un commentaire dont la première ligne est `/claim <id>` (identifiant de
   l'agent, ou `human/<login>`), suivi du plan en 3 à 5 puces ([CONVENTIONS](CONVENTIONS.md) §Commentaires). Les
   commentaires se rejouent dans l'ordre : la première prise gagne, seuls ceux des membres du dépôt comptent (label
   `pris en charge` posé à la main ou par un workflow, si le projet le suit). On s'arrête avant la fin → dire où on en
   est sur la PR et l'issue, puis commenter `/release`. Une prise en charge qui semble abandonnée depuis 24 h :
   demander au mainteneur, ne jamais la reprendre d'office.
4. **Spec** : l'issue suffit pour un bug, une tâche, une doc ; un lot a sa spec `docs/lots/LOT-XXX-*.md`.
5. **Réalisation en TDD** (§2 ter) : branche `<type>/<nom-court>` depuis la branche d'intégration à jour (`git fetch`
   d'abord) ; commits atomiques par issue, poussés souvent sur une PR en brouillon ; tests écrits d'abord et vus rouges ; pas de refactor opportuniste hors périmètre (si un point est
   ambigu : l'option la plus simple, notée dans le commentaire de fin).
6. **Vérification** : tests et lint en local ; auto-relecture contre [LESSONS](LESSONS.md) ; revue adversariale par
   un autre modèle ([ORCHESTRATION](ORCHESTRATION.md) §3) ; build Mac si l'app est touchée ([MAC-HANDOFF](MAC-HANDOFF.md)).
7. **PR** en brouillon dès le premier push, corps selon [CONVENTIONS](CONVENTIONS.md) §PR (issue, `Claim:`, lot,
   problème / cause / changement / tests, `### Ledger` si le projet tient un registre). « Ready for review » quand
   tout est fini : c'est là que la CI coûteuse tourne ([CI-BUDGET](CI-BUDGET.md) §2) ; ensuite un commit par cycle.
   Cycles de revue de bots : [REVIEW-ROUNDS](REVIEW-ROUNDS.md).
8. **Fin** : commentaire sur chaque issue (fait, lien de la PR, ce qui reste, décisions prises, à valider sur
   l'appareil). Issue résolue sans `Closes` ou fermée à la main → commentaire « Résolu par #PR ». Fermer une issue
   retire ses labels de statut.

**Fini** = définition de fini de l'issue respectée, code au bon endroit, tests écrits d'abord et verts en CI, lint et sécurité verts, docs à jour dans le même commit, relu par un
autre modèle ou un humain, auto-relecture faite, `Closes #n` et issue fermée après le merge (vérifiée fermée).

## 2 bis. L'intention : ce qu'un agent doit savoir avant d'écrire une ligne

Un agent ne devine pas une intention : il la lit. Toute issue de travail porte :

| Section | Contenu | Exemple |
|---|---|---|
| `### Résumé` | « En tant que <qui>, je veux que <X> fasse <Y>, pour <bénéfice> » | En tant que lecteur, je veux que le fil se recharge seul toutes les 2 min, pour suivre une discussion sans geste |
| `### Comportements d'erreur` | Chaque entrée invalide, panne externe, limite → résultat attendu | Réseau coupé : bandeau discret, dernier contenu conservé, nouvel essai au prochain intervalle |
| `### Critères d'acceptation` | Étant donné / Quand / Alors, un test par critère | Étant donné un fil ouvert, quand 2 min passent, alors une seule requête part (source : …) |
| `### Définition de fini` | Ce qui doit être vrai pour fermer | Tests verts en CI, doc mise à jour, revue adversariale APPROUVÉ, validé sur iPhone |
| `### Hors périmètre`, `### Sources` | Ce qu'on ne fait pas ; d'où viennent les faits | — |

Il manque une de ces sections et elle demande une décision produit → `à clarifier` avec la question exacte ; on ne
code pas. Le steward d'issues ([STEWARDS](STEWARDS.md) §1) veille à ce que la file soit prête.

## 2 ter. TDD : le test d'abord, rouge, puis vert

1. **Rouge** : traduire chaque critère d'acceptation et chaque comportement d'erreur en test, par le vrai point
   d'entrée ; le lancer et **le voir échouer pour la bonne raison** (pas une erreur de compilation ou d'import).
2. **Vert** : le code minimal qui fait passer ; aucun test n'est affaibli pour passer.
3. **Refactor** : nettoyer avec les tests verts, sans changer le comportement.
4. Un correctif de bug commence par le test qui reproduit le bug. Un constat de revue corrigé a son test (REVIEW-ROUNDS
   §4). La PR dit, dans « Vérifié », quels tests ont été vus rouges (LESSONS L01).
5. Ce qui ne se teste pas automatiquement (rendu, appareil) se dit dans « Points de vigilance », avec la vérification
   manuelle prévue.

## 3. Retours de test : issue parapluie + une issue par point

Un lot de retours (session de test sur iPhone, relecture d'un proche) devient :
- **une issue parapluie** `feedback` + priorité, avec un tableau de suivi :

  | Réf | Point | Lot | Issue | PR |
  |---|---|---|---|---|
  | Lec3 | Fil : bouton de rechargement trop petit | lot-ux-1 | #212 | #230 |

- **une issue par point**, titre `[Réf] Zone : sujet` (ex. `[Lec3] Fil : bouton…`), rattachée au parapluie
  (sous-issue), avec ses labels complets ;
- le parapluie se met à jour à chaque PR (colonne PR) et se ferme quand tous ses points le sont.

Skill : `/feedback-triage`.

## 4. Labels

Taxonomie canonique : `templates/.github/labels.json` (vendorisée en `.harness/labels.json`) ; le projet ajoute les
siens dans `.github/labels.local.json` ; le workflow réutilisable `labels-sync.yml` synchronise les deux.

| Axe | Labels | Obligatoire |
|---|---|---|
| Type | `bug`, `ux`, `feature`, `docs`, `ci`, `sécurité`, `release` (+ types métier du projet) | oui |
| Priorité | `P1 🔴` bloquant ou faux · `P2 🟠` prochaine itération · `P3 🟢` plus tard | oui |
| Modèle | `modèle: haiku` · `sonnet` · `opus` · `fable` ([ORCHESTRATION](ORCHESTRATION.md) §2) | oui, sauf réglage |
| Taille | `taille: S` < 1 h, un fichier · `M` quelques fichiers · `L` à découper | oui, sauf réglage |
| Statut | `à clarifier` (décision produit) · `bloqué` (prérequis externe) · `pris en charge` (suit le `/claim`) | selon le cas |
| Conformité | `conformité: <id>` force la revue du référentiel ([COMPLIANCE](COMPLIANCE.md)) · `revue: aucune` saute le service de revue | selon le cas |
| Suivi | `leçon` (proposition au tableau des leçons) · `tableau de bord` (issue tenue par `flow-report.yml`) | selon le cas |
| Hôte | `hôte: mac` : demande le Mac ; les sessions cloud n'y touchent pas | selon le cas |
| Projet | ex. `onglet: …`, `area: …` (dans `labels.local.json`) | selon le projet |

Les parapluies portent seulement `feedback` + priorité. Ajouter un label au fichier **avant** de l'utiliser.
`issue-hygiene.yml` signale (un seul commentaire, mis à jour) l'axe manquant.

**Axes de modèle et de taille réglables** : un projet qui a déjà sa taxonomie (ex. `difficulty: easy|medium`, niveau de
modèle déduit d'un tableau de routage) le dit dans `.harness/config.json` :
```json
{ "labels": { "model_prefixes": ["modèle:"], "size_prefixes": ["taille:", "difficulty:"] } }
```
Défauts : `["modèle:"]` et `["taille:"]`. Liste vide : le projet n'a pas cet axe. Une issue sans label de l'axe ne
bloque pas le travail : l'agent déduit le niveau et la taille du texte de l'issue et du tableau de routage du projet
(son `AGENTS.md`, ou [ORCHESTRATION](ORCHESTRATION.md) §2), le dit dans sa prise en charge, et continue ; il propose le
label manquant sans l'attendre. L'entrée `required-axes` de `issue-hygiene.yml` se règle de même.

**Ordre de prise** : `sécurité` d'abord, puis `P1` → `P3` ; parmi les lots, le chemin critique et ceux qui en
débloquent d'autres ; à priorité égale, choisir une issue dont le label `modèle:` correspond au modèle de la session.

## 5. Lots

Un **lot** est l'unité de travail d'une session : une PR, relue d'un coup, à périmètre net. Taille L = à découper.
- Le plan (`docs/LOTS.md`) liste chaque lot : périmètre, module, taille, modèle auteur → relecteur, dépendances,
  priorité, issue. Marquer le chemin critique (★). Il ne change que si le plan change (nouveau lot, dépendance,
  routage), jamais pour un avancement.
- Les dépendances respectent le sens des modules (un lot de la couche basse ne dépend pas d'une couche haute) ; un
  script de CI peut le vérifier (HFRnow : `scripts/check-lot-deps.py`).
- Une branche de lot regroupe les issues d'un même lot : `lot/<nom-court>` ; une PR par lot avec un `Closes #n` par issue.
- **Débloquer en fermant** : qui ferme un lot liste les lots qui en dépendaient, vérifie qu'aucun autre prérequis ne
  les bloque (capture, ADR, décision), retire `bloqué` et commente « Débloqué par #PR ». Sinon dire ce qui bloque encore.
- Lots parallèles qui écrivent la même section d'un doc partagé : créer d'abord le titre commun, chaque lot n'ajoute
  que sa sous-section (LESSONS L41).

## 6. Travail découvert en route

TODO, décision en attente, dette, bug vu dans un autre lot : **une issue labellisée**, jamais seulement une ligne dans un
`.md`, ni seulement un message de session. Un problème dans le lot d'un autre se signale sur son issue ou sa PR.

## 7. Contributions extérieures

Un contributeur externe (humain ou agent) suit la même boucle. Ce qui marche (HFRnow, `EXTERNAL-AGENTS.md`) :
une file `external: ready` d'issues autonomes ; la prise en charge demandée par commentaire quand il n'a pas les droits ;
une limite de PR ouvertes par contributeur ; un code UI arrivé sans spec ni tests se **porte** par lots, il ne se merge
pas tel quel (LESSONS L44). Le modèle des droits et du merge relève d'un ADR du projet.
