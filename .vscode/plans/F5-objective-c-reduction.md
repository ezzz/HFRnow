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
- `SmileyCode*` reste nécessaire tant que l'action smiley dans `MessagesTableViewController` passe par `SmileyAlertView`. Résolu dans la suite Q6 smileys.

Statut 2026-05-14, suite Q6 :

- `SimpleCellView.m` et `SimpleCellView.xib` sont retirés de la cible `HFRswift`.
- La dépendance `ThemeManager -> SimpleCellView` est isolée hors `APP_SWIFT`, car `SimpleCellView` ne sert plus que le flux UIKit `SmileyViewController` déjà sorti de la cible Swift.
- Build `HFRswift` Debug iOS Simulator OK.

Statut 2026-05-14, suite Q6 smileys :

- `SmileyAlertView.m`, `SmileyCodeTableViewController.m`, `SmileyCodeCellView.m`, `SmileyCodeTableView.xib` et `SmileyCodeCellView.xib` sont retirés de la cible `HFRswift`.
- Les imports `SmileyAlertView` restants dans `MessagesTableViewController` et `TopicsTableViewController` sont isolés hors `APP_SWIFT`.
- La cible Swift conserve le flux smiley via `MessageWebAction.manageSmileyFavorite` et `MessageSmileySheetView` dans `MessagesView`.
- Build `HFRswift` Debug iOS Simulator OK.

Statut 2026-05-14, suite Q6 favoris :

- `ObjCFavoritesLoader` n'instancie plus `FavoritesTableViewController`; il utilise `ObjCFavoritesLoaderWorker`, un `NSObject` dédié au chargement/parsing des favoris.
- `FavoritesTableViewController.m`, `FavoritesTableViewController.xib`, `FavoriteCell.m`, `FavoriteCellView.m` et `FavoriteCellView.xib` sont retirés de la cible `HFRswift`.
- Les références UIKit legacy à `FavoritesTableViewController` dans `TabBarController`, `SplitViewController` et `HFRplusAppDelegate` sont isolées hors `APP_SWIFT`.
- Build `HFRswift` Debug iOS Simulator OK.

Audit 2026-05-15 :

- `FilterPostsQuotes` est maintenant scindé de fait en deux usages :
  - côté Swift actif : `fetchFilteredPostsForTopic:startPage:progress:completion:` et `cancelSwiftFiltering`, appelés par `FavoritePostFilterService`;
  - côté UIKit legacy : `favoriteVC`, `checkPostsAndQuotesForTopic:andVC:`, barre de progression UIKit et `displayPosts:`, encore liés à `FavoritesTableViewController`.
- Suite logique pour `FilterPostsQuotes` : isoler ou supprimer le chemin UIKit legacy sous `APP_SWIFT`, puis réduire son header public aux seules API utilisées par Swift et `MessagesTableViewController`.
- `PageViewController` reste nécessaire dans `HFRswift` : `MessagesTableViewController` en hérite encore et utilise ses états de pagination, ses URLs de page et le support offline.
- `BaseTopicsViewController` reste nécessaire dans `HFRswift` : `TopicsTableViewController` et `TopicsSearchViewController` en héritent encore, et les loaders Swift dépendent toujours de leur parsing/navigation topic.
- Suite logique pour `PageViewController` / `BaseTopicsViewController` : ne pas tenter une suppression directe ; extraire d'abord des workers dédiés pour les listes topics (`TopicsTableViewController`, `TopicsSearchViewController`, éventuellement `HFRMPViewController`) puis réévaluer la hiérarchie UIKit restante.

Statut 2026-05-15, suite Q6 `FilterPostsQuotes` :

- La dépendance directe à `FavoritesTableViewController` est isolée hors `APP_SWIFT` dans `FilterPostsQuotes`.
- Le chemin UIKit favoris legacy (`favoriteVC`, `checkPostsAndQuotesForTopic:andVC:`, `displayPosts:`) n'est plus exposé dans le build Swift.
- Le chemin `MessagesTableViewController` reste conservé dans `HFRswift` : le worker topic appelle encore `checkNextPostsAndQuotesWithVC:`.
- Build `HFRswift` Debug iOS Simulator OK.

Découpage recommandé pour l'extraction topics :

1. Extraire `ObjCForumTopicsLoaderWorker` depuis le chemin `fetchContentForForum:flagIndex:pageURL:completion:` de `TopicsTableViewController`.
2. Extraire `ObjCForumSearchWorker` depuis les méthodes `performForumSearchWithParams:completion:` / `fetchForumSearchPageURL:completion:` de `TopicsSearchViewController`.
3. Extraire `ObjCMPTopicsLoaderWorker` depuis `fetchContentWithCompletion:` de `HFRMPViewController`.
4. Seulement après ces trois bascules, réauditer `BaseTopicsViewController` puis `PageViewController`.

Statut 2026-05-15, extraction topics :

- `ObjCForumTopicsLoader` n'instancie plus directement `TopicsTableViewController`; il passe par `ObjCForumTopicsLoaderWorker`.
- Cette première extraction conserve provisoirement `BaseTopicsViewController` comme support de parsing partagé. Le parser topic y reste encore mêlé à du code UIKit, donc une suppression directe serait prématurée.
- `TopicsTableViewController` reste compilé dans `HFRswift` pour l'instant : il reste utilisé par le legacy interne et n'est pas encore le prochain fichier supprimable.
- Audit après cette bascule :
  - `BaseTopicsViewController` reste requis par `ObjCForumTopicsLoaderWorker`, `TopicsTableViewController` et `TopicsSearchViewController`;
  - `PageViewController` reste requis par `MessagesTableViewController`, `OfflineMessagesTableViewController` et `BaseTopicsViewController`.
- Suite logique inchangée : extraire ensuite la recherche forum, puis les MP, avant de déplacer le parsing hors de la hiérarchie UIKit et de réévaluer les suppressions.

Statut 2026-05-15, passe workers recherche/MP :

- `ObjCForumSearchService` n'instancie plus directement `TopicsSearchViewController`; il passe par `ObjCForumSearchWorker`.
- `ObjCMPTopicsLoader` n'instancie plus directement `HFRMPViewController`; il passe par `ObjCMPTopicsLoaderWorker`.
- `ObjCMPTopicsLoaderWorker` réutilise désormais le chemin worker topic commun pour charger `/forum1.php?config=hfr.inc&cat=prive&page=1`, sans initialiser la vue UIKit MP.
- Build `HFRswift` Debug iOS Simulator OK.

Réaduit après les trois bascules worker :

- `TopicsTableViewController`, `TopicsSearchViewController` et `HFRMPViewController` ne sont plus des points d'entrée directs depuis Swift.
- Ils ne sont pas encore supprimables de `HFRswift` :
  - `ObjCForumSearchWorker` hérite encore de `TopicsSearchViewController`, car toute la logique de recherche est encore portée par cette classe ;
  - `HFRMPViewController` reste référencé par le legacy UIKit interne (`SplitViewController`, `TabBarController`, `HFRplusAppDelegate`) ;
  - `TopicsTableViewController` reste la base UIKit de `HFRMPViewController` et garde des références legacy internes.
- Le prochain vrai lot de suppression n'est donc plus un simple changement de loader : il faut extraire `parseTopicsListResult:` et l'état de pagination topic dans un composant non-UIKit, puis réimplémenter `ObjCForumSearchWorker` sans héritage de `TopicsSearchViewController`.
- Après seulement cette extraction de parser, réauditer :
  1. retrait de `TopicsSearchViewController` du build Swift ;
  2. retrait éventuel de `HFRMPViewController` / `TopicsTableViewController` si les références legacy restantes sont isolables sous `!APP_SWIFT` ;
  3. réduction ou retrait de `BaseTopicsViewController`, puis de `PageViewController`.

Statut 2026-05-15, découplage recherche :

- `ObjCForumSearchWorker` ne dépend plus de `TopicsSearchViewController`; il porte maintenant directement le bridge de recherche forum et réutilise le chemin worker topic partagé.
- `TopicsSearchViewController` n'est donc plus requis par les routes Swift actives.
- La tentative suivante de suppression doit rester séparée du déplacement de parser : `parseTopicsListResult:` mélange encore parsing, notifications et construction du footer UIKit dans `BaseTopicsViewController`.
- Pour sortir réellement le parser, il faut d'abord séparer ce bloc en deux responsabilités :
  1. un résultat de parsing sans UIKit (topics, pagination, filtres, état MP, statut) ;
  2. l'application de ce résultat à l'UI legacy (`setSegmentEnabled`, footer de pagination, notifications).
- `TopicsSearchViewController.m` est retiré de la cible `HFRswift`; le bouton de recherche forum UIKit restant dans `TopicsTableViewController` est isolé hors `APP_SWIFT`.

Audit 2026-05-15 après validation runtime :

- Validation manuelle utilisateur reçue après la bascule des trois workers : app toujours OK.
- Suppression effectivement obtenue dans cette passe : `TopicsSearchViewController.m` sort de `HFRswift`.
- Suppressions encore bloquées :
  - `TopicsTableViewController` reste référencé par `ForumsTableViewController`, `FavoritesTableViewController`, `SplitViewController`, `OnlineMessagesTableViewController` et comme superclasse de `HFRMPViewController`;
  - `HFRMPViewController` reste référencé par `SplitViewController`, `TabBarController` et `HFRplusAppDelegate`;
  - `BaseTopicsViewController` reste nécessaire à `ObjCForumTopicsLoaderWorker`, `ObjCForumSearchWorker`, `ObjCMPTopicsLoaderWorker` et `TopicsTableViewController`;
  - `PageViewController` reste nécessaire à `MessagesTableViewController`, `OfflineMessagesTableViewController` et `BaseTopicsViewController`.
- Conclusion : les points 1 à 4 ne peuvent pas être terminés honnêtement par simple suppression après les tests manuels ; le prochain lot est un refactor structurant, pas un nettoyage :
  1. introduire un `ObjCTopicListParsingResult` sans UIKit ;
  2. extraire dans un parseur dédié la lecture HTML et la production de ce résultat ;
  3. laisser `BaseTopicsViewController` appliquer seulement les effets UI legacy à partir du résultat ;
  4. faire consommer le résultat directement par les workers, puis réauditer les retraits de `TopicsTableViewController`, `HFRMPViewController`, `BaseTopicsViewController` et `PageViewController`.

Statut 2026-05-15, extraction parser topic :

- `ObjCTopicListParsingResult` et `ObjCTopicListParser` isolent désormais le parsing HTML topic hors de la hiérarchie UIKit.
- `BaseTopicsViewController` applique le résultat de parsing au legacy UI via `applyTopicListParsingResult:`.
- `ObjCForumTopicsLoaderWorker`, `ObjCForumSearchWorker` et `ObjCMPTopicsLoaderWorker` consomment directement le résultat du parser partagé.
- Réaudit après extraction :
  - `TopicsSearchViewController.m` reste bien hors de `HFRswift`;
  - `TopicsTableViewController` et `HFRMPViewController` restent compilés uniquement à cause de routes UIKit legacy internes encore présentes dans `ForumsTableViewController`, `SplitViewController`, `TabBarController` et `HFRplusAppDelegate`;
  - `BaseTopicsViewController` reste requis par les workers pour le transport réseau et l'application commune du résultat;
  - `PageViewController` reste requis par `MessagesTableViewController`, `OfflineMessagesTableViewController` et `BaseTopicsViewController`.
- Conclusion de la passe : les étapes 1 à 4 sont réalisées, mais aucune suppression supplémentaire autre que `TopicsSearchViewController.m` n'est encore sûre sans traiter explicitement les dernières routes UIKit legacy elles-mêmes.

Statut 2026-05-15, retrait routes topics/MP legacy Swift :

- Les derniers imports et appels UIKit vers `TopicsTableViewController` / `HFRMPViewController` sont isolés hors `APP_SWIFT` dans `SplitViewController`, `TabBarController`, `HFRplusAppDelegate`, `ForumsTableViewController`, `OnlineMessagesTableViewController` et `OfflineMessagesTableViewController`.
- `TopicsTableViewController.m` et `HFRMPViewController.m` sont retirés de la cible `HFRswift`.
- Les fichiers restent présents pour la cible Objective-C legacy; seule la cible Swift cesse de les compiler.
- Build `HFRswift` Debug iOS Simulator OK après ajout explicite de l'import `RegexKitLite` dans `HFRplusAppDelegate`.
- Réaudit :
  - `BaseTopicsViewController` n'est plus requis par des écrans topics Swift actifs, mais reste la superclasse des workers topic/recherche/MP pour le transport réseau et l'application du résultat;
  - `PageViewController` reste encore requis par `BaseTopicsViewController` et par les écrans messages legacy encore conservés;
  - prochaine étape utile : extraire le transport réseau topic dans un worker non-UIViewController, puis faire quitter `BaseTopicsViewController` aux trois workers.

Statut 2026-05-15, transport topic non-UI :

- `ObjCTopicListLoaderWorkerBase` porte désormais le transport réseau et l'état partagé des workers topic sous forme d'un `NSObject`.
- `ObjCForumTopicsLoaderWorker`, `ObjCForumSearchWorker` et `ObjCMPTopicsLoaderWorker` ne dépendent plus de `BaseTopicsViewController`.
- `BaseTopicsViewController.m` est retiré de la cible `HFRswift`; il reste uniquement pour la cible Objective-C legacy avec `TopicsTableViewController` / `TopicsSearchViewController`.
- Audit `OfflineMessagesTableViewController` :
  - aucun usage depuis SwiftUI ni aucune entrée `OfflineMessagesTableViewController.m in Sources` dans `HFRswift`;
  - les références trouvées sont internes à son propre fichier;
  - la fonctionnalité d'écran offline legacy est donc déjà hors cible Swift.
- Clarification `MessagesTableViewController` :
  - il reste compilé non comme écran SwiftUI, mais comme worker legacy encore appelé par `ObjCTopicPageLoader`, `TopicSearchService` et `FavoritePostFilterService`;
  - ses responsabilités actives côté Swift sont le chargement/parsing d'une page topic, l'extraction des actions par message, la recherche intra-topic et le rendu des posts filtrés;
  - prochain chantier cohérent avec l'objectif produit : extraire ces responsabilités dans des workers métier non-UIKit, puis retirer à son tour l'UI de `MessagesTableViewController` de la cible Swift.

Statut 2026-05-15, premier lot `MessagesTableViewController` :

- `ObjCTopicSearchWorker` porte désormais la recherche intra-topic `/transsearch.php` hors de `MessagesTableViewController`.
- `ObjCTopicSearchService` instancie ce worker dédié au lieu de passer par `LegacyTopicWorkerRuntime`.
- Responsabilités encore actives dans `MessagesTableViewController` côté Swift :
  1. chargement/parsing d'une page topic;
  2. extraction des actions par message;
  3. rendu des posts filtrés favoris.
- Suite logique recommandée : extraire ensuite le rendu des posts filtrés, qui réutilise déjà des items parsés existants et ne nécessite pas de requête réseau.

Statut 2026-05-15, second lot `MessagesTableViewController` :

- Audit du rendu filtré : il reste encore trop couplé à `manageLoadedItems:` (HTML global, toolbar legacy, état de navigation, thèmes et side effects UIKit) pour être extrait proprement en un seul petit lot.
- `ObjCMessageActionsBuilder` extrait la construction des actions par message hors de `MessagesTableViewController`.
- `swiftMessageActionsByIndex` devient un adaptateur mince vers ce builder.
- Ce builder est maintenant une brique métier partagée prête à être réutilisée quand le rendu HTML filtré puis le chargement topic seront extraits.
- Suite logique : extraire un renderer HTML topic pur à partir de `manageLoadedItems:`; une fois ce renderer disponible, le rendu filtré pourra sortir sans recopier l'ancien contrôleur entier.

Statut 2026-05-15, troisième lot `MessagesTableViewController` :

- Le premier morceau du rendu HTML sort avec `ObjCTopicToolbarHTMLBuilder`.
- `manageLoadedItems:` délègue désormais la génération du fragment de toolbar HTML à ce builder pur.
- Le reste du gabarit HTML reste encore dans `MessagesTableViewController`; la prochaine extraction doit viser le document complet une fois les entrées de rendu regroupées dans une structure dédiée.

Statut 2026-05-15, quatrième lot `MessagesTableViewController` :

- `ObjCTopicHTMLRenderContext` formalise les entrées nécessaires au rendu du document HTML.
- `ObjCTopicHTMLRenderer` porte désormais la génération du document HTML complet hors de `MessagesTableViewController`.
- `manageLoadedItems:` conserve encore la préparation des messages, de l'ancre et des side effects UIKit, puis délègue le document final au renderer.
- Le rendu filtré devient maintenant extractible par étapes : il reste à sortir la préparation du contenu message/ancre hors de `manageLoadedItems:`, puis il pourra partager le même renderer sans dépendre du contrôleur entier.

Statut 2026-05-15, cinquième lot `MessagesTableViewController` :

- `ObjCTopicMessageContentBuilder` et `ObjCTopicMessageContentResult` sortent la préparation du contenu message hors du contrôleur :
  - assemblage HTML des `LinkItem`;
  - insertion du séparateur de nouveaux messages;
  - résolution de l'ancre la plus proche.
- `manageLoadedItems:` ne conserve plus que l'orchestration et les side effects UIKit autour de ces briques métier.
- Le rendu filtré dispose maintenant de toutes les briques pures nécessaires (`ObjCTopicMessageContentBuilder`, `ObjCTopicToolbarHTMLBuilder`, `ObjCTopicHTMLRenderer`, `ObjCMessageActionsBuilder`) pour être extrait au prochain lot.

Statut 2026-05-15, sixième lot `MessagesTableViewController` :

- `ObjCFilteredPostsRendererWorker` porte désormais `renderFilteredPosts:topic:startPage:endPage:finished:completion:` hors de `MessagesTableViewController`.
- `FavoritePostFilterService` utilise ce worker dédié.
- L'ancienne API de rendu filtré est retirée de `MessagesTableViewController`.
- Responsabilités encore actives côté Swift dans `MessagesTableViewController` :
  1. chargement/parsing d'une page topic;
  2. exposition des actions par message sur la dernière page chargée.
- Suite logique : extraire le chargement/parsing d'une page topic dans un worker dédié, en réutilisant les builders déjà sortis.

Statut 2026-05-16, septième lot `MessagesTableViewController` :

- `ObjCTopicPageWorker` porte désormais le chargement/parsing d'une page topic et l'exposition des actions de messages pour le chemin SwiftUI.
- `LegacyTopicWorkerRuntime` instancie maintenant `ObjCTopicPageWorker` au lieu de `MessagesTableViewController`.
- `MessagesView` ne dépend donc plus de `MessagesTableViewController` côté Swift pour :
  1. le chargement d'une page topic;
  2. la recherche intra-topic;
  3. le rendu filtré;
  4. les actions par message.
- Build `HFRswift` Debug iOS Simulator OK après intégration du worker.
- `MessagesTableViewController` reste encore dans la cible Swift à cause du graphe UIKit legacy compilé autour de lui (`MessagesSearchTableViewController`, `PageViewController`, anciens contrôleurs de listes et fallbacks), pas à cause du chemin SwiftUI actif.
- Suite logique : auditer puis retirer de la cible Swift les derniers chemins UIKit legacy qui maintiennent encore `MessagesTableViewController` compilé.

Statut 2026-05-16, huitième lot `MessagesTableViewController` :

- `MessagesSearchTableViewController` est sorti de la cible `HFRswift`.
- La classe est une sous-classe vide de `MessagesTableViewController`, sans instanciation restante ni usage SwiftUI; les seules références encore présentes sont des imports legacy.
- Build `HFRswift` Debug iOS Simulator OK après retrait de la cible.
- Audit suivant :
  1. `PageViewController` ne peut pas sortir tant que `BaseTopicsViewController` et `MessagesTableViewController` restent dans la cible;
  2. les contrôleurs de listes legacy encore présents (`TopicsTableViewController`, `FavoritesTableViewController`, `HFRMPViewController`, `TopicsSearchViewController`) restent utilisés comme workers historiques;
  3. le prochain vrai chantier doit donc viser leur remplacement worker par worker, puis la sortie conjointe de `BaseTopicsViewController` et `MessagesTableViewController`.

Statut 2026-05-16, neuvième lot `MessagesTableViewController` :

- Vérification du graphe réel de la cible `HFRswift` :
  - `BaseTopicsViewController.m` n'était déjà plus présent dans la phase de sources de la cible;
  - les anciens loaders SwiftUI utilisent déjà `ObjCForumTopicsLoaderWorker`, `ObjCFavoritesLoaderWorker`, `ObjCMPTopicsLoaderWorker` et `ObjCForumSearchWorker`, pas les contrôleurs de listes UIKit.
- Les derniers chemins `FilterPostsQuotes` qui pilotaient l'ancien UI topic sont isolés sous `!APP_SWIFT`.
- `MessagesTableViewController.m` et `PageViewController.m` sont retirés de la cible `HFRswift`.
- Build `HFRswift` Debug iOS Simulator OK après retrait conjoint.
- Conséquence : le chemin SwiftUI n'embarque plus le contrôleur topic UIKit ni sa superclasse de pagination; ils restent uniquement dans la cible legacy.
- Prochain audit utile hors de ce sous-chantier : revoir les contrôleurs UIKit encore compilés dans `HFRswift` mais indépendants de `MessagesTableViewController` (`ForumsTableViewController`, `TabBarController`, `SplitViewController`, etc.).

## À garder explicitement pour l'instant

| Zone | Raison |
|---|---|
| `MessagesTableViewController`, `PageViewController`, `BaseTopicsViewController` | Conservés dans la cible legacy, plus compilés dans `HFRswift`. |
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
