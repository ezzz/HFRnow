---
name: harness-update
description: Met à jour la copie vendorisée du cadre agentic-harness dans ce dépôt vers un tag donné (ou le dernier), en PR brouillon, sans écraser ce qui appartient au projet. À utiliser quand l'opérateur demande de passer à une nouvelle version du cadre.
argument-hint: "[vX.Y.Z]"
---

# Mettre à jour le cadre

Version visée : $ARGUMENTS (vide = dernier tag `vX.Y.Z` de `francoisgn/agentic-harness`).

1. Version actuelle : `.harness/VERSION`. Dernier tag : `git ls-remote --tags --refs https://github.com/francoisgn/agentic-harness.git 'v*'`
   (en session cloud, le dépôt du cadre doit être attaché à la session). Lire le `CHANGELOG.md` du cadre entre les deux.
2. Branche depuis l'intégration à jour : `git switch -c claude/harness-<tag> origin/<intégration>`.
3. Récupérer le cadre au tag dans un dossier jetable (`git clone --depth 1 --branch <tag> … "$TMPDIR/agentic-harness"`),
   puis `"$TMPDIR/agentic-harness/scripts/harness-sync.sh" --target . --dry-run`, et sans `--dry-run` si c'est l'attendu.
4. Code 3 (conflits) : un fichier du cadre a été modifié dans le projet. **Ne pas forcer** sans accord : montrer le
   diff à l'opérateur et proposer soit de reporter la modification dans le cadre (PR sur agentic-harness), soit de la
   déplacer hors du cadre, soit `--force`.
5. Relire `git diff` en entier (LESSONS L17) ; vérifier que `harness-sync.sh --check` sort en 0 ; les références `@vX.Y.Z`
   de `.github/workflows/harness.yml` suivent.
6. Un commit `Cadre agentic-harness : passage en <tag>`, un push, PR en brouillon (`## Changelog` : « Aucun (outillage) »),
   avec dans le corps les points du CHANGELOG du cadre qui demandent une action dans le projet.
