---
name: intent
description: Transforme une demande (message, note, idée) en issue exploitable par un agent — user story, comportements d'erreur, définition de fini, critères d'acceptation testables, labels d'axe — selon le cadre agentic-harness. À utiliser avant tout travail qui n'a pas encore d'issue claire.
argument-hint: "<demande en une phrase>"
---

# Définir l'intention

Demande : $ARGUMENTS. Référence : `.harness/docs/METHODOLOGY.md` §2 (sinon `${CLAUDE_PLUGIN_ROOT}/docs/METHODOLOGY.md`).

1. **Doublons** d'abord : issues et PR, ouvertes et fermées. Une existe → la compléter plutôt qu'en créer une.
2. Rédiger, en français :
   - `### Résumé` : « En tant que <qui>, je veux que <X> fasse <Y>, pour <bénéfice> » ;
   - `### Comportements d'erreur` : chaque entrée invalide, panne externe, limite, avec le résultat attendu (message,
     code, état conservé) ; « aucun » doit être justifié ;
   - `### Critères d'acceptation` : Étant donné / Quand / Alors, chacun vérifiable par un test ;
   - `### Définition de fini` : tests (écrits d'abord, vus rouges), docs mises à jour, revue par un autre modèle,
     conformité si le périmètre l'exige, ce qui sera validé sur l'appareil ;
   - `### Hors périmètre` et `### Sources` (rien de deviné).
3. Labels : type, priorité, et niveau de modèle et taille si le projet a ces axes (préfixes : `.harness/config.json` →
   `labels`, METHODOLOGY §4) ; `à clarifier` + la question exacte si une décision produit manque.
4. **Montrer le texte à l'opérateur avant de créer l'issue** ; après accord, la créer et donner le lien.
