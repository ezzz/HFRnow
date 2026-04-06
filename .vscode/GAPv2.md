# GAPv2 — Analyse des écarts HFRswift vs SuperHFRplus

> Révision complète basée sur l'inventaire exhaustif des fichiers XIB et controllers ObjC, avec vérification ligne par ligne des implémentations Swift existantes.

---

## Décisions structurantes (héritées et à jour)

1. `OfflineMessagesTableViewController` est déprécié et ne doit pas être porté en SwiftUI.
2. `MessagesView` doit utiliser le rendu WebView fichier-local (pas de mode HTML inline) pour préserver le chargement des CSS/ressources locales.
3. `OfflineStorage` ne doit pas être utilisé pour les flux offline-topic dépréciés ; en dehors du rendu des messages il reste opt-in et temporaire.
4. Priorité de test : socle de sécurité minimal sur les wrappers ObjC et les politiques critiques d'ouverture/navigation (feature-first).
5. Chaque écran SwiftUI migré doit avoir `#Preview` avec données mock (normal, loading, empty, error) quand c'est possible.
6. Les Settings doivent supprimer la dépendance à l'ancienne COTS (`InAppSettingsKit`) et passer aux APIs SwiftUI modernes.
7. La parité iPad est de priorité inférieure ; première étape = étude nécessité/impact.
8. Cible finale : toute l'UI est SwiftUI ; Objective-C conservé uniquement pour les couches de traitement non-UI.
9. L'usage XIB/NIB doit être supprimé des flux migrés dans `HFRswift` ; aucune nouvelle UI XIB/NIB ne doit être introduite.
10. Focus implémentation actuel : parité `Répondre` et actions contextuelles niveau message ; modernisation Settings différée mais non supprimée.
11. Périmètre sprint actions contextuelles limité à quote/profil et hardening associé ; autres actions par-post explicitement différées.
12. G19 fermé : actions contextuelles quote/profil incluent un chemin fallback UIKit, validées sur vrais posts ; actions optionnelles par-post restent différées par scope.
13. Pour G04, la réorganisation catégorie/topic est explicitement hors scope (coût > bénéfice) et remplacée par fold/unfold de section dans les Favoris.
14. G06 est passé d'action-porting à hardening : le menu popup Swift couvre la majorité des actions legacy.

---

## Méthode d'analyse v2

Cette révision est fondée sur :
- Inventaire exhaustif des 44 fichiers XIB dans `SuperHFRplus/XIB/`
- Lecture des controllers ObjC associés (`.m` / `.h`) dans `Classes/`
- Vérification des 23 fichiers Swift dans `HFRswift/Swift/`
- Vérification des wrappers dans `HFRswift/Wrapped/`
- Recoupement avec le GAP v1 pour les items déjà traités

---

## Inventaire XIB / Controllers

### Navigation principale

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `MainWindow.xib` | `AppDelegate` + `TabBarController` | Initialisation app, fenêtre root, 4 onglets (Forums, Favoris, Messages, Plus) |
| `MainWindow-iPad.xib` | `AppDelegate` variante iPad | Layout iPad split-view |

**Statut Swift** : `HFRswiftApp.swift` + `MainWindow.swift` (RootTabView). Onglets présents. `TabBarController` ObjC éliminé du flux SwiftUI.

---

### Forums et sujets

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `ForumCellView.xib` | `ForumCellView` (cell custom) | Affichage cellule forum avec info catégorie |
| `TopicCellView.xib` | `TopicCellView` (cell custom) | Cellule sujet avec nb posts/auteur |
| `SimpleCellView.xib` | `SimpleCellView` (cell custom) | Cellule générique réutilisable |
| `TopicSearchCellView.xib` | `TopicSearchCellView` (cell custom) | Cellule résultat de recherche |
| `TopicMPCellView.xib` | `TopicMPCellView` (cell custom) | Cellule sujet MP |

**Controllers associés** :

| Controller | Fonctions clés | Statut Swift |
|-----------|---------------|-------------|
| `ForumsTableViewController` | `viewDidLoad`, `numberOfRowsInSection`, `cellForRowAtIndexPath`, `didSelectRowAtIndexPath`, filtres rapides (Favoris/Suivis/Lus/Tous via long-press) | Migré : `CategoriesListViewModel` + `MainWindow.swift`. Filtres rapides absent (**G02**) |
| `TopicsTableViewController` | `viewDidLoad`, `numberOfRowsInSection`, `cellForRowAtIndexPath`, `didSelectRowAtIndexPath`, actions rapides (première/dernière page, copier lien), pagination | Migré : `MainWindow.swift` + `Common.swift`. Actions rapides validées (**G03 Done**) |
| `TopicsSearchViewController` | Recherche texte, affichage résultats en `UITableView`, `didSelectRowAtIndexPath` | **Partiellement** : enveloppé dans `ObjCViewControllerHost` dans `PlusTab.swift`. Pas de UI native Swift (**G21**) |

---

### Messages privés

| Controller | Fonctions clés | Statut Swift |
|-----------|---------------|-------------|
| `HFRMPViewController` | `viewDidLoad`, `fetchContent` (callback Swift), `didSelectRowAtIndexPath`, actions rapides (première/dernière/page/copie), `UITableViewDelegate` | Migré : `MPListView.swift` + `MPListViewModel`. Actions validées (**G05 Done**) |

---

### Composition de message

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `AddMessageViewController.xib` | `AddMessageViewController` | `viewDidLoad`, `initWithNibName`, `segmentFilterAction` (smiley/image), `loadSmileys` (pagination), `initData`, `updateExpandCompressSmiley`, `updateExpandCompressRehostImage`, `resizeViewWithKeyboard`, insertion smiley/image/GIF (Giphy), gestion undo/redo, brouillon |
| `SmileyViewController.xib` | `SmileyViewController` | `viewDidLoad`, `changeDisplayMode` (3 modes : défaut/recherche/favoris), `loadSmileys`, `fetchSmileys`, `updateTheme`, `UICollectionViewDelegate`, `UITableViewDelegate` pour résultats recherche |
| `SmileyCodeTableView.xib` | `SmileyCodeTableViewController` | Liste des codes smileys, `UITableViewDelegate/DataSource` |
| `SmileyCodeCellView.xib` | `SmileyCodeCellView` | Cellule affichage code smiley |
| `RehostImageViewController.xib` | `RehostImageViewController` | `updateExpandButton`, `getDisplayHeight`, `actionReduce`, `updateTheme`, `UIImagePickerControllerDelegate`, `UICollectionViewDelegate/DataSource`, upload avec progression, réhébergement 400px |
| `RehostCell.xib` | `RehostCell` | Cellule upload image individuelle |
| `AccessoryView.xib` | (Vue accessoire clavier) | Barre d'accessoire pour le champ texte |

**Statut Swift** :
- `AnswerView.swift` : composer SwiftUI natif avec smileys (communs/favoris), insertion image, GIF, quote template, undo/redo, haptics, erreurs nettoyées.
- `ReplyComposer.swift`, `ReplySmileyCatalog.swift`, `ReplyService.swift` : couches service.
- Intégration Giphy : **statut incertain** — à vérifier si l'insertion GIF via Giphy est couverte ou non (**G18 à préciser**).
- `ObjCMessageComposerView.swift` : bridge commenté, non actif.

---

### Authentification et comptes

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `IdentificationViewController.xib` | `IdentificationViewController` | Formulaire login : `pseudoField`, `passField`, action `connexion`, méthodes `finish`/`finishOK`, pattern délégué |
| `CompteViewController.xib` | `CompteViewController` | `viewDidLoad`, `viewWillAppear` (thème), `viewDidAppear` (rafraîchissement), `addCompte`, `refreshComptes`, login/logout, `UITableViewDelegate` (ajout, suppression de comptes) |
| `CompteTableViewCell.xib` | `CompteTableViewCell` | Cellule compte avec avatar/pseudo |

**Statut Swift** :
- `AccountsStore.swift`, `AddAccountView.swift`, `AccountMenuViews.swift`, `AccountSessionService.swift`, `LoginService.swift` : couches service et vues partielles.
- **Formulaire login** : `LoginService.swift` existe (backend), mais UI native SwiftUI pour `IdentificationViewController` absente ou non identifiée (**G24**).
- Gestion multi-comptes partiellement couverte (**G09 NotStarted**).

---

### Favoris

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `FavoritesTableViewController.xib` | `FavoritesTableViewController` | `viewDidLoad`, `viewWillAppear`, `loadDataInTableView`, `numberOfSectionsInTableView`, `cellForRowAtIndexPath` (logique complexe ~1350 lignes), `editingStyleForRowAtIndexPath`, `lastPageAction`, `lastPostAction`, `copyLinkAction`, `textFieldTopicDidChange`, bridge Swift (completion block) |
| `FavoriteCellView.xib` | `FavoriteCellView` | Cellule sujet favori avec catégorie/nb posts |

**Statut Swift** :
- `Favorites.swift` : `FavoritesTopicActionServicing` + `ForumFavoritesTopicActionService` (suppression flag favori, form URL, auth hash).
- Liste complète des favoris avec sections, états colorés, swipe actions : **partiellement** présent via `FavoritesViewModel` (**G04 InProgress**).
- Fold/unfold de section : en place. Réorganisation : hors scope.

---

### Bookmarks

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `BookmarksTableView.xib` | `BookmarksTableViewController` | `UITableViewDelegate`, `UIActionSheetDelegate`, `UITextFieldDelegate` |
| `BookmarksCellView.xib` | `BookmarksCellView` | Cellule marque-page |

**Statut Swift** : `BookmarksPlusView.swift` — implémentation complète avec bridge `MPStorage`, rafraîchissement, gestion erreurs. **Migré**.

---

### Messages Privés (liste)

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `TopicMPCellView.xib` | `TopicMPCellView` | Cellule MP (réutilisée) |

**Statut Swift** : `MPListView.swift` + `MPListViewModel`. **Migré** (**G05 Done**).

---

### Vue de profil utilisateur

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `ProfilViewController.xib` | `ProfilViewController` | `initWithNibName:andUrl`, `profilTableView`, `loadingView`, gestion état chargement, `UITableViewDelegate/DataSource`, fetch HTTP, parsing profil |
| `PersonnalLinkViewController.xib` | `PersonnalLinkViewController` | Liens personnels / contributions utilisateur |

**Statut Swift** : **Absent**. Aucun équivalent SwiftUI trouvé. (**G20**)

---

### AQ (Alertes Qualitay)

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `AQTableView.xib` | `AQTableViewController` | `viewDidLoad`, `numberOfSectionsInTableView`, `tableView:numberOfRowsInSection`, `tableView:cellForRowAtIndexPath`, `tableView:didSelectRowAtIndexPath` |
| `AQCellView.xib` | `AQCellView` | Cellule AQ |

**Statut Swift** : `AQPlusView.swift` — parsing RSS/XML (`AQRSSParserDelegate`), filtrage date/catégorie, détection nouveaux items. **Migré** (via onglet Plus).

---

### Sondages (Polls)

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `PollTableViewController.xib` | `PollTableViewController` | Affichage sondage, vote, `UITableViewDelegate`, `UIAlertViewDelegate` |
| `PollResultTableViewCell.xib` | `PollResultTableViewCell` | Cellule résultat de sondage |

**Statut Swift** : **Absent**. Aucun équivalent SwiftUI. (**G23**)

---

### Listes noire/blanche

Aucun XIB propre — rendu depuis `MessagesTableViewController` popup menu.

| Controller | Fonctions clés |
|-----------|---------------|
| `BlackListTableViewController` | Gestion liste noire : ajout, suppression, affichage |
| `WhiteListTableViewController` | Gestion liste blanche |

**Statut Swift** : `MessagePopupMenuActionKind` définit `.blacklist`/`.whitelist` dans `MessagesView.swift` mais **aucune vue de gestion UI**. (**G22**)

---

### Alerte modo

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `AlerteModoViewController.xib` | `AlerteModoViewController` | `UITextViewDelegate`, saisie et envoi signalement modération |

**Statut Swift** : **Absent**. (**G25**)

---

### Settings et Thème

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `ThemeSettingsViewController.xib` | `ThemeSettingsViewController` | Paramètres thème/apparence |
| `ThemeColorCellView.xib` | `ThemeColorCellView` | Cellule sélecteur couleur |
| `ThemeBrightnessCellView.xib` | `ThemeBrightnessCellView` | Cellule slider luminosité |
| `ColorPickerViewController.xib` | `ColorPickerViewController` | Sélecteur couleur complet |
| `SettingsView.xib` | (Vue settings legacy) | Ancienne UI settings |

**Statut Swift** :
- `AppSettingsView.swift` : 8 variantes icône, sélection thème auto/manuel.
- Personnalisation couleur fine et sélecteur de luminosité : **partiellement absent** — `AppSettingsView` couvre les options de base mais pas l'éditeur de couleur custom. (**G26**)
- `PlusSettingsViewController` dépend encore de `InAppSettingsKit` (**G14 NotStarted**).

---

### Pages statiques et aide

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `CreditsViewController.xib` | `CreditsViewController` | `WKWebView`, `WKNavigationDelegate/WKUIDelegate`, chargement contenu web |
| `AideViewController.xib` | `AideViewController` | `WKWebView`, navigation aide/documentation |
| `InfosViewController.xib` | `InfosViewController` | Informations sur l'application |
| `InfoTableViewCell.xib` | `InfoTableViewCell` | Cellule section info |
| `ConfigurationViewController.xib` | `ConfigurationViewController` (étend `PageViewController`) | Page configuration avec WKWebView |
| `FeedbackViewController.xib` | `FeedbackViewController` (étend `PageViewController`) | Affichage feedback avec `feedTableView`, `loadingView` |
| `FeedbackTableViewCell.xib` | `FeedbackTableViewCell` | Cellule feedback |

**Statut Swift** :
- `StaticInfoPageView.swift` : enum `Kind` (`.credits`, `.charter`), affichage contenu web.
- Crédits : **migré** via `StaticInfoPageView`.
- Aide (`AideViewController`) : **absent** en Swift. (**G27**)
- Infos app, Feedback, Configuration : **absents** en Swift.

---

### Divers

| XIB | Controller | Fonctions clés |
|-----|-----------|---------------|
| `PopupViewController.xib` | `PopupViewController` | Dialogue modal/popup générique |
| `PlusCellView.xib` | `PlusCellView` | Cellule menu Plus |
| `HFRDebugViewController.xib` | `HFRDebugViewController` | Panneau de debug (non à porter) |
| `PayViewController.xib` | `PayViewController` | Vue abonnement/paiement |

---

## Fichiers Swift — inventaire et usage

| Fichier | Rôle | Complet ? |
|---------|------|----------|
| `HFRswiftApp.swift` | Entry point `@main`, injection `HFRplusAppDelegate` | Oui |
| `MainWindow.swift` | RootTabView, `CategoriesListViewModel`, `ForumTopicsListViewModel` | Oui |
| `MessagesView.swift` | Affichage thread, `MessagePopupMenuActionKind`, menu contextuel, bridge ObjC | Partiel (G06) |
| `MPListView.swift` | Liste MP, `MPListViewModel` | Oui |
| `AnswerView.swift` | Composer SwiftUI (smileys, images, quote, undo/redo) | Oui (G07/G18 Done) |
| `PlusTab.swift` | Menu Plus, `PlusHomeView`, wrappers ObjC restants | Partiel (G08) |
| `BookmarksPlusView.swift` | Marque-pages, bridge `MPStorage` | Oui |
| `AQPlusView.swift` | AQ RSS, filtrage, détection nouveautés | Oui |
| `Favorites.swift` | `FavoritesTopicActionService`, suppression favori | Partiel (G04) |
| `AppSettingsView.swift` | Settings icône/thème | Partiel (G14/G26) |
| `ReplyComposer.swift` | État composer, `ReplyComposerPanel`, insertion texte | Oui |
| `ReplySmileyCatalog.swift` | Cache smileys, protocole chargement | Oui |
| `ReplyService.swift` | `ReplyPostingService`, pipeline d'envoi | Oui |
| `AccountMenuViews.swift` | Sélecteur compte UI, `AccountAvatarView` | Oui |
| `AccountSessionService.swift` | Session auth, suivi session | Partiel (G09) |
| `AccountsStore.swift` | Persistance comptes, bridge `MultisManager` | Partiel (G09) |
| `AddAccountView.swift` | UI ajout compte | Oui |
| `LoginService.swift` | Orchestration login/logout | Partiel (G24) |
| `MainToolbar.swift` | Barre de navigation, contrôles titre | Oui |
| `ObjCMessageComposerView.swift` | Bridge `AddMessageViewController` (commenté, inactif) | Non actif |
| `StaticInfoPageView.swift` | Pages statiques (crédits, charte) | Partiel (G27) |
| `Common.swift` | Utilitaires partagés, thème, routing schemes, `showPopupMenu` | Oui |
| `LiquidGlass.swift` | Effet verre liquid glass | Oui |

---

## Matrice des écarts — version 2

> Champs : (1) Description utilisateur · (2) Implémentation ObjC · (3) Statut SwiftUI · (4) Dépendances ObjC non-UI · (5) Risques · (6) Effort S/M/L · (7) Priorité P0/P1/P2

### Items hérités de GAP v1 (statuts mis à jour)

| ID | (1) Description | (2) ObjC | (3) Swift | (4) Dépendances | (5) Risques | (6) | (7) |
|----|----------------|----------|-----------|----------------|------------|-----|-----|
| G01 | Navigation catégories/forums | `TabBarController`, `ForumsTableViewController`, XIB | **Done** — `CategoriesListView` + `ForumTopicsListView` SwiftUI natifs | `Forum`, `k` | Risque résiduel : parité backend/regression | M | P0 |
| G02 | Filtres rapides forum (Favoris/Suivis/Lus/Tous) | `ForumsTableViewController` long-press ligne 1090-1100 | **NotStarted** — absent du flux SwiftUI | Logique URL forum `k` | Comportement power-user manquant | M | P1 |
| G03 | Actions rapides sujet (première/dernière/page/copier) | `TopicsTableViewController` actions | **Done** — validé pour contextes forum/favoris/MP | Modèle pagination URL topic | Risque résiduel : edge cases on-device | M | P0 |
| G04 | Favoris avancé (super favori/swipe/fold-unfold) | `FavoritesTableViewController` (~1700 lignes) | **InProgress** — super favoris, swipe, fold/unfold présents ; réorganisation hors scope | `FilterPostsQuotes`, données favoris | Edge cases heavy-user | M | P0 |
| G05 | MP actions rapides | `HFRMPViewController` | **Done** — première/dernière/page/copie validés | `MPStorage` | Validation UX on-device | M | P0 |
| G06 | Interactions WebView topic (schemes/popup/liens internes) | `MessagesTableViewController` `WKNavigationDelegate` | **InProgress** — routing couvert, menu popup Swift quasi-complet ; edge cases restants | `ParseMessagesOperation`, `BlackList`, `SmileyCache`, `MPStorage` | Dérive parité edge behaviors | M | P0 |
| G07 | Flux réponse fiable (auth/hash/cookies/form post/erreurs) | Legacy composer + pipeline | **Done** — tests fiabilité passent | `MultisManager`, `HFRplusAppDelegate.hash_check` | Régressions posting/session | L | P0 |
| G08 | Parité routes Plus (compte/search/bookmarks/AQ/settings/credits/charte/suppression) | `PlusTableViewController` routing | **NotStarted** — wrapper UIKit actif ; pas de SwiftUI natif | Services compte/session + AQ | Perte routes si wrapper retiré trop tôt | M | P1 |
| G09 | Session multi-compte stable | `MultisManager` | **NotStarted** — fort couplage depuis Swift, non validé | `MultisManager` | Dérive état session, problèmes threading | M | P0 |
| G10 | Parité lifecycle startup/background | `HFRplusAppDelegate didFinishLaunchingWithOptions` | **NotStarted** — non validé | `MultisManager`, `MPStorage`, `BlackList`, `SmileyCache` | Effets de bord startup/background | M | P1 |
| G11 | Split/master-detail iPad | `MainWindow-iPad.xib`, branche iPad delegate | **NotStarted** | N/A | Gap UX iPad. Priorité basse. | M | P2 |
| G12 | Hardening frontière interop (exposer uniquement les pièces ObjC non-UI nécessaires) | Bridging header large | **NotStarted** | `MultisManager`, `MPStorage`, `k` | Fragilité build, ralentissement migration | M | P0 |
| G13 | Socle tests minimal sur wrappers/politiques | Wrapped classes + controllers ObjC appelés depuis Swift | **InProgress** — baseline wrapper + popup/action policy tests ; chemins bridge-heavy à renforcer | Dépendances service/controller wrappées | Régressions possibles dans bridges action | S | P0 |
| G14 | Migration Settings : remplacer COTS legacy | `PlusSettingsViewController` utilise `InAppSettingsKit` | **NotStarted** | Préférences, thème, services compte | Dépendance COTS bloquante | M | P1 |
| G15 | Previews SwiftUI avec données mock pour écrans migrés | N/A legacy | **NotStarted** | Services mock et fixtures | Itération UI plus lente | S | P1 |
| G16 | Cache offline topic déprécié ne pas porter | `OfflineMessagesTableViewController` | **LockedOut** — hors scope explicite | Aucune | Effort inutile si réintroduit | S | P0 |
| G17 | Supprimer XIB/NIB des flux migrés HFRswift | Controllers UIKit legacy + XIBs | **NotStarted** — wrappers dépendent encore des chemins UIKit/XIB | N/A (concern UI) | Coût maintenance et divergence | L | P1 |
| G18 | Parité composer réponse (smileys défaut/favoris/image/quote) | `AddMessageViewController`, `SmileyViewController`, `RehostImageViewController`, `QuoteMessageViewController` | **Done** — smileys communs/favoris, insertion image/réhébergement 400px, GIF, quote template, undo/redo, haptics, erreurs | `ReplyService`, `AccountSessionService`, `SmileyCache`, `RehostImage` | Risque résiduel : fiabilité automatisée (G07) | L | P0 |
| G19 | Actions contextuelles niveau message (quote post, ouvrir profil) | Schemes popup + `showMenuCon` dans `MessagesTableViewController` | **Done** — schemes gérés en Swift, menu contextuel quote/profil câblé, fallback UIKit | Champs modèle message parsé (`urlQuote`, `urlProfil`, `MPUrl`) | Risque résiduel : actions optionnelles différées par scope | M | P0 |

---

### Nouveaux écarts identifiés par l'analyse XIB (G20–G28)

| ID | (1) Description | (2) ObjC | (3) Swift | (4) Dépendances | (5) Risques | (6) | (7) | Références concrètes |
|----|----------------|----------|-----------|----------------|------------|-----|-----|----------------------|
| G20 | Vue de profil utilisateur (pseudo, stats, historique, liens) | `ProfilViewController` + `PersonnalLinkViewController` : `initWithNibName:andUrl`, `profilTableView`, `loadingView`, `UITableViewDelegate/DataSource`, fetch HTTP, parsing | **Absent** en SwiftUI — aucun équivalent trouvé | Parsing réponse HTTP profil, service fetch | Fonctionnalité visible depuis menu popup message (lien "Profil") ; gap direct dans flux migré | M | P1 | `Classes/ProfilViewController.h`, `HFRswift/Swift/MessagesView.swift` (action `.profile`) |
| G21 | Recherche forum native SwiftUI | `TopicsSearchViewController` : recherche texte, résultats `UITableView`, `didSelectRowAtIndexPath` | **Partiellement** — `ObjCViewControllerHost(TopicsSearchViewController)` dans `PlusTab.swift` ; pas de UI native Swift | Service search ObjC | Maintenance XIB maintenue ; pas de cohérence thème/navigation Swift | M | P2 | `HFRswift/Swift/PlusTab.swift:25-28`, `Classes/TopicsSearchViewController.m` |
| G22 | Gestion UI liste noire / liste blanche | `BlackListTableViewController` / `WhiteListTableViewController` : ajout, suppression, affichage | **Absent** — `.blacklist`/`.whitelist` définis dans `MessagePopupMenuActionKind` mais aucune vue de gestion | `BlackList` (ObjC service) | L'action "Blacklister" dans le menu popup ne peut ouvrir aucune liste de gestion | S | P2 | `HFRswift/Swift/MessagesView.swift` (MessagePopupMenuActionKind), `Classes/BlackList.h` |
| G23 | Affichage et vote de sondages | `PollTableViewController` : affichage sondage, vote, `UITableViewDelegate`, `UIAlertViewDelegate`; `PollResultTableViewCell` | **Absent** en SwiftUI | Parsing sondage dans `ParseMessagesOperation` | Les posts avec sondages n'ont aucun rendu de vote | M | P2 | `Classes/PollTableViewController.h`, `Classes/PollResultTableViewCell.h` |
| G24 | Formulaire d'identification (login) SwiftUI natif | `IdentificationViewController` : `pseudoField`, `passField`, action `connexion`, `finish`/`finishOK`, pattern délégué | **Partiel** — `LoginService.swift` couvre le backend ; aucune vue SwiftUI native identifiée pour le formulaire de connexion | `MultisManager`, `AccountSessionService` | Le flux login peut encore reposer sur l'ObjC ; risque de dérive thème/UX | S | P1 | `Classes/IdentificationViewController.h`, `HFRswift/Swift/LoginService.swift`, `HFRswift/Swift/AddAccountView.swift` |
| G25 | Alerte modération (signalement de post) | `AlerteModoViewController` : `UITextViewDelegate`, saisie motif, envoi signalement | **Absent** en SwiftUI | Service envoi modération | L'action "Alerter modo" dans le menu popup ne peut aboutir côté Swift | S | P2 | `Classes/AlerteModoViewController.h` |
| G26 | Personnalisation thème avancée (couleur custom, luminosité) | `ThemeSettingsViewController` + `ThemeColorCellView` + `ThemeBrightnessCellView` + `ColorPickerViewController` : sélecteur couleur complet, slider luminosité | **Partiel** — `AppSettingsView.swift` couvre icône et thème auto/manuel ; éditeur de couleur custom et slider luminosité absents | Préférences thème persistées | Utilisateurs habitués à la personnalisation fine ne trouveront pas les options | M | P1 | `Classes/ThemeSettingsViewController.h`, `Classes/ColorPickerViewController.h`, `HFRswift/Swift/AppSettingsView.swift` |
| G27 | Page d'aide / documentation | `AideViewController` : `WKWebView`, `WKNavigationDelegate`, navigation aide | **Absent** en SwiftUI — `StaticInfoPageView` ne couvre que Credits et Charte | N/A | Aide inaccessible dans le flux SwiftUI | S | P2 | `Classes/AideViewController.h`, `HFRswift/Swift/StaticInfoPageView.swift` |
| G28 | Page d'informations app et feedback | `InfosViewController`, `FeedbackViewController` (étend `PageViewController`) : `feedTableView`, `loadingView` | **Absent** en SwiftUI | Service feedback HTTP | Informations app et remontée feedback inaccessibles | S | P2 | `Classes/InfosViewController.h`, `Classes/FeedbackViewController.h` |

---

## Tracker de progression v2

| ID | Statut | Critère de sortie | Phase cible |
|----|--------|-------------------|-------------|
| G01 | Done | Navigation catégories/forums native SwiftUI, tests baseline validés | S1 |
| G02 | NotStarted | Filtres rapides forum disponibles dans flux SwiftUI | S2 |
| G03 | Done | Actions rapides sujet validées forum/favoris/MP + tests politique | S1 |
| G04 | InProgress | Checklist parité favoris avancés validée | S2 |
| G05 | Done | Parité MP actions rapides validée | S2 |
| G06 | InProgress | Parité complète menu contextuel WebView validée (routing + actions legacy) | S1-S2 |
| G07 | Done | Tests fiabilité réponse passent | S1-S2 |
| G08 | NotStarted | Plus migré sans régression routes | S3 |
| G09 | NotStarted | Service session/compte stable avec tests | S1 |
| G10 | NotStarted | Parité comportement startup/background validée | S3 |
| G11 | NotStarted | Étude nécessité iPad complétée ; implémentation seulement si justifiée | S4 |
| G12 | NotStarted | Frontière bridging réduite et documentée | S0-S1 |
| G13 | InProgress | Tests régression wrapper/politique minimaux en place et exécutés avant push | S0-S2 |
| G14 | NotStarted | Settings ne dépend plus de InAppSettingsKit | S2-S3 |
| G15 | NotStarted | Previews avec données mock ajoutés pour écrans SwiftUI migrés | Continu |
| G16 | LockedOut | Flux OfflineMessages marqué non-portable et bloqué dans le plan | S0 |
| G17 | NotStarted | Aucun chemin d'exécution XIB/NIB ne subsiste dans les flux migrés HFRswift | S2-S4 |
| G18 | Done | Parité Répondre validée on-device (quote/smileys/images/undo-redo/haptics/erreurs) | S1-R |
| G19 | Done | Actions popup contextuelles (quote/profil + fallback) validées ; actions optionnelles différées par scope | S1-R |
| G20 | NotStarted | Vue profil utilisateur native SwiftUI, accessible depuis menu popup et menu Plus | S2 |
| G21 | NotStarted | Recherche forum en UI native SwiftUI (sans `ObjCViewControllerHost`) | S3 |
| G22 | NotStarted | Vues gestion liste noire/blanche accessibles depuis menu Plus et depuis action popup | S3 |
| G23 | NotStarted | Sondages affichés dans vue message ; vote fonctionnel | S3 |
| G24 | InProgress | Formulaire login SwiftUI natif confirmé ou créé ; flux `AddAccountView` complet | S1 |
| G25 | NotStarted | Action "Alerter modo" dans popup ouvre formulaire SwiftUI natif | S3 |
| G26 | NotStarted | Personnalisation couleur custom et luminosité disponibles dans Settings SwiftUI | S2-S3 |
| G27 | NotStarted | Page aide accessible depuis menu Plus en SwiftUI | S3 |
| G28 | NotStarted | Informations app et feedback accessibles en SwiftUI | S3 |

---

## Top priorités v2

### P0 — Blocants ou critiques pour la cohérence du flux principal

1. **G09** — Hardening adaptateur session/compte.
2. **G06** — Validation edge cases WebView et hardening bridge.
3. **G13** — Socle tests régression wrapper/politique.
4. **G04** — Validation edge cases parité favoris avancés.
5. **G12** — Nettoyage frontière bridging.

### P1 — Important pour la complétude utilisateur

6. **G24** — Confirmer/créer formulaire login SwiftUI natif.
7. **G20** — Vue profil utilisateur en SwiftUI.
8. **G26** — Personnalisation thème avancée (couleur/luminosité).
9. **G02** — Filtres rapides forum.
10. **G08** — Migration native SwiftUI des routes Plus.
11. **G14** — Migration Settings hors InAppSettingsKit.

### P2 — Complétude et polish

12. **G21** — Recherche forum native SwiftUI.
13. **G22** — Gestion UI liste noire/blanche.
14. **G23** — Affichage et vote sondages.
15. **G25** — Formulaire alerte modération.
16. **G27** — Page aide.
17. **G28** — Infos app et feedback.
18. **G10** — Parité lifecycle startup/background.
19. **G11** — iPad split-view (après étude nécessité).
20. **G15** — Previews SwiftUI avec données mock.

---

## Prérequis techniques (mis à jour)

1. Guardrail : ne pas porter `OfflineMessagesTableViewController`.
2. Guardrail : aucun usage nouveau `OfflineStorage` sauf obligatoire et explicitement documenté.
3. Définir des adapteurs Swift autour des classes ObjC wrappées et services non-UI.
4. Maintenir un socle de tests minimal : smoke tests wrapper + `TopicOpenPolicy` + régressions lifecycle connues.
5. Politique preview : chaque écran SwiftUI migré reçoit des previews mock quand possible.
6. Remplacer COTS settings (`InAppSettingsKit`) par un stack Settings SwiftUI natif (`Form`, `AppStorage`).
7. Conserver le travail iPad derrière une étude de nécessité dédiée.
8. Maintenir matrice CI pour `HFRswift` sur iPhone en premier ; étendre iPad si l'étude confirme le scope.
9. Conserver le comportement `SuperHFRplus` comme oracle pour les décisions de parité.
10. Tracer la dette de contournement temporaire dans les docs et la supprimer après stabilisation.
11. Définir et appliquer un pattern réutilisable de ligne Topic SwiftUI (comme dans Favoris/MP) pour éviter la dérive UI inter-écrans.
12. Hardener et valider le contrat bridge Swift pour les actions contextuelles par-post (`messageIndex` → `urlQuote`, `urlProfil`) avant de fermer G19.
13. **Nouveau** : Pour les nouveaux écrans G20–G28, définir les protocoles de service ObjC-side à exposer via le bridging header avant d'écrire l'UI SwiftUI.
14. **Nouveau** : Vérifier l'état du flux `IdentificationViewController` → `AddAccountView` pour confirmer si G24 est réellement couvert ou s'il manque une UI native.
