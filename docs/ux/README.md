# Démarche UX et questionnaire utilisateurs : archive du cadrage

## Statut : archive

Ce dossier archive le travail de cadrage UX du PO, arrêté au 7 novembre 2026. Il trace la démarche, l'analyse et les arbitrages de cadrage. **Ce ne sont pas des spécifications à implémenter**, et rien ici ne modifie le plan du portage (`docs/LOTS.md`, `docs/FEATURES.md`).

La suite se pilote dans les issues, dont le périmètre fait foi en cas d'écart avec ces documents :

| Sujet | Où |
|---|---|
| Questionnaire utilisateurs | Issue parapluie #628, un lot par issue de #629 à #635 |
| Évolutions produit issues de la revue d'équipe | #624 à #627, et les commentaires sur les issues M5 concernées |

Les documents sont en français, comme le questionnaire.

## Contenu

| Document | Rôle |
|---|---|
| [tri-m5-decisions.md](tri-m5-decisions.md) | Tri Oui / Peut-être / Non des 39 propositions par le PO, et première version du contenu du questionnaire (§4), entrée de #629 |
| [plan-preparation-questionnaire.md](plan-preparation-questionnaire.md) | Décisions pratiques du PO, lots de préparation, calendrier |
| [cadrage-agents-questionnaire.md](cadrage-agents-questionnaire.md) | Briefs par lot et routage des modèles, repris dans #629 à #635 |
| [retours-equipe-github.md](retours-equipe-github.md) | Retours de l'équipe et issues #624 à #627 |
| [audit-m5-ux-ui.md](audit-m5-ux-ui.md) | Audit du jalon M5 côté UX/UI |
| [cadrage-questionnaire-ux.md](cadrage-questionnaire-ux.md), [cadrage-points-ux.md](cadrage-points-ux.md) | Premiers cadrages, remplacés |

## Où vont les livrables du questionnaire

- Contenu, mention sur les données, spécification du formulaire, visuels : `docs/ux/questionnaire/`.
- Code du formulaire : `tooling/ux-survey/`.

## Arbitrages de cadrage à retenir

- Le lecteur garde la WebView pour le moment ; le rendu natif sera une décision technique ultérieure.
- Aucune proposition classée Non par le PO n'apparaît dans le questionnaire.
