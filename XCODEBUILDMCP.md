# XcodeBuildMCP - principes d'utilisation

Derniere verification locale : 2026-07-06.

## Etat detecte

- Profil actif : `hfrswift-ios-latest`.
- Config persistante : `.xcodebuildmcp/config.yaml`.
- Projet principal retenu : `SuperHFRplus.xcodeproj`.
- Schema principal retenu : `HFRswift`.
- Configuration : `Debug`.
- Simulateur configure : `iPhone 17 Pro Max`.
- Outils MCP disponibles dans cette session : defaults, discovery, schemes, build/run/test simulateur, launch/stop/install, app path/bundle id, screenshots, UI snapshot semantique, video simulateur, coverage.

Le projet `HFRnow.xcodeproj` est detecte mais `list_schemes` echoue avec `Unable to read project 'HFRnow.xcodeproj'`. Pour les builds MCP courants, utiliser `SuperHFRplus.xcodeproj`.

Le depot contient des tests unitaires dans `HFRswiftTests` et un plan `HFRswift.xctestplan`. Aucune cible UI tests dediee n'a ete trouvee au premier niveau au moment de cette verification.

## Regle de depart

Avant le premier build, run ou test MCP d'une session, toujours appeler :

```text
session_show_defaults()
```

Si `projectPath`, `scheme` ou `simulatorName`/`simulatorId` manque, configurer un profil avant de lancer un build. Ne pas supposer que les defaults sont encore valides.

## Profil courant

Le profil persistant cree pour ce depot est :

```yaml
hfrswift-ios-latest:
  projectPath: /Users/bruno/DocumentsLocal/Projects/HwFR/HFRnow/SuperHFRplus.xcodeproj
  scheme: HFRswift
  configuration: Debug
  simulatorName: iPhone 17 Pro Max
  useLatestOS: true
  suppressWarnings: true
  preferXcodebuild: true
  simulatorPlatform: iOS Simulator
```

Attention : apres resolution, le MCP a aussi ecrit un `simulatorId` precis dans `.xcodebuildmcp/config.yaml`. Pour tester une version iOS differente, creer ou activer un profil dedie avec l'ID exact du simulateur, plutot que de compter sur `useLatestOS`.

## Simulateurs utiles detectes

- iOS 17.5 : `iPhone 15` (`A58711AB-0EC0-4667-B183-F5F299E51047`) ou `iPhone SE (3rd generation)` (`82E4CB32-45B4-4C5C-A00F-A7131296193F`).
- iOS 18.6 : `iPhone 16 (iOS 18.6)` (`DA36EEEE-C5B0-4171-B80C-D2727CAE142D`).
- iOS 26.4 : `iPhone 17 Pro Max` (`1A3B24D0-3A6E-4C57-B0B4-DE98E802034F`).
- iOS 26.5 : `iPhone 17 Pro Max` (`53C36A54-3B66-46DA-9BCE-9BAAC0E69072`).
- iOS 27.0 : `iPhone 17 Pro Max` (`9D436DD2-636C-4BCC-A3B6-7B812C3523DF`), actuellement booted lors de la verification.
- iPad iOS 26.5 : `iPad Pro 13-inch (M5)` (`315E1812-5CAD-4779-8A28-D130DF9F2530`) ou `iPad Air 13-inch (M4)` (`4A0BC082-688C-49E9-8388-04AD2AA62B62`).
- iPad iOS 27.0 : `iPad Pro 13-inch (M5)` (`6D975883-7190-4D59-BC31-657C49EE4AFC`) ou `iPad (A16)` (`ABBFD8B8-B718-4AD3-B6CF-9E786D77B406`).

## Strategie de build multi-version

Objectif : verifier vite les regressions par runtime sans consommer trop de contexte.

1. Garder `hfrswift-ios-latest` pour le run interactif par defaut.
2. Creer des profils nommes pour les versions cibles, par exemple `hfrswift-ios17`, `hfrswift-ios18`, `hfrswift-ios26`, `hfrswift-ios27`.
3. Pour chaque version, lancer un `build_sim` ou `test_sim(progress: false)`.
4. Ne remonter dans la conversation que le statut final, les erreurs, et les chemins de logs/xcresult. Eviter de coller les logs complets sauf echec difficile a diagnostiquer.

Exemples de profils a creer si besoin :

```text
session_set_defaults(profile: "hfrswift-ios26", simulatorId: "53C36A54-3B66-46DA-9BCE-9BAAC0E69072", simulatorPlatform: "iOS Simulator", projectPath: ".../SuperHFRplus.xcodeproj", scheme: "HFRswift", configuration: "Debug")
session_set_defaults(profile: "hfrswift-ios27", simulatorId: "9D436DD2-636C-4BCC-A3B6-7B812C3523DF", simulatorPlatform: "iOS Simulator", projectPath: ".../SuperHFRplus.xcodeproj", scheme: "HFRswift", configuration: "Debug")
```

## Boucle visuelle recommandee

Pour une implementation UI SwiftUI/UIKit :

1. `session_show_defaults()`.
2. `build_run_sim()` pour compiler, installer et lancer l'app. Ne pas appeler `boot_sim` avant : `build_run_sim` s'en charge.
3. `screenshot(returnFormat: "path")` pour garder une trace visuelle peu couteuse en tokens.
4. `snapshot_ui()` pour obtenir l'arbre semantique et les `elementRef`.
5. Interagir avec les outils UI MCP si exposes dans la session courante, puis refaire `snapshot_ui()` apres navigation, scroll, sheet ou changement d'ecran.
6. En cas de comportement anime ou transitoire, utiliser `record_sim_video(start/stop)` et ne partager que le chemin du fichier.

Cette boucle doit devenir le reflexe pour les changements d'ecran, de navigation iPad, de Liquid Glass, de layout responsive ou d'accessibilite.

## Tests UI a mettre en place

Priorite recommandee :

- Ajouter une cible `HFRswiftUITests` si elle n'existe pas deja.
- Ajouter des accessibility identifiers stables sur les vues critiques : liste des favoris, liste des sujets, page topic, composition de reponse, menu popup de message, split view iPad.
- Ecrire des tests UI courts et deterministes : lancement, navigation principale, affichage topic, ouverture/fermeture composeur, rotation ou taille iPad si pertinent.
- Prevoir des donnees de test controlees via launch arguments ou environnement pour eviter la dependance au reseau.
- Lancer les tests via `test_sim(progress: false)` et exploiter les screenshots/snapshots MCP en cas d'echec.

## Politique de logs

- Builds reussis : reporter uniquement `SUCCEEDED`, le runtime cible et le simulateur.
- Builds echoues : reporter les erreurs filtrees, les fichiers/lignes et le statut final.
- Runs simulateur : conserver le chemin du log runtime renvoye par `build_run_sim` ou `launch_app_sim`.
- Tests : conserver le chemin `.xcresult` s'il est fourni, puis utiliser les outils coverage seulement quand la couverture est pertinente pour la tache.

## Rappels projet

- Ne pas commit/push sans demande explicite.
- Apres changement Swift/Xcode substantiel, proposer ou lancer un build check.
- Pour iOS 26 Liquid Glass, privilegier les APIs SwiftUI natives (`glassEffect`, `.buttonStyle(.glass)`, `.glassProminent`) avec fallback lisible pour les OS plus anciens.
