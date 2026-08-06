# HFR-006 - iPad split view

Dernière vérification : 27 juillet 2026, branche `beta`, base version 4.0.2 build 28.

## Statut

HFR-006 et le recadrage issu de la recette iPad sont implémentés dans la copie de travail.

Sur iPad en taille régulière, `RootTabView` coordonne deux présentations exclusives :

- la sidebar de navigation contient directement Catégories, Favoris, Messages, Bookmarks, Alertes Qualitay et les pages de l'ancien onglet Plus ;
- les rubriques à topics utilisent sidebar + liste + détail ;
- les pages directes utilisent seulement sidebar + page, sans panel intermédiaire vide.

Sur iPhone et lorsque l'iPad passe en taille compacte, le `TabView` et le flux liste puis push restent inchangés.

## Architecture retenue

### Un coordinateur unique, deux géométries

```text
RootTabView
├── rubriques à topics : NavigationSplitView à trois colonnes
│   ├── sidebar : rubriques
│   ├── content : liste active
│   └── detail : MessagesView / état vide
└── pages directes : NavigationSplitView à deux colonnes
    ├── sidebar : rubriques
    └── detail : Réglages / Recherche / Crédits / Charte / Suppression
```

Le détail n'est plus alimenté implicitement par des `NavigationLink` présents dans les listes. Toutes les sélections iPad remontent au coordinateur, qui remplace explicitement la racine du panel de droite.

Le passage conditionnel entre deux et trois colonnes conserve la même sélection de sidebar. Il évite que la sortie d'une page directe restaure d'abord un panel `content` vide avant la sidebar.

### Parcours Catégories en deux étapes

Le choix d'une catégorie remplace la liste des catégories par la liste de ses topics dans le panel de gauche. Le panel de droite reste alors disponible pour afficher le topic.

Un bouton retour dans la barre du panel gauche revient à la liste des catégories. Un changement de sous-forum, de filtre ou de page invalide la sélection de topic précédente afin que le détail ne représente jamais un autre contexte que la liste visible.

L'ouverture d'un forum depuis l'en-tête d'une section Favoris utilise le même parcours et bascule proprement vers Catégories.

### Deux modes pour les lignes de topics

`TopicListRowView` fonctionne dans deux modes :

- mode push sans callback pour le flux compact historique ;
- mode sélection avec `onSelectTarget` pour le split iPad.

Toutes les ouvertures partagent le même `TopicNavigationTarget` : tap normal, première ou dernière page, dernière réponse, résultat de recherche, page choisie manuellement et filtre des posts favoris.

Le target transporte le topic, la page, la page maximale, l'URL, le scroll initial, le séparateur de nouveaux messages et l'éventuel résultat du filtre de posts favoris.

### Identité stable

La sélection n'utilise pas l'identité mémoire de `Topic`, qui change après un refresh. `TopicNavigationID` applique :

1. un espace de noms forum ou messages privés ;
2. le `postID`, avec la catégorie lorsqu'elle est disponible ;
3. l'identifiant extrait d'une URL HFR query ou SEO ;
4. une URL canonique sans page, ancre ni paramètres de pagination ;
5. un fallback catégorie + titre normalisé.

Une liste recréée après refresh peut ainsi retrouver le topic sélectionné et conserver son détail.

## Comportements implémentés

### Synchronisation des rubriques

- Catégories, Favoris, Messages, Bookmarks et Alertes Qualitay possèdent chacun leur sélection indépendante.
- Un changement de rubrique remplace immédiatement la liste et le détail par le contexte de cette rubrique.
- Le passage d'une page directe à une liste, ou d'une liste à une autre, restaure l'affichage liste + détail.
- Un ancien topic ne peut donc plus rester visible face à une liste appartenant à une autre rubrique.
- Une notification MP ouvre Messages sur sa liste et efface son ancien détail.

### Sélection et style

- Catégories, Favoris, Messages, Bookmarks et Alertes Qualitay alimentent le panel droit.
- La ligne active utilise le fond `tintColor`, du texte blanc et le trait d'accessibilité `isSelected`, dans l'esprit de Mail.
- La transition de couleurs n'est pas animée : fond et texte changent dans le même rendu.
- Le fond sélectionné s'étend presque sur toute la ligne avec un rayon de 6 points, afin de ne pas ressembler aux teintes de type de topic.
- Une nouvelle sélection remplace le topic racine et réinitialise la pile interne du détail.
- Les liens internes et résultats de recherche de `MessagesView` continuent à s'empiler dans cette pile.
- La suppression du MP ou du bookmark affiché ferme le détail correspondant.
- Un changement de compte ou une déconnexion efface toutes les sélections.

### Affichage plein topic

Lorsqu'un topic est sélectionné et que la liste est visible, un bouton `rectangle.leadinghalf.inset.filled` est disponible dans la barre du panel droit :

- il replie le panel gauche avec `.detailOnly` ;
- il disparaît lorsque la liste est repliée ;
- le bouton système unique de `NavigationSplitView` réaffiche alors les colonnes ;
- son libellé d'accessibilité est « Masquer la liste ».

Cette combinaison évite les deux contrôles identiques observés en plein écran. Elle est partagée par Catégories, Favoris, Messages, Bookmarks et Alertes Qualitay.

### Suppression de l'onglet Plus dans la sidebar iPad

L'entrée intermédiaire Plus n'existe plus sur iPad régulier. Ses sous-rubriques sont directement accessibles :

- Bookmarks et Alertes Qualitay utilisent le modèle liste à gauche / topic à droite ;
- Réglages, Recherche, Crédits, Charte et Suppression du compte utilisent un split à deux colonnes, avec la sidebar directement accessible ;
- le panel « Aucune liste » n'existe plus ;
- l'iPhone conserve l'onglet Plus historique.

Les badges Messages et Alertes Qualitay restent visibles sur leurs entrées respectives.

### Présentations annexes

`MessagesView` reste embarquée dans le détail sans modifier ses présentations :

- réponse et édition en plein écran ;
- viewer image en plein écran ;
- sondage, recherche, page picker, profil et Safari via leurs présentations existantes.

## Fichiers concernés

- `HFRswift/Swift/MainWindow.swift`
  - coordinateur, sidebar complète et sélection par rubrique ;
  - parcours Catégories dans le panel gauche ;
  - synchronisation du détail et visibilité des colonnes.
- `HFRswift/Swift/Common.swift`
  - identité et target de navigation partagés ;
  - modes push / sélection de `TopicListRowView` ;
  - style sélection façon Mail.
- `HFRswift/Swift/Favorites.swift`
  - sélection coordonnée, ouverture d'un forum et filtre de posts.
- `HFRswift/Swift/MPListView.swift`
  - sélection coordonnée et fermeture après suppression.
- `HFRswift/Swift/BookmarksPlusView.swift`
  - liste coordonnée et fermeture après suppression.
- `HFRswift/Swift/AQPlusView.swift`
  - liste coordonnée vers le détail.
- `HFRswift/Swift/PlusTab.swift`
  - page directe de suppression du compte pour iPad.
- `HFRswift/Swift/ForumSearchView.swift`
  - adaptation au callback `onDidOpen`.
- `HFRswiftTests/TopicNavigationIdentityTests.swift`
  - stabilité de l'identité et séparation forum / MP.

## Audit de navigation

Synthèse après recadrage :

- CRITICAL : 0
- HIGH : 0
- MEDIUM : 1
- LOW : 1
- risque architectural résiduel estimé : 3/10.

### MEDIUM - Ancien push compact encore non typé

Le fallback iPhone de `TopicListRowView` et la navigation du filtre de favoris utilisent encore `NavigationLink(isActive:)`. Cette API dépréciée reste isolée au flux compact et n'intervient pas dans le coordinateur split.

Une migration vers une route typée et `NavigationPath` peut être menée séparément.

### LOW - Visibilité partagée entre scènes

La visibilité des colonnes est stockée dans `AppStorage`. Une future gestion avancée de plusieurs fenêtres pourrait déplacer cet état vers `SceneStorage`.

## Validation du 27 juillet 2026

- build, installation et lancement iPad Air 13 pouces iOS 26.4 : succès ;
- rendu iOS 26 vérifié en topic plein écran avec un seul bouton de restauration ;
- sélection vérifiée avec texte blanc, fond étendu et faible arrondi ;
- build, installation et lancement iPad Pro 13 pouces iOS 27.0 : succès ;
- Réglages et Recherche vérifiés dans le split à deux colonnes, sans panel vide et avec sidebar immédiatement accessible ;
- audit de navigation : aucun nouveau conflit de destination ou de coordinateur ;
- `git diff --check` : succès.

Les cinq `TopicNavigationIdentityTests` sont découverts, mais le target de tests ne compile pas encore à cause d'erreurs antérieures à HFR-006 dans `AccountsStoreTests` :

- `ForumTopicsLoaderSpy` non conforme à `ForumTopicsLoading` ;
- appels sans le paramètre `pageInfo`.

Ces erreurs ne proviennent pas de HFR-006 et ne bloquent pas le build de l'application.

## Recette manuelle recommandée

- iPad paysage et portrait ;
- Split View multitâche et Stage Manager ;
- rotation regular → compact → regular ;
- masquer/réafficher le panel gauche depuis un topic ;
- Catégories → catégorie → topic → retour catégories ;
- Catégories → Favoris → sélection d'un autre topic ;
- Favoris → en-tête de forum → topic → retour Favoris ;
- Bookmarks et Alertes Qualitay → topic ;
- pages directes de l'ancienne rubrique Plus ;
- refresh avec topic sélectionné ;
- suppression du MP ou bookmark affiché ;
- changement de compte, déconnexion et notification MP ;
- liens internes, recherche, réponse/édition et viewer image depuis `MessagesView`.
