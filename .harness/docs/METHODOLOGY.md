# Méthode : le travail piloté par les issues

Comment une idée devient une PR mergée, quel que soit le projet. Sources : `CLAUDE.md` de ios-app_credit-immo
(workflow piloté par les issues, schéma `docs/diagrams/workflow.svg`), `AGENTS.md` §5–§9 et `docs/LOTS.md` de HFRnow
(boucle de lot, plan, prises en charge, définition de « fini »).

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

1. **Issue** : titre clair, section `### Résumé` en tête (user story « En tant que …, je veux …, pour … » ou synthèse
   en deux lignes), puis périmètre, sources, critères d'acceptation. Labels obligatoires (§4).
   Chercher un doublon avant de créer (titres, corps, synonymes, issues et PR ouvertes **et** fermées) ; la plus
   ancienne est celle qu'on garde.
2. **Prête ?** Toutes ses dépendances sont faites, ses entrées existent (données, captures, accès), aucune décision
   produit ne manque (sinon `à clarifier`, on ne code pas), pas `hôte: mac` si on est en cloud.
3. **Prise en charge** avant d'écrire du code : commentaire « Pris en charge — branche `claude/<lot>` » + plan en 3 à 5
   puces (label `pris en charge` si le projet le suit). Première prise en charge gagne. On s'arrête avant la fin →
   dire où on en est sur la PR et l'issue, puis rendre la main (« Rendue : … »). Une prise en charge qui semble
   abandonnée depuis 24 h : demander au mainteneur, ne jamais la reprendre d'office.
4. **Spec** : l'issue suffit pour un bug, une tâche, une doc ; un lot a sa spec `docs/lots/LOT-XXX-*.md`.
5. **Réalisation** : branche depuis la branche d'intégration à jour (`git fetch` d'abord) ; commits atomiques par
   issue ; tests qui échouent sans le changement ; pas de refactor opportuniste hors périmètre (si un point est
   ambigu : l'option la plus simple, notée dans le commentaire de fin).
6. **Vérification** : tests et lint en local ; auto-relecture contre [LESSONS](LESSONS.md) ; revue adversariale par
   un autre modèle ([ORCHESTRATION](ORCHESTRATION.md) §3) ; build Mac si l'app est touchée ([MAC-HANDOFF](MAC-HANDOFF.md)).
7. **PR** en brouillon, **un seul push** ([CONVENTIONS](CONVENTIONS.md) §PR). « Ready for review » quand tout est fini.
   Cycles de revue de bots : [REVIEW-ROUNDS](REVIEW-ROUNDS.md).
8. **Fin** : commentaire sur chaque issue (fait, lien de la PR, ce qui reste, décisions prises, à valider sur
   l'appareil). Issue résolue sans `Closes` ou fermée à la main → commentaire « Résolu par #PR ». Fermer une issue
   retire ses labels de statut.

**Fini** = code au bon endroit, tests verts en CI, lint et sécurité verts, docs à jour dans le même commit, relu par un
autre modèle ou un humain, auto-relecture faite, `Closes #n` et issue fermée après le merge (vérifiée fermée).

## 3. Retours de test : issue parapluie + une issue par point

Un lot de retours (session de test sur iPhone, relecture d'un proche) devient :
- **une issue parapluie** `feedback` + priorité, avec un tableau de suivi :

  | Réf | Point | Lot | Issue | PR |
  |---|---|---|---|---|
  | Sim3 | Capacité : fusion des deux jauges | lot-ux-1 | #212 | #230 |

- **une issue par point**, titre `[Réf] Onglet : sujet` (ex. `[Sim3] Capacité : fusion…`), rattachée au parapluie
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
| Modèle | `modèle: haiku` · `sonnet` · `opus` · `fable` ([ORCHESTRATION](ORCHESTRATION.md) §2) | oui |
| Taille | `taille: S` < 1 h, un fichier · `M` quelques fichiers · `L` à découper | oui |
| Statut | `à clarifier` (décision produit) · `bloqué` (prérequis externe) · `pris en charge` | selon le cas |
| Hôte | `hôte: mac` : demande le Mac ; les sessions cloud n'y touchent pas | selon le cas |
| Projet | ex. `onglet: …`, `area: …` (dans `labels.local.json`) | selon le projet |

Les parapluies portent seulement `feedback` + priorité. Ajouter un label au fichier **avant** de l'utiliser.
`issue-hygiene.yml` signale (un seul commentaire, mis à jour) l'axe manquant.

**Ordre de prise** : `sécurité` d'abord, puis `P1` → `P3` ; parmi les lots, le chemin critique et ceux qui en
débloquent d'autres ; à priorité égale, choisir une issue dont le label `modèle:` correspond au modèle de la session.

## 5. Lots

Un **lot** est l'unité de travail d'une session : une PR, relue d'un coup, à périmètre net. Taille L = à découper.
- Le plan (`docs/LOTS.md`) liste chaque lot : périmètre, module, taille, modèle auteur → relecteur, dépendances,
  priorité, issue. Marquer le chemin critique (★). Il ne change que si le plan change (nouveau lot, dépendance,
  routage), jamais pour un avancement.
- Les dépendances respectent le sens des modules (un lot de la couche basse ne dépend pas d'une couche haute) ; un
  script de CI peut le vérifier (HFRnow : `scripts/check-lot-deps.py`).
- Une branche de lot regroupe les issues d'un même lot : `claude/<lot>` ; une PR par lot avec un `Closes #n` par issue.
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
