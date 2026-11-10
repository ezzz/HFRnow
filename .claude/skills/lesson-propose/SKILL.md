---
name: lesson-propose
description: Propose une nouvelle leçon (erreur récurrente, constat de revue d'un genre nouveau) au tableau LESSONS.md — dans le projet, ou au cadre agentic-harness par une issue « Leçon » si elle vaut ailleurs. À utiliser après un cycle de revue, un incident ou une erreur qu'on ne veut pas refaire.
argument-hint: "<constat ou lien de PR / commentaire>"
---

# Proposer une leçon

Matière : $ARGUMENTS. Référence : `.harness/docs/LESSONS.md` (en-tête : portée, sources, numérotation stable).

1. **Déjà listée ?** Chercher dans le tableau du cadre **et** celui du projet (mots-clés, synonymes). Déjà là → pas de
   nouvelle ligne : c'est l'auto-relecture qui l'a manquée ; proposer de resserrer `/lessons-check` ou la leçon.
2. **Rédiger** une ligne : portée (`général`, `docs`, `ci`, `linux-cloud`, `swift`, `ios`…), la leçon en une phrase
   impérative et vérifiable (ce qu'il faut faire, pas l'anecdote), la **source** (PR, commentaire, commit, à un SHA).
3. **Où ?**
   - propre au domaine du projet → tableau du projet, dans le commit qui corrige ;
   - valable ailleurs → issue sur `francoisgn/agentic-harness` avec le formulaire « Leçon » (labels `leçon`, `docs`) :
     titre `Leçon : <résumé>`, corps = portée, leçon, source, contre-exemple, comment la vérifier en revue. Depuis une
     session cloud, le dépôt du cadre doit être attaché (`add_repo`).
4. Montrer la proposition à l'opérateur avant de créer l'issue (elle touche un autre dépôt). Le numéro `L..` est
   attribué par la PR du cadre qui l'intègre, jamais par le projet.
