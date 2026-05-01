# GAPv2 — État courant migration UI SwiftUI

> Mise à jour 2026-05-01 après dérive positive du plan initial. Objectif produit inchangé : porter toutes les features avec UI depuis Objective-C/UIKit vers SwiftUI, tout en conservant temporairement Objective-C pour les traitements lourds et risqués, notamment parsing forum, stockage historique et services legacy.

---

## Synthèse

La migration UI est désormais proche de la couverture complète des flux visibles iPhone. Le plan initial sous-estimait ce qui a été livré depuis :

- `UserProfileView.swift` remplace la vue profil UIKit et s’ouvre directement depuis les avatars/messages.
- `PollView.swift` couvre l’affichage et le vote des sondages.
- `ForumSearchView.swift` couvre la recherche forum native SwiftUI.
- `MessagesView.swift` couvre largement les actions contextuelles : quote, profil, MP, BL/WL, AQ, bookmark, alerte modération, recherche dans topic, photos/GIF/smileys.
- `AppSettingsView.swift` remplace l’essentiel des settings utilisateur, thème, listes noire/blanche.
- `PlusTab.swift` expose déjà les routes Plus principales en SwiftUI : réglages, recherche forum, bookmarks, AQ, crédits, charte, suppression de compte.

Le nouvel axe de travail n’est plus “porter les gros écrans UI”, mais :

1. Identifier les dernières UI legacy réellement encore visibles.
2. Stabiliser les écarts mineurs de parité.
3. Réduire progressivement Objective-C au scope strict des traitements utilisés, sans suppression destructrice tant que l’usage n’est pas prouvé mort.

---

## Décisions structurantes à jour

1. `OfflineMessagesTableViewController` reste hors scope et ne doit pas être porté.
2. `MessagesView` conserve le rendu WebView fichier-local (`loadFileURL`) pour préserver CSS et ressources locales.
3. Objective-C reste autorisé pour le parsing forum, les bridges historiques, `MPStorage`, `MultisManager`, `BlackList`, `SmileyCache`, `k`, et les traitements réseau/HTML risqués.
4. Toute nouvelle UI doit être SwiftUI. Aucun nouveau XIB/NIB dans le flux migré.
5. Les choix techniques/UI récents priment sur le plan initial : Liquid Glass natif iOS 26 via helpers existants, sheets SwiftUI, `SFSafariViewController` seulement comme viewer web externe.
6. Pas d’effort supplémentaire demandé sur les tests pour cette phase. Les tests existants restent utiles, mais le plan ne bloque plus les features sur une extension de couverture.
7. iPad reste basse priorité, à décider plus tard.
8. Après couverture UI, la phase suivante est une réduction prudente de l’Objective-C : observer, documenter, isoler, puis supprimer uniquement ce qui est prouvé inutilisé.

---

## Inventaire SwiftUI actuel

| Zone | SwiftUI actuel | État |
|---|---|---|
| App/root/tabs | `HFRswiftApp.swift`, `MainWindow.swift`, `RootTabView` | Couvert |
| Forums/catégories | `CategoriesListView`, `ForumTopicsListView` | Couvert |
| Topics/actions rapides | `TopicListRowView`, `TopicQuickActionsConfiguration`, page picker | Couvert |
| Messages topic | `MessagesView.swift`, `WebView`, action handler, rendu fichier-local | Couvert, hardening continu |
| Réponse/édition/MP | `AnswerView.swift`, `ReplyComposer.swift`, `ReplyService.swift` | Couvert |
| Smileys/images/GIF | `ReplySmileyCatalog`, smiley sheet, image viewer/GIF | Couvert |
| Profil utilisateur | `UserProfileView.swift` | Couvert, polish récent |
| Sondages | `PollView.swift`, `PollData.swift` | Couvert |
| Recherche forum | `ForumSearchView.swift`, `ForumSearchService.swift` | Couvert |
| Recherche dans topic | `TopicSearchSheetView.swift`, `TopicSearchService.swift` | Couvert |
| Favoris | `Favorites.swift` | Couvert fonctionnellement, edge cases possibles |
| Messages privés | `MPListView.swift` | Couvert |
| Bookmarks | `BookmarksPlusView.swift` | Couvert |
| Alertes Qualitay | `AQPlusView.swift` + création AQ depuis message | Couvert |
| Alerte modération | `ModerationAlertComposerView` dans `MessagesView.swift`, `ReplyService.swift` | Couvert |
| Settings | `AppSettingsView.swift` | Couvert principal, parité fine à vérifier |
| Listes noire/blanche | `ProfileFilterListEditorView`, actions profil/message | Couvert |
| Plus | `PlusTab.swift` | Couvert principal |
| Pages statiques | `StaticInfoPageView.swift` credits/charte | Partiel |
| Comptes/login | `AddAccountView`, `AccountMenuViews`, `LoginService`, `AccountsStore` | Couvert principal, hardening session restant |

---

## Manques prioritaires restants

### P0 — À clarifier avant réduction Objective-C

| ID | Statut | Manque | Pourquoi |
|---|---|---|---|
| G09 | InProgress | Hardening session/compte et contrat `MultisManager` | Risque transversal : login, cookies, hash, compte courant |
| G10 | NotStarted | Validation startup/background | Risque runtime discret : restore onglet, refresh MP/AQ, cache, compte actif |
| G12 | NotStarted | Cartographie du scope ObjC réellement utilisé | Prérequis avant réduction sans destruction |
| G17 | InProgress | Inventaire XIB/NIB encore sur chemins visibles | Nécessaire pour savoir quoi garder, wrapper ou retirer |

### P1 — Derniers écarts UI visibles probables

| ID | Statut | Manque | Décision actuelle |
|---|---|---|---|
| G02 | NotStarted | Filtres rapides forum Favoris/Suivis/Lus/Tous depuis liste forums | Seul manque power-user net côté forums |
| G26 | InProgress | Parité thème avancée historique | `AppSettingsView` couvre accent/luminosité logique, mais parité ancien sélecteur couleur à confirmer |
| G27 | NotStarted | Page Aide SwiftUI | À ajouter si encore exposée/utile dans Plus |
| G28 | NotStarted | Infos app / feedback SwiftUI | À vérifier : peut être réduit ou remplacé par credits/charte/mail |
| G29 | NotStarted | Vue paiement/abonnement si encore exposée | `PayViewController` existe côté ObjC, usage actuel à confirmer |

### P2 — Basse priorité / polish

| ID | Statut | Manque | Décision actuelle |
|---|---|---|---|
| G11 | NotStarted | iPad split/master-detail | Étude d’intérêt seulement |
| G15 | Deferred | Previews exhaustives mock | Non prioritaire selon demande actuelle |
| G30 | NotStarted | Harmonisation finale Liquid Glass | À faire après stabilisation des dernières UI |

---

## Gaps historiques reclassés

| ID | Ancien état | État courant | Note |
|---|---|---|---|
| G01 Navigation catégories/forums | Done | Done | Stable |
| G02 Filtres rapides forum | NotStarted | NotStarted | Reste un vrai manque |
| G03 Actions rapides sujet | Done | Done | Stable |
| G04 Favoris avancés | InProgress | Done/Watch | Fonctionnellement couvert ; garder en observation edge cases |
| G05 MP actions rapides | Done | Done | Stable |
| G06 Interactions WebView topic | InProgress | Done/Watch | Couverture large ; maintenir hardening |
| G07 Flux réponse fiable | Done | Done | Stable |
| G08 Routes Plus | NotStarted | Done/Watch | Plus principal SwiftUI, routes secondaires à vérifier |
| G09 Session multi-compte | NotStarted | InProgress | UI présente, contrat session à durcir |
| G10 Startup/background | NotStarted | NotStarted | À valider |
| G11 iPad | NotStarted | NotStarted | Basse priorité |
| G12 Frontière interop | NotStarted | NotStarted | Devient axe principal post-UI |
| G13 Tests wrapper/politiques | InProgress | Deferred | Pas d’effort test supplémentaire demandé |
| G14 Settings hors COTS | NotStarted | Done/Watch | `PlusTab` route vers `AppSettingsView`; vérifier dépendance legacy résiduelle hors flux |
| G15 Previews mock | NotStarted | Deferred | Non bloquant |
| G16 Offline topic déprécié | LockedOut | LockedOut | Inchangé |
| G17 XIB/NIB flux migrés | NotStarted | InProgress | À inventorier précisément |
| G18 Composer réponse | Done | Done | Stable |
| G19 Actions contextuelles quote/profil | Done | Done+ | Étendu au-delà du scope initial |
| G20 Profil utilisateur | NotStarted | Done | `UserProfileView.swift` |
| G21 Recherche forum | NotStarted | Done | `ForumSearchView.swift` |
| G22 Gestion listes BL/WL | NotStarted | Done | `AppSettingsView` + actions message/profil |
| G23 Sondages | NotStarted | Done | `PollView.swift` |
| G24 Login SwiftUI | InProgress | Done/Watch | `AddAccountView` + services ; hardening session dans G09 |
| G25 Alerte modération | NotStarted | Done | `ModerationAlertComposerView` |
| G26 Thème avancé | NotStarted | InProgress | À confirmer contre legacy |
| G27 Aide | NotStarted | NotStarted | Reste possible manque |
| G28 Infos/feedback | NotStarted | NotStarted | À confirmer produit |

---

## Objective-C restant — règle de réduction

Ne pas supprimer “parce que ça semble vieux”. Réduction par étapes :

1. Lister les classes ObjC encore appelées par Swift ou par l’app delegate.
2. Marquer chaque classe : `Traitement utilisé`, `UI legacy encore visible`, `UI legacy non visible`, `Inconnu`.
3. Pour `Traitement utilisé`, garder et isoler derrière protocole Swift si le coût est faible.
4. Pour `UI legacy encore visible`, décider : porter SwiftUI ou conserver temporairement si hors scope.
5. Pour `UI legacy non visible`, garder en quarantaine documentaire jusqu’à preuve par build/runtime.
6. Supprimer seulement après recherche statique, validation runtime et absence de référence projet/XIB.

Classes ObjC probablement à conserver à court terme :

| Classe/zone | Raison |
|---|---|
| `ParseMessagesOperation`, `LinkItem`, wrappers message | Parsing/rendu forum lourd |
| `MultisManager` | Comptes, cookies, compte courant |
| `MPStorage` | Bookmarks/MP/AQ historiques |
| `BlackList` | BL/WL persistées |
| `SmileyCache` | Cache smileys |
| `k`, `ThemeManager`, constantes legacy | URLs, thème, compatibilité |
| Services search/reply bridgés | Traitement/réseau legacy encore utile |

Zones ObjC à auditer avant suppression :

| Zone | Hypothèse |
|---|---|
| Controllers XIB Plus secondaires (`Aide`, `Infos`, `Feedback`, `Pay`) | Peut-être plus exposés dans SwiftUI, mais à confirmer |
| Controllers liste legacy (`ForumsTableViewController`, `TopicsTableViewController`, `FavoritesTableViewController`) | Remplacés côté UI, mais peuvent contenir logique encore référencée |
| `PlusSettingsViewController` / `InAppSettingsKit` | Probablement hors flux SwiftUI, usage projet à vérifier |
| `SDWebImage.m` legacy | À garder tant que des écrans ObjC l’utilisent |

---

## Audit Objective-C/XIB — 2026-05-01

Audit statique réalisé sans suppression. Sources croisées :

- Références Swift vers `NSClassFromString`, `LegacyLoaderRuntime`, `UIViewControllerRepresentable`.
- XIB présents dans `Classes/`.
- XIB et controllers encore référencés dans `SuperHFRplus.xcodeproj/project.pbxproj`.

### KEEP_TREATMENT — traitement Objective-C encore utilisé

Ces éléments restent dans le scope utile. Ils peuvent être isolés derrière protocoles Swift, mais ne doivent pas être supprimés.

| Zone | Référence Swift actuelle | Raison |
|---|---|---|
| `MultisManager` | `ObjCLegacyAccountsManager`, `ObjCAccountSessionService`, `AppSettingsView`, `ReplyService`, `AQPlusView`, `MessagesView` | Compte courant, cookies, hash, session |
| `MPStorage` / `Bookmark` | `ObjCMPStorageBridge`, `BookmarksPlusView`, `MessagesView`, settings MPStorage | Bookmarks, drapeaux, stockage historique |
| `BlackList` | `AppSettingsView`, `MessagesView`, `ParseMessagesOperation`, `LinkItem` | BL/WL, rendu filtré, actions contextuelles |
| `SmileyCache` | `ReplySmileyCatalog`, `AnswerView`, `MessagesView`, `UserProfileView` | Smileys favoris et cache |
| `MessagesTableViewController` | `ObjCTopicPageLoader`, `ObjCTopicSearchService`, `ObjCFavoritePostFilterService` | Worker parsing/rendu topic, metadata actions, poll/search |
| `ParseMessagesOperation` / `LinkItem` | via `MessagesTableViewController` wrapper | Parsing posts et metadata legacy |
| `FavoritesTableViewController` | `ObjCFavoritesLoader` | Worker chargement favoris |
| `ForumsTableViewController` | `ObjCForumsLoader` | Worker chargement catégories/forums |
| `TopicsTableViewController` | `ObjCForumTopicsLoader` | Worker chargement topics |
| `HFRMPViewController` | `ObjCMPTopicsLoader` | Worker chargement liste MP |
| `TopicsSearchViewController` | `ObjCForumSearchService` | Worker recherche forum |
| `FilterPostsQuotes` | `ObjCFavoritePostFilterService` | Filtre posts favoris |
| `ThemeManager` / `ThemeColors` / `k` | `AppSettingsView`, wrappers, rendu legacy | Thème, URLs, compatibilité globale |
| `HFRAlertView` | `MessagesView` | Toasts legacy depuis actions WebView |
| `SDWebImage` / `SDAnimatedImageView` | `AnswerView` fallback GIF/animation + legacy ObjC | Animation image/GIF et compatibilité |

### WRAP — garder mais réduire le couplage

Ces éléments sont utiles, mais leur exposition Swift devrait être documentée et resserrée avant toute réduction.

| Zone | Action recommandée |
|---|---|
| `MessagesTableViewController` comme worker | Extraire/documenter le contrat Swift : `fetchContentForTopicURL`, `swiftMessageActionsByIndex`, poll, search form, render favorite filter |
| `MultisManager` | Stabiliser un unique adaptateur session/compte ; éviter les appels directs dispersés |
| `MPStorage` | Garder `ObjCMPStorageBridge` comme façade unique pour bookmarks/settings, puis auditer les autres appels directs |
| `BlackList` | Centraliser lecture/toggle BL/WL pour éviter doublons `NSClassFromString` et appels directs |
| Search ObjC (`TopicsSearchViewController`) | Conserver comme service worker tant que le parser/form POST n’est pas réécrit |
| `SDWebImage` shim | Documenter les call sites restants et décider si SwiftUI peut tout couvrir via loaders natifs |

### PORT_UI — UI legacy potentiellement encore visible à confirmer

Ces écrans/controllers existent encore dans le projet et doivent être confirmés côté produit. S’ils restent visibles, ils doivent être portés SwiftUI ; sinon ils passent en quarantaine.

| Zone | XIB/controller | Statut produit actuel |
|---|---|---|
| Aide | `AideViewController.xib` | Route SwiftUI non exposée actuellement ; décider ajout ou abandon |
| Infos app | `InfosViewController.xib`, `InfoTableViewCell.xib` | Route SwiftUI non exposée actuellement ; décider remplacement par `StaticInfoPageView`/Plus |
| Feedback | `FeedbackViewController.xib`, `FeedbackTableViewCell.xib` | Route SwiftUI non exposée actuellement ; décider utile ou abandon |
| Pay/abonnement | `PayViewController.xib` | Usage actuel à confirmer |
| Configuration / liens profil secondaires | `ConfigurationViewController.xib`, `PersonnalLinkViewController.xib` | `UserProfileView` ouvre les liens externes ; parité fine à confirmer |
| Filtres rapides forum | pas un XIB dédié | Manque SwiftUI G02 confirmé |

### QUARANTINE — probablement hors flux SwiftUI principal

À ne pas supprimer encore : ils restent dans le projet Xcode et peuvent être référencés par des chemins legacy non testés.

| Zone | Raison |
|---|---|
| `PlusTableViewController`, `PlusCellView.xib`, `PlusTableViewWrapper` | Plus principal remplacé par `PlusHomeView`; wrapper encore compilé mais pas routé dans SwiftUI actuel |
| `PlusSettingsViewController`, `SettingsView.xib`, `InAppSettingsKit` | Settings principal remplacé par `AppSettingsView`; vérifier absence de route legacy avant déclassement |
| `IdentificationViewController`, `CompteViewController`, cellules compte | Flux SwiftUI compte présent ; vérifier absence de fallback UIKit |
| `ProfilViewController`, `PollTableViewController`, `AlerteModoViewController` | Remplacés par SwiftUI ; rester en quarantaine jusqu’à validation runtime |
| `BookmarksTableViewController`, `AQTableViewController`, listes BL/WL UIKit | Remplacés côté Plus/Settings ; restent comme legacy compilé |
| `AddMessageViewController`, `SmileyViewController`, `RehostImageViewController` | Composer SwiftUI actif ; `ObjCMessageComposerView` existe mais non routé |
| XIB cellules legacy (`TopicCellView`, `TopicMPCellView`, `ForumCellView`, `FavoriteCellView`, etc.) | Probablement requis seulement par controllers legacy compilés |
| `MainWindow.xib`, `MainWindow-iPad.xib`, `TabBarController` | Root SwiftUI actif, mais app delegate legacy encore présent |
| `HFRDebugViewController` | Debug legacy, hors portage UI produit |

### DELETE_LATER — aucun candidat immédiat

Aucun fichier n’est proposé à la suppression dans cette passe. Les XIB sont encore référencés dans `project.pbxproj`, et plusieurs controllers legacy servent encore de workers ou restent compilés. La prochaine étape est une validation runtime des routes, puis seulement des petits PR/commits de quarantaine ou retrait ciblé.

### Risques observés

1. Certains controllers UIKit remplacés par SwiftUI restent utilisés comme workers de données (`FavoritesTableViewController`, `ForumsTableViewController`, `TopicsTableViewController`, `HFRMPViewController`, `MessagesTableViewController`, `TopicsSearchViewController`).
2. Plusieurs bridges utilisent `NSClassFromString`; la suppression d’un fichier peut compiler jusqu’à casser au runtime.
3. Le projet Xcode embarque toujours tous les XIB legacy dans les ressources, donc l’absence de route SwiftUI ne prouve pas l’inutilité.
4. `PlusTableViewWrapper`, `MessageViewWrapper` et `ObjCMessageComposerView` existent encore comme wrappers Swift, mais l’audit statique ne montre pas de route active vers eux.

### Validation routes SwiftUI — 2026-05-01

Validation statique des routes SwiftUI actives, sans lancement simulateur.

| Entrée | Route active | Conclusion |
|---|---|---|
| Root app | `HFRswiftApp` → `RootTabView` | SwiftUI root actif |
| Onglet Forums | `CategoriesListView` / `ForumTopicsListView` | Pas de route UIKit directe |
| Onglet Favoris | `FavoritesListView` | UI SwiftUI ; `FavoritesTableViewController` reste worker de données |
| Onglet Messages | `MPListView` | UI SwiftUI ; `HFRMPViewController` reste worker de données |
| Onglet Plus | `NavigationStack { PlusHomeView() }` | UI SwiftUI ; `PlusTableViewWrapper` non routé |
| iPad/sidebar | `selectedTabContent` vers vues SwiftUI | Pas de route `MainWindow-iPad.xib` dans root SwiftUI |
| Plus > Réglages | `AppSettingsView` | Remplace `PlusSettingsViewController` / `SettingsView.xib` dans ce flux |
| Plus > Recherche forum | `ForumSearchView` | UI SwiftUI ; `TopicsSearchViewController` reste worker service |
| Plus > Bookmarks | `BookmarksPlusView` | Remplace UI bookmarks UIKit dans ce flux |
| Plus > AQ | `AQPlusView` | Remplace UI AQ UIKit dans ce flux |
| Plus > Crédits/Charte | `StaticInfoPageView` | Remplace crédits/charte UIKit pour ces deux pages |
| Plus > Suppression compte | `DeleteAccountMailComposeView` | UIKit système `MFMailComposeViewController`, acceptable |
| Topic depuis listes | `MessagesView` | UI SwiftUI ; `MessagesTableViewController` reste worker parser/rendu |
| Répondre/éditer/MP | `AnswerView` | `ObjCMessageComposerView` commenté et non routé |
| Profil | `UserProfileView` | Remplace `ProfilViewController` dans le flux SwiftUI |
| Sondage | `PollSheet` / `PollView` | Remplace `PollTableViewController` dans le flux SwiftUI |
| Alerte modération | `ModerationAlertComposerView` | Remplace `AlerteModoViewController` dans le flux SwiftUI |

Wrappers Swift non routés par la navigation SwiftUI active :

| Wrapper | Statut |
|---|---|
| `PlusTableViewWrapper` | Fallback/debug uniquement d’après commentaire ; aucun usage trouvé |
| `MessageViewWrapper` | Aucun usage trouvé |
| `ObjCMessageComposerView` | Code commenté ; aucun usage actif |
| `ObjCViewControllerHost` | Défini mais aucun usage actif depuis la migration `ForumSearchView` |

Conséquence : les XIB Plus/settings/login/profil/poll/alerte/composer/bookmarks/AQ peuvent rester en `QUARANTINE`, mais ne doivent pas être supprimés avant validation runtime réelle et audit `project.pbxproj`.

Validation smoke simulateur effectuée ensuite :

| Étape | Résultat |
|---|---|
| Build `HFRswift` Debug iPhone 17 Pro iOS 26.4 | `BUILD SUCCEEDED` |
| Installation simulateur | OK |
| Lancement bundle `hfrplus.red.super` | OK, PID retourné |
| Capture écran automatique | Non concluante : `simctl io screenshot` a bloqué et a été interrompu |

Conclusion smoke : le binaire SwiftUI construit, s’installe et se lance. Cette validation ne remplace pas une navigation manuelle écran par écran ; elle suffit seulement à confirmer l’absence de crash immédiat au lancement après classification.

---

## Tracker mis à jour

| ID | Statut | Critère de sortie actuel | Priorité |
|---|---|---|---|
| G02 | NotStarted | Filtres rapides forum disponibles ou décision d’abandon documentée | P1 |
| G09 | InProgress | Contrat session/compte documenté, chemins login/logout/switch validés manuellement | P0 |
| G10 | NotStarted | Checklist startup/background validée | P0 |
| G12 | InProgress | Inventaire ObjC utilisé + classification réduction validé par lancement manuel | P0 |
| G17 | InProgress | Liste des XIB/NIB encore visibles ou supprimables validée par lancement manuel | P0 |
| G26 | InProgress | Décision parité thème avancée : porter, simplifier ou abandonner | P1 |
| G27 | NotStarted | Aide portée ou retirée du scope produit | P1 |
| G28 | NotStarted | Infos/feedback portés ou remplacés | P1 |
| G29 | NotStarted | Pay/abonnement confirmé utile ou dépriorisé | P1 |
| G11 | NotStarted | Décision iPad documentée | P2 |
| G15 | Deferred | Previews ajoutées opportunistiquement | P2 |
| G30 | NotStarted | Passe UI finale Liquid Glass/cohérence | P2 |

---

## Plan de resserrage des façades ObjC

Objectif : réduire les appels ObjC dispersés avant toute suppression. Cette étape ne supprime rien ; elle rend les dépendances explicites et testables manuellement.

### Lot W1 — `BlackList`

État observé :

- Appels directs dans `AppSettingsView.swift` pour charger/ajouter/supprimer BL/WL.
- Bridges séparés dans `MessagesView.swift` pour état et toggle BL/WL.
- Usage interne ObjC dans `ParseMessagesOperation` et `LinkItem` pour rendu/filtrage.

Action recommandée :

| Étape | Résultat attendu |
|---|---|
| Créer une façade Swift unique `ProfileFilterListManaging` | Lecture BL/WL, ajout, suppression, toggle, état |
| Remplacer les appels Swift directs à `BlackList.shared()` | `AppSettingsView` et `MessagesView` passent par la façade |
| Garder les usages ObjC internes | `ParseMessagesOperation` / `LinkItem` restent inchangés |
| Documenter la frontière | Swift ne connaît plus les selectors ObjC BL/WL hors façade |

### Lot W2 — `MPStorage`

État observé :

- `ObjCMPStorageBridge` couvre déjà une partie : init/reset, parse bookmarks, count, get, remove, reload.
- `MessagesView.swift` accède encore à `MPStorage` via `NSClassFromString` pour bookmarks/action post.
- `AppSettingsView.swift` utilise la façade existante pour init/reload.

Action recommandée :

| Étape | Résultat attendu |
|---|---|
| Étendre `LegacyMPStorageManaging` aux opérations bookmarks post-level | Plus d’accès direct `NSClassFromString("MPStorage")` dans `MessagesView` |
| Centraliser la création `Bookmark` | Une seule façade sait construire/ajouter un bookmark ObjC |
| Garder `MPStorage` ObjC | Traitement historique conservé |

### Lot W3 — `MessagesTableViewController` worker

État observé :

- Utilisé comme worker pour charger/rendre topic, actions message, sondage, search form.
- Utilisé par `ObjCTopicSearchService` et `ObjCFavoritePostFilterService` comme renderer/service.
- Contient encore du code UI legacy interne, mais les routes SwiftUI utilisent `MessagesView`.

Action recommandée :

| Étape | Résultat attendu |
|---|---|
| Documenter le contrat public Swift attendu | `fetchContentForTopicURL`, `cancelFetchContent`, `swiftMessageActionsByIndex`, poll/search fields |
| Éviter toute nouvelle dépendance à ses méthodes UI legacy | Pas de nouveau chemin `presentViewController` via wrapper |
| À moyen terme, extraire un worker ObjC non-UI | Seulement quand la surface utilisée est stable |

### Lot W4 — Session/compte `MultisManager`

État observé :

- `ObjCLegacyAccountsManager` et `ObjCAccountSessionService` existent.
- Appels depuis `AccountsStore`, `ReplyService`, `AQPlusView`, `AppSettingsView`, `MessagesView`.

Action recommandée :

| Étape | Résultat attendu |
|---|---|
| Confirmer que tous les flux passent par `LegacyAccountsManaging` / `AccountSessionService` | Pas d’accès dispersé à `MultisManager` depuis Swift |
| Documenter les invariants | compte courant, cookies forcés, hash_check, suppression compte |
| Valider manuellement switch/logout/login | Réduction du risque startup/background |

### Lot W5 — `SmileyCache`

État observé :

- Façade `ReplySmileyCacheBridge` utilisée par composer.
- Accès séparés dans `MessagesView` et `UserProfileView` pour favoris smileys.

Action recommandée :

| Étape | Résultat attendu |
|---|---|
| Unifier les opérations favoris smileys dans une façade Swift | `AnswerView`, `MessagesView`, `UserProfileView` partagent la même surface |
| Garder `SmileyCache` ObjC | Cache existant conservé |

### Ordre recommandé

1. W1 `BlackList`, petit et visible.
2. W2 `MPStorage`, nécessaire avant toute réduction bookmarks.
3. W4 session/compte, avant cleanup runtime.
4. W5 `SmileyCache`, opportuniste.
5. W3 `MessagesTableViewController`, plus risqué, à faire seulement après stabilisation.

---

## Prochaine analyse recommandée

1. Faire un audit statique des références ObjC/XIB encore dans le projet Xcode.
2. Croiser avec les routes SwiftUI actuelles (`RootTabView`, `PlusTab`, `MessagesView`, sheets).
3. Produire une table `KEEP / WRAP / PORT / QUARANTINE / DELETE-LATER`.
4. Ne rien supprimer dans la première passe ; ajouter seulement des notes de scope et éventuellement des commentaires/doc.
5. Ensuite traiter les derniers manques UI P1, en commençant par G02 si l’usage est confirmé.
