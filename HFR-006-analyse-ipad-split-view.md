# HFR-006 - Analyse iPad split view

## Objectif

Etudier la faisabilite UX et technique d'un affichage iPad en deux colonnes, proche de Mail :

- a gauche, la liste des topics correspondant a la section active ;
- a droite, le topic ouvert dans `MessagesView` ;
- ratio vise autour de 30/70, avec adaptation aux tailles d'ecran iPad.

Cette analyse ne propose pas de modification immediate du code. Elle sert a cadrer le refactor potentiel.

## Conclusion courte

La demande est pertinente et realisable. Sur iPad, le modele liste + detail correspond bien a l'usage forum : scanner des favoris ou messages prives, ouvrir rapidement un topic, garder le contexte de liste visible.

Le chantier n'est cependant pas un simple reglage SwiftUI. Aujourd'hui, l'app a deja un `NavigationSplitView` sur iPad, mais il sert a selectionner l'onglet racine, pas a afficher une liste de topics a gauche et un topic a droite. Le refactor consiste donc surtout a deplacer la responsabilite d'ouverture des topics depuis les lignes vers un conteneur parent iPad.

Risque estime : moyen. L'UX cible est saine, mais il faut eviter de dupliquer les vues iPhone/iPad et stabiliser la navigation.

## Etat actuel observe

### Racine iPad

Sur iPad en taille reguliere, `RootTabView` utilise actuellement `NavigationSplitView` avec :

- colonne gauche : liste des onglets racine ;
- colonne droite : contenu de l'onglet selectionne.

Reference : `HFRswift/Swift/MainWindow.swift`, autour de `iPadSidebarRoot`.

Ce n'est donc pas encore le split attendu pour HFR-006. Le split actuel remplace le tab bar par une sidebar d'onglets.

### Listes de topics

`FavoritesListView` et `MPListView` possedent chacune leur propre `NavigationStack`.

References :

- `HFRswift/Swift/Favorites.swift`, `FavoritesListView.body`
- `HFRswift/Swift/MPListView.swift`, `MPListView.body`

Les lignes de topics passent par `TopicListRowView`, qui construit une cible de navigation puis pousse directement `MessagesView` via un `NavigationLink` cache.

Reference : `HFRswift/Swift/Common.swift`, `TopicListRowView`.

Cette architecture est coherente pour iPhone, mais elle est le principal obstacle au split iPad : la ligne possede aujourd'hui la navigation, alors qu'en split la selection doit etre portee par le parent.

### `MessagesView`

`MessagesView` gere deja plusieurs presentations annexes :

- reponse via `coverVerticalFullScreen` et `AnswerView` ;
- viewer image via `fullScreenCover` ;
- sondage, recherche, page picker, profil, Safari in-app via sheets.

Reference : `HFRswift/Swift/MessagesView.swift`.

En mode split, `MessagesView` devra pouvoir etre affichee comme detail embarque, tout en gardant certaines presentations en plein ecran.

## Analyse UX

### Pertinence du modele Mail

Le modele est pertinent pour :

- Favoris : consultation rapide de plusieurs topics ;
- Messages prives : lecture de conversations avec maintien de la liste ;
- Topics de forum : utile aussi, mais plus complexe a cause du niveau categorie -> liste de topics -> topic.

Le gain principal est la reduction des allers-retours. Sur iPad, le comportement actuel type iPhone pousse l'utilisateur a revenir en arriere pour changer de topic. Le split rend l'usage plus fluide.

### Comportement recommande

Sur iPhone :

- conserver le flux actuel ;
- liste puis push plein ecran vers `MessagesView`.

Sur iPad regular :

- colonne gauche : liste active ;
- colonne droite : topic selectionne ;
- etat vide a droite si aucun topic n'est selectionne ;
- tap sur une ligne : mise a jour du detail, sans push ;
- ligne selectionnee visuellement active.

### Ratio de colonnes

Le ratio 30/70 est bon comme intention, mais il vaut mieux eviter un pourcentage strict.

Recommandation :

- largeur gauche ideale autour de 320 a 420 pt ;
- largeur minimale suffisante pour garder les titres lisibles ;
- detail qui prend le reste ;
- laisser `NavigationSplitView` adapter ou masquer la colonne selon portrait/paysage et taille disponible.

### Fenetres annexes

Recommandation UX :

- reponse : toujours plein ecran sur l'ensemble de la scene, pas limitee a la colonne droite ;
- viewer image : plein ecran ;
- sondage : sheet acceptable depuis le detail ;
- recherche/page picker/profil : sheet ou popover selon le point d'appel ;
- login/compte : presentation globale, pas liee a une seule colonne.

Le composeur de reponse ne doit pas etre contraint dans 70 % de largeur. La saisie longue, le clavier et les brouillons justifient une presentation plein ecran.

## Analyse technique

### Changement d'architecture de navigation

La direction technique recommandee est de rendre `TopicListRowView` capable de fonctionner dans deux modes :

- mode push : comportement actuel, utile pour iPhone ;
- mode selection : la ligne calcule le `TopicNavigationTarget` et le remonte au parent, utile pour iPad split.

Le parent iPad devient alors proprietaire de la selection et affiche :

- a gauche, la liste ;
- a droite, `MessagesView(topic: target.topic, curPage: target.page, ...)`.

Cela evite de faire porter a chaque ligne une pile de navigation locale.

### Factorisation a prevoir

Pour garder la maintenabilite :

- extraire des variantes "liste pure" pour Favoris et Messages ;
- conserver les view models existants ;
- mutualiser les lignes ;
- eviter une duplication complete entre iPhone et iPad ;
- centraliser la construction de `TopicNavigationTarget`.

Le but n'est pas de creer une deuxieme app iPad, mais de partager les composants et de changer uniquement le proprietaire de navigation selon la taille d'ecran.

### Etat simultane liste + detail

Le split implique que la liste et `MessagesView` vivent en meme temps. Il faudra verifier :

- topic marque lu alors que la ligne gauche se met a jour ;
- favori retire ou deplace pendant que le topic reste ouvert ;
- MP supprime ou marque non lu pendant qu'il est affiche ;
- refresh de la liste sans recreation inutile de `MessagesView` ;
- selection stable si l'objet `Topic` source disparait ou est remplace.

Point favorable : `TopicListRowView` cree deja une copie de destination du topic pour la navigation. Ce principe est utile pour garder le detail stable meme si la liste evolue.

### Liens internes depuis `MessagesView`

Question a trancher pendant le design :

- un lien interne vers un autre topic remplace-t-il le detail courant ?
- ouvre-t-il un push dans la colonne detail ?
- met-il aussi a jour la selection gauche si le topic existe dans la liste ?

Recommandation initiale : remplacer le detail courant, sans chercher a synchroniser la selection gauche si le topic n'est pas present dans la liste active.

### Tab racine iPad

Le split actuel utilise la colonne gauche pour choisir les onglets. Or HFR-006 veut que cette colonne soit la liste des topics.

Il faudra donc choisir une nouvelle organisation iPad :

- soit garder une forme de selection d'onglet en haut ou dans une barre compacte ;
- soit avoir un split specifique par onglet actif ;
- soit envisager un modele 3 colonnes, mais ce n'est pas la demande actuelle.

Pour respecter la demande, la meilleure piste est un split par onglet actif : quand Favoris est actif, gauche = favoris ; quand Messages est actif, gauche = MP ; quand une categorie/forum est actif, gauche = topics du forum.

## Plan de mise en oeuvre propose

### Phase 1 - Base de navigation

- Rendre `TopicNavigationTarget` partageable si necessaire.
- Ajouter un callback d'ouverture a `TopicListRowView`.
- Garder le push actuel pour iPhone.
- Ajouter un mode selection pour iPad.

### Phase 2 - Favoris et Messages

- Creer un conteneur split pour Favoris.
- Creer un conteneur split pour Messages prives.
- Afficher `MessagesView` en detail.
- Ajouter un etat vide a droite.
- Verifier selection, refresh, unread, suppression.

### Phase 3 - Adapter `MessagesView`

- Ajouter si necessaire une notion de contexte de presentation : push plein ecran ou detail split.
- Eviter les hypotheses de tab bar cachee en mode detail.
- Garder les presentations importantes en plein ecran : reponse et viewer image.

### Phase 4 - Categories / forums

- Traiter le cas plus complexe categorie -> liste de topics -> topic.
- Decider si la selection de categorie reste un niveau avant le split, ou si elle s'integre dans une navigation plus large.

### Phase 5 - Validation

Scenarios a tester :

- iPhone : comportement inchange ;
- iPad paysage : deux colonnes visibles ;
- iPad portrait : comportement de collapse acceptable ;
- Favoris : ouverture, refresh, topic marque lu ;
- MP : ouverture, marquer non lu, suppression ;
- reponse : plein ecran ;
- viewer image : plein ecran ;
- sondage : flux sans conflit avec le split ;
- liens internes depuis `MessagesView`.

## Recommandation finale

HFR-006 est un bon candidat pour une evolution iPad, mais il faut le traiter comme un refactor de navigation cible, pas comme une simple option d'affichage.

Je recommande de commencer par Favoris et Messages, qui sont les deux flux les plus naturels pour le split. Les Categories peuvent venir ensuite, car leur navigation a un niveau supplementaire.

Le critere de reussite principal : l'iPhone doit rester sur le flux actuel, tandis que l'iPad gagne un vrai mode liste/detail sans duplication massive de code.
