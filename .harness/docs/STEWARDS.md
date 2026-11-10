# Stewards : rôles d'entretien et rapport d'état

Un **steward** est un agent jetable, spécialisé, qui entretient un bien commun du projet pour que les agents de lot
travaillent vite : la file d'issues, la documentation, le flux. Il est lancé par l'orchestrateur ou par un workflow
planifié, fait une passe, rend compte, et s'arrête ([FINOPS](FINOPS.md) §1). Définitions vendorisées dans
`.claude/agents/` ; appel : « utilise le sous-agent `issue-steward` sur … ».

| Rôle | Agent | Niveau | Quand | Peut écrire |
|---|---|---|---|---|
| Orchestrateur (SPOC) | session principale | solide | toujours | issues, commentaires, sessions enfants |
| Issue steward | `issue-steward` | rapide | nouvelle issue, chaque jour, avant une vague de lots | labels, commentaires de tri ; **propose** fusions et fermetures |
| Doc steward | `doc-steward` | solide | après un merge qui touche le comportement, chaque semaine | une PR de docs (brouillon) |
| Flow monitor | `flow-monitor` (lecture seule) ; `flow-report.yml` écrit l'issue | rapide | chaque jour | rien (le workflow tient l'issue « Tableau de bord ») |
| Relecteur adversarial | `adversarial-reviewer` | ≥ auteur, autre modèle | avant « Ready for review » | rien (lecture seule) |
| Service de revue | `ai-review.yml` | solide / frontière | chaque PR prête | une revue de PR ([REVIEW-SERVICE](REVIEW-SERVICE.md)) |
| Relecteurs conformité | `compliance-*` | frontière | diff dans leur périmètre | rien ([COMPLIANCE](COMPLIANCE.md)) |

## 1. Issue steward : une file prête à être prise

Objectif : qu'un agent de lot puisse prendre une issue **sans poser de question**.
- Labels d'axe complets (type, priorité, et modèle / taille si le projet a ces axes : METHODOLOGY §4) ; `à clarifier` avec la question exacte quand une décision
  manque ; `bloqué` avec le prérequis ; `hôte: mac` si besoin.
- Intention exploitable : user story, comportements d'erreur, définition de fini ([METHODOLOGY](METHODOLOGY.md) §2) ;
  sinon un commentaire qui liste ce qui manque.
- Doublons : propose la fusion (la plus ancienne gagne), ne ferme jamais seul ce qu'un autre a écrit.
- Routage : jalon, lot, dépendances (`Dépend de #n`), sous-issues du parapluie ; taille L → proposition de découpe.
- Prises en charge abandonnées (`/claim` actif sans activité depuis 24 h) : les signale à l'orchestrateur, ne les reprend pas.

## 2. Doc steward : des docs toujours vraies et lisibles

- Compare les docs au code mergé : comportement décrit = comportement livré (LESSONS L08), liens et ancres vivants,
  tableaux non cassés (L07). Ce qui a dérivé : une PR de docs, une issue si le code est en cause.
- Lisible par un humain : un fichier un rôle (L10), titres stables, TL;DR en tête des docs longs, **un schéma** quand
  un flux ou une architecture se décrit mieux en image (Mermaid dans le Markdown : rendu par GitHub, versionné, relu
  comme du code).
- Tient à jour les vues d'ensemble : README (contenu, état), plan des lots, index des ADR.
- Si le projet tient un registre ([CONVENTIONS](CONVENTIONS.md) §Registre) : après un lot de merges, lance la commande
  de repli du projet (`.harness/config.json` → `ledger.fold_command`), ouvre **une** PR de docs qui ne touche que les
  fichiers du registre et que le script reproduit, signale les entrées mal formées sur leur PR, puis marque les PR
  repliées (`ledger: done`).

## 3. Flow monitor : voir les dérives tôt

Lit le tableau de bord ([FINOPS](FINOPS.md) §4), et pour chaque 🔴 ou 🟠 nomme l'action et son responsable. Il ne
corrige rien lui-même : il alerte l'orchestrateur, qui arrête une boucle, relance une PR en panne ou remonte un goulot.

## 4. Rapport d'état pour un public non technique

Produit par l'orchestrateur (skill `/status-report`), à partir du tableau de bord et des issues. Pas de jargon, pas
de SHA, des liens cliquables.

```text
# État du projet <nom> — semaine du <date>

TL;DR : 🟢|🟠|🔴 <une phrase : où on en est, ce qui compte>

| Jalon | Avancement | Échéance | État |
|---|---|---|---|
| Jalon 1 : <nom lisible> | ███████░░░ 70 % (7/10) | <date> | 🟢 dans les temps |

Livré cette semaine : <3 à 5 puces orientées utilisateur, avec liens>
Prochaine étape : <3 puces>
Blocages et décisions attendues : <qui doit décider quoi, avant quand>
Risques : 🔴/🟠 <risque> → <mesure>
Qualité : <x> % de PR avec constat en revue (agents <a> %, humains <h> %), <n> commits de correction en moyenne
Coût : <minutes CI, tendance jetons> (FINOPS)
```

Catégories reprises des labels (type, priorité, zone du projet), des jalons GitHub (milestones), des assignés et des
lots ; un goulot est toujours formulé comme « qui doit faire quoi ».
