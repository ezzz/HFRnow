# Cycles de revue (bots, CodeQL, humains)

Source : `docs/agents/REVIEW-ROUNDS.md` de HFRnow, traduit et généralisé. Skill : `/review-round`.

Chaque cycle coûte un passage de CI, une nouvelle revue et des jetons. Le faire **une fois, complètement**.

1. **Tout lire d'abord** : commentaires en ligne, « Outside diff range », détails, bloc « Prompt for AI agents », chaque
   fil ouvert de la PR.
2. **Un constat est une affirmation à vérifier, pas un ordre.** Suivre un vrai chemin (entrée ou appelant → défaillance).
   Réel et correctif proportionné → corriger. Tiré par les cheveux ou correctif plus coûteux que le gain → répondre dans
   son fil avec le chemin suivi et pourquoi non, et le signaler au mainteneur.
   **Un constat de sécurité reste ouvert jusqu'à la décision du mainteneur.**
3. **Corriger la classe, pas l'instance** : lister les cas voisins (autres points d'entrée, autres analyseurs ou
   requêtes du même motif, ordre inverse, autres limites) et les corriger tous, un test par cas.
4. **Chaque test est montré en échec sans le correctif** (annuler le cœur du changement, voir rouge) et passe par le vrai
   point d'entrée. Un run filtré doit annoncer des tests exécutés (LESSONS L01).
5. **Contre-vérification avant de pousser** : un agent séparé reçoit le constat, le diff et LESSONS.md, **pas** la
   conclusion de l'auteur, avec la consigne de trouver ce que le correctif rate ou casse. Intégrer ses constats.
6. **Un commit + un push par cycle**, tous les constats traités. Jamais un push par constat.
7. **Puis une réponse par fil** (commit correctif, ou pourquoi non), dans la même unité de travail que le push ; un push
   seul n'est pas une réponse. Constats hors diff : un commentaire de PR adressé au bot. Résoudre chaque fil traité.
8. **Constats facultatifs** (détail, suggestion) : jamais de push pour eux seuls. Réponse d'une ligne ; les intégrer au
   prochain push qui touche ces fichiers.
9. **Après le cycle** : comparer les constats à [LESSONS](LESSONS.md). Déjà listé = l'auto-relecture l'a manqué,
   resserrer cette étape. Nouveau genre = nouvelle ligne.

Un bot de revue peut sauter une revue (« Review skipped ») ou se mettre en pause sur une branche : après le push,
vérifier qu'il a relu la **nouvelle tête** ; sinon demander `@coderabbitai review` (depuis une session cloud, les
`@mentions` sont altérées : l'opérateur le poste). Le cycle n'est complet que quand le bot a relu la tête poussée.

**Bruit de CI ou vraie panne** : un contrôle qui échoue en quelques secondes sans journal (jeton absent, service
indisponible, runner jamais acquis) n'est pas « CI rouge » : le dire et pointer les vrais contrôles. « Instable » n'est
pas une cause : une relance au plus, puis enquête.

**Prête à merger** = contrôles requis verts **et** zéro fil ouvert **et** le bot a relu la tête **et** une revue
adversariale APPROUVÉ sur cette tête (et la politique de merge du projet).

## Configuration CodeRabbit recommandée
Sur le modèle des deux projets (`.coderabbit.yaml`) : `language: fr-FR`, `auto_review.drafts: false` (pas de revue des
brouillons, comme la CI), `base_branches` = branches d'intégration et de promotion, `path_filters` qui excluent les
fichiers générés (PNG, SVG exportés), `path_instructions` qui rappellent les règles du projet par dossier (moteur sans UI,
workflows épinglés par SHA et permissions minimales, données de test anonymisées, docs sourcées). Profil `chill` pour un
projet solo, `assertive` quand des contributeurs externes arrivent.
