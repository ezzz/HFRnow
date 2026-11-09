---
name: compliance-review
description: Lance, sur le diff courant, les relecteurs de conformité déclarés dans .harness/config.json — agents intégrés du cadre (gdpr, eu-ai-act, nis2, iso27001, soc2, tisax, pci, hds), agents propres à l'entreprise, ou specs du projet appliquées par le relecteur générique — dont le périmètre est touché, en parallèle, et consolide leurs verdicts pour la PR. À utiliser avant « Ready for review » dans un projet soumis à un référentiel.
argument-hint: "[ids séparés par des virgules, défaut : config] [base]"
---

# Revue de conformité

Référence : `.harness/docs/COMPLIANCE.md`.

1. **Plan** : `python3 .harness/scripts/compliance-plan.py --base origin/<base>` (base : argument, sinon
   `integration_branch`). Il résout `compliance` de `.harness/config.json` : agent **intégré**, agent **du projet**
   (l'entreprise a le sien), ou **spec** du projet appliquée par `compliance-reviewer`. Code 1 → montrer les erreurs à
   l'opérateur et s'arrêter (config à corriger). Restreindre aux ids de `$ARGUMENTS` s'il en nomme ; ajouter ceux
   qu'exige un label `conformité: <id>` des issues liées. Aucun → « aucun référentiel activé », s'arrêter.
2. **Périmètre** : `hors périmètre` (chemins et mots-clés configurés non touchés) → `HORS PÉRIMÈTRE` sans lancer ;
   `à évaluer` → lire la section « Quand intervenir » de l'agent ou de la spec et décider.
3. **Lancer en parallèle** les sous-agents concernés (`compliance-<id>`), nommés `<projet>.<orc>.conf-<id>.<cible>`
   (ORCHESTRATION §7 ; description `conf-<id> <cible> — conformité`) ; pour le mode `spec`, l'agent
   `compliance-reviewer` reçoit en tête de prompt `Spec : <file>`. Chacun reçoit : le diff, la tête (SHA), la spec
   liée, `ESSENTIEL.md`. Jamais les conclusions de l'auteur. Ils sont en lecture seule.
4. **Consolider** dans un tableau `Référentiel | Verdict | Constats ouverts | À confirmer par` et ajouter la section
   « Conformité » à la PR. Une faille de sécurité : aucun détail public.
5. Écarts Haute / Moyenne : corriger en un commit puis relancer seulement les agents concernés, ou ouvrir une issue
   `conformité: <id>` pour décision du responsable (risque accepté = ADR).
