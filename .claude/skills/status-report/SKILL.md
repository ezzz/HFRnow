---
name: status-report
description: Produit un rapport d'état du projet lisible par un public non technique (TL;DR RAG, jalons, livré, prochaines étapes, blocages et décisions attendues, risques, coût) à partir du tableau de bord du flux et des issues. À utiliser pour un point hebdomadaire, un comité, ou quand l'opérateur demande « où en est-on ? ».
argument-hint: "[période, défaut : 7 jours]"
---

# Rapport d'état

Période : $ARGUMENTS (défaut 7 jours). Format : `.harness/docs/STEWARDS.md` §4.

1. **Données** : `python3 .harness/scripts/flow-metrics.py --repo <owner/nom> --json-out /tmp/flow.json` (ou l'issue
   « Tableau de bord » du jour) ; jalons GitHub (milestones, échéances) ; PR mergées et issues fermées sur la période ;
   issues `bloqué`, `à clarifier`, P1.
2. **Traduire** pour un non-technicien : ce que l'utilisateur gagne (entrées `### Ledger` ou descriptions des PR), pas les fichiers ;
   pas de SHA ni de jargon ; liens cliquables.
3. **Rédiger** dans le format de STEWARDS §4 : TL;DR avec 🟢/🟠/🔴 en première ligne ; un jalon = une ligne avec barre
   d'avancement et échéance ; chaque blocage formulé « qui doit décider quoi, avant quand ».
4. Vérifier chaque chiffre contre sa source avant de livrer (L18). Livrer dans la conversation ; le publier (issue,
   page) seulement si l'opérateur le demande.
