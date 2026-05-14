ok go# F5 — Réduction Objective-C progressive

## Objectif

Réduire l'Objective-C au strict périmètre encore utile, sans casser les traitements legacy conservés volontairement : parsing forum, session/compte, cookies, stockage historique, BL/WL, smileys, rendu topic.

Le principe n'est pas de supprimer massivement. Chaque lot doit avoir une preuve statique, une preuve runtime, puis une suppression petite et réversible.

## Règles de suppression

1. Ne supprimer aucun fichier Objective-C/XIB tant qu'une route runtime possible n'est pas exclue.
2. Ne pas toucher à `OfflineMessagesTableViewController`.
3. Garder les controllers ObjC utilisés comme workers tant qu'ils portent du parsing ou de la logique réseau.
4. Une suppression doit passer :
   - recherche `rg` sans référence active ;
   - inspection `project.pbxproj` ;
   - build Debug iOS Simulator ;
   - lancement manuel du flux concerné.
5. Un commit = un petit lot cohérent. Pas de suppression groupée de familles entières.

## Taxonomie

| Classement | Décision |
|---|---|
| `KEEP_TREATMENT` | Garder. Éventuellement isoler derrière une façade Swift plus petite. |
| `WRAP` | Garder mais réduire le couplage Swift/ObjC. |
| `PORT_OR_DROP_UI` | Décider produit : porter SwiftUI ou abandonner explicitement. |
| `QUARANTINE` | Non routé a priori ; candidat après preuve runtime. |
| `DELETE_READY` | Références retirées, runtime validé, suppression possible en lot dédié. |

## Lot Q0 — Inventaire mécanique avant suppression

But : produire une liste fiable des fichiers ObjC/XIB encore présents dans le projet.

Travail :

1. Lister les `.m`, `.h`, `.mm`, `.xib`, `.storyboard` sous `Classes/`, `HFRswift/Wrapped/`, `SuperHFRplus/`.
2. Croiser avec `SuperHFRplus.xcodeproj/project.pbxproj`.
3. Croiser avec les références Swift : `NSClassFromString`, `LegacyLoaderRuntime`, `UIViewControllerRepresentable`, `ObjC*Bridge`.
4. Produire une table `file -> owner -> classification -> preuve`.

Sortie attendue :

- Table ajoutée à `GAPv2.md` ou dans un fichier dédié.
- Aucun code supprimé.

## Lot Q1 — Wrappers Swift non routés

Statut 2026-05-13 : exécuté.

Candidats déjà identifiés :

| Fichier | Hypothèse |
|---|---|
| `PlusTableViewWrapper` | Supprimé de `PlusTab.swift`. |
| `MessageViewWrapper` | Supprimé avec `HFRswift/Wrapped/TopicViewWrapper.swift`. |
| `ObjCMessageComposerView` | Supprimé avec `HFRswift/Swift/ObjCMessageComposerView.swift`. |
| `ObjCViewControllerHost` | Supprimé de `PlusTab.swift`. |

Travail :

1. Confirmer `rg` sans usage actif.
2. Confirmer que les previews/tests ne les référencent pas.
3. Supprimer d'abord les wrappers Swift morts, pas les controllers ObjC derrière.
4. Build.

Critère :

- Aucun symbole wrapper supprimé n'est requis par les flux SwiftUI.

Preuves :

- `rg` ne trouve plus `PlusTableViewWrapper`, `MessageViewWrapper`, `ObjCMessageComposerView`, `ObjCViewControllerHost`.
- `TopicViewWrapper.swift` retiré du projet Xcode.
- Build `HFRswift` Debug iOS Simulator OK.

## Lot Q2 — Plus legacy non routé

Candidats :

| Zone | Fichiers probables |
|---|---|
| Plus principal UIKit | `PlusTableViewController`, `PlusCellView.xib` |
| Settings legacy | `PlusSettingsViewController`, `SettingsView.xib`, dépendances InAppSettingsKit si plus aucune route |
| Aide/Infos/Feedback/Pay | `AideViewController`, `InfosViewController`, `FeedbackViewController`, `PayViewController`, XIB/cellules liées |

Décision préalable :

- Si Aide/Infos/Feedback/Pay sont encore utiles produit, les porter SwiftUI avant suppression.
- Sinon documenter l'abandon explicite dans `GAPv2.md`.

Travail :

1. Vérifier dans `PlusTab.swift` que les routes SwiftUI couvrent les entrées voulues.
2. Valider manuellement l'onglet Plus complet.
3. Supprimer une sous-zone à la fois.

Critère :

- Plus aucun écran UIKit Plus n'apparaît depuis l'app SwiftUI.

Statut 2026-05-13 :

- Partiel réalisé : `PlusTableViewController`, `PlusSettingsViewController`, `PlusCellView`, `SettingsView.xib`, `PlusCellView.xib` et `ThemeSettingsViewController` sont retirés de la cible `HFRswift`.
- `SplitViewController` ne référence plus le Plus UIKit legacy sous `APP_SWIFT`; un placeholder interne garde le fallback iPad compilable.
- `ThemeManager` ne dépend plus de `PlusCellView` sous `APP_SWIFT`.
- Build `HFRswift` Debug iOS Simulator OK.

Statut 2026-05-14 :

- `InfosViewController`, `AideViewController`, `PayViewController`, `InfoTableViewCell` et leurs XIB sont retirés de la cible `HFRswift`.
- La méthode debug `TopicsTableViewController.test` qui instancie `AideViewController` est exclue sous `APP_SWIFT`.
- Build `HFRswift` Debug iOS Simulator OK.
- Reste à traiter `FeedbackViewController` séparément avec le lot profil.

## Lot Q3 — UI compte/session legacy

Candidats :

| Zone | Fichiers probables |
|---|---|
| Login UIKit | `IdentificationViewController` et XIB associé |
| Compte UIKit | `CompteViewController`, cellules compte associées |

Précondition forte :

- B05 validé manuellement : ajout compte, switch, logout/suppression, cookies, persistance après relance.

Travail :

1. Confirmer que `AddAccountView`, `AccountMenuViews`, `AccountsStore`, `LoginService`, `AccountSessionService` couvrent le flux.
2. Garder `MultisManager` et les services ObjC de traitement.
3. Supprimer uniquement l'UI UIKit morte.

Critère :

- Aucun fallback UIKit compte/session visible.

Statut 2026-05-14 :

- Précondition validée manuellement/bêta : flux SwiftUI compte/session utilisé par environ 40 testeurs sans retour négatif.
- `IdentificationViewController`, `CompteViewController`, `CompteTableViewCell` et leurs XIB sont retirés de la cible `HFRswift`.
- `AQTableViewController.h` ne dépend plus de `CompteViewController` sous `APP_SWIFT`.
- `MultisManager`, `BlackList` et les services ObjC de session restent compilés.
- Build `HFRswift` Debug iOS Simulator OK.

## Lot Q4 — UI topic/composer remplacée

Candidats :

| Zone | Fichiers probables |
|---|---|
| Profil UIKit | `ProfilViewController` et XIB |
| Poll UIKit | `PollTableViewController` et XIB/cellules |
| Alerte modo UIKit | `AlerteModoViewController` |
| Composer UIKit | `AddMessageViewController`, `SmileyViewController`, `RehostImageViewController` |

Préconditions :

- Messages SwiftUI validé : ouvrir topic, quote, profil, MP, BL/WL, AQ, bookmark, alerte modération, sondage, réponse/édition.
- Ne pas supprimer `MessagesTableViewController`, `ParseMessagesOperation`, `LinkItem`.

Travail :

1. Supprimer d'abord les wrappers Swift morts si Q1 ne l'a pas déjà fait.
2. Supprimer une UI UIKit à la fois.
3. Garder les services/rendu ObjC utilisés par `MessagesView`.

Critère :

- `MessagesView` reste fonctionnel et le worker ObjC reste isolé.

Statut 2026-05-14 :

- Q4.1 réalisé : `AlerteModoViewController` et son XIB sont retirés de la cible `HFRswift`.
- `MessagesTableViewController` ne conforme plus à `AlerteModoViewControllerDelegate` et n'importe plus `AlerteModoViewController`.
- L'ancien `actionAlerter` du worker ne présente plus d'UI UIKit ; `MessagesView` utilise déjà `ModerationAlertComposerView` via les `alertURL` exportées.
- Build `HFRswift` Debug iOS Simulator OK.

Statut 2026-05-14, passe Q4.2/Q4.3/Q4.4 :

- `PollTableViewController`, `PollResultTableViewCell` et leurs XIB sont retirés de la cible `HFRswift`.
- `ProfilViewController` et son XIB sont retirés de la cible `HFRswift`; le `FeedbackViewController` legacy embarqué dans son `.m` sort donc aussi de la cible Swift.
- `AddMessageViewController`, `QuoteMessageViewController`, `EditMessageViewController`, `NewMessageViewController`, `DeleteMessageViewController`, `SmileyViewController`, `RehostImageViewController`, `RehostCell`, `RehostCollectionCell` et les XIB associés sont retirés de la cible `HFRswift`.
- `MessagesTableViewController` conserve son rôle de worker, mais ne présente plus ces UI UIKit legacy; les chemins SwiftUI existants portent sondage, profil, réponse, quote, édition/suppression et MP.
- `TopicsTableViewController` n'expose plus les headers du composer dans son header public; le fallback legacy reste isolé hors `APP_SWIFT`.
- `SmileyAlertView` et `SmileyCodeTableViewController` restent dans `HFRswift` pour le menu d'action sur les smileys déjà affichés dans les messages.
- Build `HFRswift` Debug iOS Simulator OK.

## Lot Q5 — Listes legacy remplacées par SwiftUI

Candidats :

| Zone | Fichiers probables |
|---|---|
| Bookmarks UIKit | `BookmarksTableViewController` et XIB/cellules |
| AQ UIKit | `AQTableViewController` et XIB/cellules |
| BL/WL UIKit | anciennes listes UIKit si encore présentes |

Préconditions :

- `BookmarksPlusView`, `AQPlusView`, `AppSettingsView` validés manuellement.
- Garder `MPStorage`, `BlackList`, `ObjCMPStorageBridge`.

Critère :

- Plus/Settings restent SwiftUI, traitements ObjC conservés.

Statut 2026-05-14 :

- `BookmarksTableViewController`, `BookmarksCellView`, `AQTableViewController`, `AQCellView`, `BlackListTableViewController`, `WhiteListTableViewController`, `ListTableViewController` et leurs XIB sont retirés de la cible `HFRswift`.
- `BookmarksPlusView` et `AQPlusView` restent les routes SwiftUI de l'onglet Plus.
- Les actions BL/WL restent portées par `UserProfileView` via `ObjCProfileFilterListManager`.
- `Bookmark`, `MPStorage`, `BlackList` et `ObjCMPStorageBridge` restent compilés dans `HFRswift`.

## Lot Q6 — Cellules/XIB legacy orphelins

But : nettoyer les ressources XIB uniquement après suppression des controllers propriétaires.

Travail :

1. Pour chaque XIB, identifier son controller/cell propriétaire.
2. Si le propriétaire a été supprimé et que `project.pbxproj` n'a plus de référence utile, supprimer le XIB.
3. Build + lancement.

Critère :

- Aucun XIB supprimé n'est chargé dynamiquement par nom.

Statut 2026-05-14 :

- `AccessoryView.xib`, `FeedbackTableViewCell`, `FeedbackViewController.xib`, `PersonnalLinkViewController.xib`, `ConfigurationViewController.xib`, `HFRDebugViewController` et son XIB sont retirés de la cible `HFRswift`.
- `CreditsViewController` et son XIB sont retirés de la cible `HFRswift`; `credits.html` et `charte.html` restent conservés car `StaticInfoPageView` les utilise pour les routes SwiftUI.
- `ColorPickerViewController`, `ThemeColorCellView`, `ThemeBrightnessCellView` et leurs XIB sont retirés de la cible `HFRswift`; `ThemeSettingsViewController` était déjà hors cible Swift.
- `PopupViewController` et son XIB sont retirés de la cible `HFRswift`; ils ne sont plus référencés que par `SmileyViewController`, déjà sorti de cette cible.
- `RehostImage.m` est retiré de la cible `HFRswift`; les écrans legacy `RehostImageViewController`, `RehostCell` et `RehostCollectionCell` étaient déjà hors cible Swift.
- `SmileyAlertView`, `SmileyCodeTableViewController`, `SmileyCodeCellView` et leurs XIB restent conservés : `MessagesTableViewController` appelle encore `SmileyAlertView` pour l'action smiley depuis le rendu topic.
- `SimpleCellView` reste conservé pour l'instant : `ThemeManager` référence encore explicitement sa classe.
- Build `HFRswift` Debug iOS Simulator OK.

Audit des suivants :

- `PageViewController` reste nécessaire : `MessagesTableViewController`, `BaseTopicsViewController` et `OfflineMessagesTableViewController` en héritent encore.
- `SimplePhotoViewController` reste nécessaire : `MessagesTableViewController` l'instancie encore pour l'affichage photo.
- `FavoriteCellView`, `FavoritesTableViewController` et leurs XIB restent nécessaires : `Common.swift` instancie encore `FavoritesTableViewController` comme worker pour les favoris.
- `FilterPostsQuotes` reste nécessaire : `FavoritePostFilterService` l'instancie encore comme worker.
- `SmileyCode*` reste nécessaire tant que l'action smiley dans `MessagesTableViewController` passe par `SmileyAlertView`.

## À garder explicitement pour l'instant

| Zone | Raison |
|---|---|
| `MessagesTableViewController` | Worker topic/search/filter encore central. |
| `ParseMessagesOperation`, `LinkItem` | Parsing/rendu HTML forum. |
| `ForumsTableViewController`, `TopicsTableViewController`, `FavoritesTableViewController`, `HFRMPViewController`, `TopicsSearchViewController` | Workers de chargement tant que les loaders Swift s'appuient dessus. |
| `MultisManager` | Session, cookies, compte courant. |
| `MPStorage`, `Bookmark` | Stockage historique/bookmarks/MP/AQ. |
| `BlackList` | BL/WL et rendu filtré. |
| `SmileyCache` | Cache/favoris smileys. |
| `ThemeManager`, `ThemeColors`, `k` | Compatibilité thème/URLs legacy. |
| `SDWebImage` | GIF/images et compatibilité tant que call sites présents. |

## Première tâche recommandée

Commencer par **Q1 — Wrappers Swift non routés**.

Raison :

- faible risque ;
- surface réduite ;
- permet de prouver la méthode ;
- ne touche pas encore aux fichiers ObjC lourds.
