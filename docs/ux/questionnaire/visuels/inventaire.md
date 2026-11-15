# Inventaire des visuels

Ce fichier liste les visuels du questionnaire : texte alternatif, sujet utilisé, version de l'app, appareil (cadrage de construction §3.3).

> **Fusion avec #712.** La PR du formulaire (#712) ajoute elle aussi `visuels/inventaire.md`, avec les marques de place des propositions (`L1-pages-ameliorees-iphone.png`, `D2-tableau-de-bord-*`, `D2-cote-a-cote-*`, etc.). La section « Visuels de l'app actuelle » ci-dessous vient de #631 (UX-07) ; en cas de conflit, garder les deux sections.

## Visuels de l'app actuelle (#631, UX-07)

- **App** : 4.0.3 (37), tag `build#37`, commit `20a4b2f7`, compilée depuis ce commit (le plist du `.app` compilé donne `CFBundleShortVersionString` 4.0.3 et `CFBundleVersion` 37).
- **Sujet** : « Topic Blackwell - Nvidia Geforce RTX 5000 » (forum Hardware, lisible sans compte), page 2 sur 712 (messages du 11 juin 2023). Le même sujet sert à toutes les images.
- **Thème** : clair, réglages par défaut de l'app, aucun compte ajouté, heure de la barre d'état fixée à 9:41.
- **Pseudos** : tous masqués (auteurs, citations « a écrit », « édité par », derniers messagistes de la liste), avec leurs avatars. Aucun message n'a été envoyé et aucune requête authentifiée n'a été faite.

| Fichier | Texte alternatif | Question | Appareil |
|---|---|---|---|
| `actuel/L1-comme-aujourdhui-iphone.png` | Lecture d'un long sujet dans l'app actuelle sur iPhone : un message et sa citation, texte plein écran, barre de navigation en haut, boutons de page et de réponse flottants en bas. | `L1` | iPhone 17 Pro, simulateur iOS 27.0 |
| `actuel/D2-comme-aujourdhui-ipad.png` | Disposition actuelle sur iPad en paysage, trois colonnes : barre latérale (Forum, Outils, Plus), liste des sujets du forum Hardware, sujet ouvert à droite. Sert aussi à `D1` (barre latérale actuelle). | `D2`, `D1` | iPad Pro 13 pouces (M5), simulateur iOS 27.0 |
| `actuel/D2-comme-aujourdhui-duo-exterieur.png` | iPhone Duo, écran extérieur : l'interface de l'iPhone avec la lecture d'un sujet, la barre d'onglets et les boutons de page sur le côté droit. | `D2` | iPhone Duo, simulateur iOS 27.2 |
| `actuel/D2-comme-aujourdhui-duo.mp4` | Vidéo muette de 7 secondes : défilement de la liste des catégories sur l'écran extérieur de l'iPhone Duo. | `D2` | iPhone Duo, simulateur iOS 27.2 |
| `actuel/D2-comme-aujourdhui-duo.png` | Image d'attente de `D2-comme-aujourdhui-duo.mp4` : liste des catégories, écran extérieur du Duo. | `D2` | iPhone Duo, simulateur iOS 27.2 |

## À faire par le PO ou sur un autre poste

- **Écran intérieur du Duo (déplié) : en attente.** Le simulateur iPhone Duo existe dans Xcode, mais l'application Simulator n'est pas installée sur ce poste : il n'y a aucun moyen d'ouvrir le Duo, et l'écran intérieur reste noir. Les visuels du Duo déplié (`D2` : disposition actuelle, vidéo de 10 secondes) sont à refaire sur un poste avec Simulator, ou sur un appareil réel (décision D5 du PO).
- La vidéo du Duo montre la liste des catégories, qui n'affiche aucun pseudo : monter un défilement dans un sujet demanderait de masquer chaque image de la vidéo.
