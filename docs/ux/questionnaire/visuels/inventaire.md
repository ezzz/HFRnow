# Inventaire des visuels

Ce fichier liste les visuels du questionnaire : texte alternatif, sujet utilisé, version de l'app, appareil (cadrage de construction §3.3).

## Visuels de l'app actuelle (#631, UX-07)

- **App** : 4.0.3 (37), tag `build#37`, commit `20a4b2f7`, compilée depuis ce commit (le plist du `.app` compilé donne `CFBundleShortVersionString` 4.0.3 et `CFBundleVersion` 37).
- **Sujet** : « Topic Blackwell - Nvidia Geforce RTX 5000 » (forum Hardware, lisible sans compte), page 2 sur 712 (messages du 11 juin 2023). Le même sujet sert à toutes les images.
- **Thème** : clair, réglages par défaut de l'app, aucun compte ajouté, heure de la barre d'état fixée à 9:41.
- **Pseudos** : tous masqués (auteurs, citations « a écrit », « édité par », derniers messagistes de la liste), avec leurs avatars. Aucun message n'a été envoyé et aucune requête authentifiée n'a été faite.

| Fichier | Texte alternatif | Question | Appareil |
|---|---|---|---|
| `actuel/L1-comme-aujourdhui-iphone.png` | Lecture d'un long sujet dans l'app actuelle sur iPhone : un message et sa citation, texte plein écran, barre de navigation en haut, boutons de page et de réponse flottants en bas. | `L1` | iPhone 17 Pro, simulateur iOS 27.0 |
| `actuel/D2-comme-aujourdhui-ipad.png` | Disposition actuelle sur iPad en paysage, trois colonnes : barre latérale (Forum, Outils, Plus), liste des sujets du forum Hardware, sujet ouvert à droite. Sert aussi à `D1` (barre latérale actuelle). | `D2`, `D1` | iPad Pro 13 pouces (M5), simulateur iOS 27.0 |
- **Badge « 25 » sur Alertes Qualitay** (`D2-comme-aujourdhui-ipad.png`) : il vient de l'app compilée telle quelle, sans compte ; ce n'est pas une donnée de l'utilisateur.

## Duo déplié

Pas de capture propre au Duo (décision du PO) : pour `D2` sur Duo déplié, on réutilise `actuel/D2-comme-aujourdhui-ipad.png` (même disposition que sur iPad).

## Marques de place des propositions (UX-10, #634)

> **PROVISOIRE.** Ces fichiers sont des marques de place ajoutées par UX-10 (#634) pour que le formulaire se construise sans attendre #632 (décision du PO du 9 novembre 2026). Les visuels réels de #632 les remplacent aux mêmes noms ; ce fichier est alors réécrit avec le sujet utilisé et la version de l'app. Le formulaire (`tooling/ux-survey/`) garde une copie de ces fichiers dans `web/visuels/`, et un test vérifie qu'elles sont identiques.

Les deux captures « comme aujourd'hui » (`L1-comme-aujourdhui-iphone.png`, `D2-comme-aujourdhui-ipad.png`) sont décrites par la section « Visuels de l'app actuelle » ci-dessus (#631, UX-07) et vivent dans `visuels/actuel/` ; leurs lignes ci-dessous les recopient pour le test de concordance. Pour D2 sur Duo déplié, on reprend la capture iPad (décision du PO, même disposition).

| Fichier | Texte alternatif | Question | Sujet utilisé | Version de l'app |
|---|---|---|---|---|
| `L1-pages-ameliorees-iphone.png` | Visuel provisoire : lecture d'un sujet avec des pages plus agréables, sur iPhone | `L1` | (provisoire) | (provisoire) |
| `L1-lecture-continue-iphone.png` | Visuel provisoire : lecture continue en option, sur iPhone | `L1` | (provisoire) | (provisoire) |
| `L1-comme-aujourdhui-iphone.png` | Lecture d'un long sujet dans l'app actuelle sur iPhone : un message et sa citation, texte plein écran, barre de navigation en haut, boutons de page et de réponse flottants en bas. | `L1` | « Topic Blackwell - Nvidia Geforce RTX 5000 », page 2 | 4.0.3 (37) |
| `D2-comme-aujourdhui-ipad.png` | Disposition actuelle sur iPad en paysage, trois colonnes : barre latérale (Forum, Outils, Plus), liste des sujets du forum Hardware, sujet ouvert à droite. Sert aussi à D1 (barre latérale actuelle). | `D2` | « Topic Blackwell - Nvidia Geforce RTX 5000 », page 2 | 4.0.3 (37) |
| `D2-tableau-de-bord-ipad.png` | Visuel provisoire : colonne « À suivre » sur iPad | `D2` | (provisoire) | (provisoire) |
| `D2-tableau-de-bord-duo.mp4` | Vidéo provisoire : colonne « À suivre » sur iPhone Duo déplié | `D2` | (provisoire) | (provisoire) |
| `D2-tableau-de-bord-duo.png` | Image d'attente de D2-tableau-de-bord-duo.mp4 | `D2` | (provisoire) | (provisoire) |
| `D2-cote-a-cote-ipad.png` | Visuel provisoire : lire et écrire côte à côte sur iPad | `D2` | (provisoire) | (provisoire) |
| `D2-cote-a-cote-duo.mp4` | Vidéo provisoire : lire et écrire côte à côte sur iPhone Duo déplié | `D2` | (provisoire) | (provisoire) |
| `D2-cote-a-cote-duo.png` | Image d'attente de D2-cote-a-cote-duo.mp4 | `D2` | (provisoire) | (provisoire) |
