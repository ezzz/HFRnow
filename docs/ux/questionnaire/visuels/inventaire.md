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

## Duo déplié

Pas de capture propre au Duo (décision du PO) : pour `D2` sur Duo déplié, on réutilise `actuel/D2-comme-aujourdhui-ipad.png` (même disposition que sur iPad).
