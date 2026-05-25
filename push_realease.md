# Push Release

> Nom conservé tel quel : `push_realease.md`.

## Objectif

Préparer une build TestFlight / beta de la cible Swift `HFRswift`, la committer, la tagguer, la pousser, puis produire une synthèse utilisateur des changements depuis la build précédente.

## Procédure

1. Vérifier l'état Git.

   ```sh
   git status --short
   git branch --show-current
   ```

   Ne pas embarquer de changements locaux sans rapport avec la release.

2. Incrémenter le numéro de build de `HFRswift`.

   Dans `SuperHFRplus.xcodeproj/project.pbxproj`, mettre à jour les deux occurrences `CURRENT_PROJECT_VERSION` de la cible `HFRswift` :

   - configuration `Debug`
   - configuration `Release`

   Exemple : si la build courante est `15`, passer à `16`.

   Vérification :

   ```sh
   rg -n "CURRENT_PROJECT_VERSION|MARKETING_VERSION|PRODUCT_BUNDLE_IDENTIFIER" SuperHFRplus.xcodeproj/project.pbxproj
   ```

3. Vérifier la signature de l'app.

   Pour la cible `HFRswift`, les configurations `Debug` et `Release` doivent être en signature manuelle pour `iphoneos` :

   - `CODE_SIGN_STYLE = Manual`
   - `"DEVELOPMENT_TEAM[sdk=iphoneos*]" = QMG83DG7YP`
   - `"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]" = "iOS-Distribution-Profile-v2"`
   - `"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Distribution"`

   Vérification :

   ```sh
   rg -n "CODE_SIGN_STYLE|DEVELOPMENT_TEAM|PROVISIONING_PROFILE_SPECIFIER|CODE_SIGN_IDENTITY" SuperHFRplus.xcodeproj/project.pbxproj
   ```

4. Lancer au minimum une vérification de build.

   ```sh
   set -o pipefail
   xcodebuild -project SuperHFRplus.xcodeproj -scheme HFRswift -configuration Release -destination 'generic/platform=iOS' build 2>&1 | rg -n "error:|warning:|BUILD SUCCEEDED|BUILD FAILED|SwiftCompile|Ld "
   ```

5. Committer la release courante.

   Exemple pour une build `16` :

   ```sh
   git add SuperHFRplus.xcodeproj/project.pbxproj
   git commit -m "Prepare build 16"
   ```

   Ajouter les autres fichiers seulement s'ils font partie de la release et ont été validés.

6. Ajouter le tag de build.

   Exemple :

   ```sh
   git tag build#16
   ```

   Si le tag existe déjà, ne pas l'écraser sans décision explicite.

7. Push commit + tag.

   ```sh
   git push
   git push origin build#16
   ```

8. Générer la synthèse des changements depuis le build précédent.

   Exemple pour passer de `build#15` à `build#16` :

   ```sh
   git log --oneline build#15..build#16
   git diff --stat build#15..build#16
   ```

   La synthèse utilisateur doit éviter les détails internes inutiles et regrouper les changements par thèmes :

   - corrections de bugs
   - améliorations UI
   - navigation / stabilité
   - recherche / favoris / messages
   - points à tester en priorité

## Points déjà vérifiés dans le projet

- La cible Swift principale est `HFRswift`.
- Le bundle id de `HFRswift` est `hfrplus.red.super`.
- La version marketing actuelle est `4.0`.
- Le numéro de build actuel trouvé dans `HFRswift` est `15`.
- La cible `HFRswift` est déjà configurée en signature manuelle avec `iOS-Distribution-Profile-v2` pour `iphoneos`.

## Ce que Codex peut faire

- Incrémenter `CURRENT_PROJECT_VERSION` pour `HFRswift` en `Debug` et `Release`.
- Vérifier / remettre la signature manuelle avec `iOS-Distribution-Profile-v2`.
- Faire le commit de release et créer le tag `build#xx`, si demandé explicitement.
- Pousser le commit et le tag, si demandé explicitement.
- Produire une synthèse depuis le tag précédent.

## À clarifier si nécessaire

- La génération et l'upload de l'archive TestFlight ne sont pas détaillés ici. Si on veut automatiser entièrement la release, il faudra ajouter une étape `archive` + `exportArchive`, avec un `ExportOptions.plist` adapté au provisioning profile `iOS-Distribution-Profile-v2`.
- `SuperHFRplus.xcodeproj/project.pbxproj` peut contenir aussi l'ancienne cible `SuperHFRplus`. Pour la beta Swift actuelle, ne modifier que les réglages de la cible `HFRswift`, sauf demande explicite.
