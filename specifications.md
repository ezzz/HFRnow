# Specifications

## Gestion de reponse

### Objectif

Clarifier les differents chemins d'ouverture de `AnswerView` pour eviter de melanger deux usages distincts :

- une reponse rapide, locale et immediate ;
- une reponse forum complete, qui charge le formulaire serveur et recupere les citations cochees sur le forum.

### Points d'entree

Le bouton `+` de `MessagesView` est reserve a la reponse rapide. Il ouvre `AnswerView` avec le brouillon courant du topic, sans prechargement du formulaire forum. Le reglage `Sujets > Reponse rapide` sert uniquement a afficher ou masquer ce bouton.

L'action `Repondre` du menu `...` de `MessagesView` garde le comportement forum complet. Elle charge `topicAnswerURL`, recupere le contenu renvoye par le forum, y compris les citations cochees, puis ouvre `AnswerView`.

Les actions `Citer` et `Citer extrait` chargent aussi un contenu depuis le forum avant ouverture de `AnswerView`. Elles remplacent le texte courant plutot que de le concatener.

L'action `Editer` reste isolee : elle ouvre `AnswerView` avec le contenu du message a editer, sans ecraser le brouillon de reponse du topic.

### Brouillons

Les brouillons de reponse sont contextualises par topic et limites aux 3 derniers brouillons par topic.

Quand un contenu charge depuis le forum doit remplir `AnswerView` alors qu'un brouillon courant non vide existe, le brouillon courant est archive avant remplacement. Le contenu charge remplace ensuite totalement le contenu de l'editeur.

Dans `AnswerView`, le bouton `Brouillons` affiche une sheet listant les brouillons du topic. Choisir un brouillon remplace le texte courant ; si le texte courant est non vide et different, il est archive avant remplacement.

Un brouillon est supprime automatiquement lorsqu'il est selectionne puis poste avec succes. La sheet permet aussi de supprimer rapidement un brouillon par swipe gauche, ou de vider tous les brouillons du topic via l'action globale `Vider`.

### Principe UX

Le `+` doit rester une action rapide et previsible. Le comportement forum complet est volontairement expose par une action nommee `Repondre`, plus explicite, car elle peut entrainer une requete reseau et charger des citations accumulees.
