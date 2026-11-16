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

## Maquettes des propositions (#632, UX-08)

- **Sujet, thème, appareils** : ceux des captures ci-dessus, pour qu'on compare d'un coup d'œil. Même sujet et même page, thème clair, heure 9:41, pseudos, auteurs de citation, « édité par », expéditeurs de MP et identifiants de citation masqués par les mêmes rectangles gris. Aucune requête vers HFR : les textes sont ceux des captures.
- **Base** : l'app 4.0.3 (37), tag `build#37`. La barre d'état, les barres de navigation et les boutons flottants reprennent les captures de #631 au pixel près ; le reste est redessiné à l'identique : styles du lecteur de `SuperHFRplus/Assets/HTML/style-liste-light.css`, icônes de la barre latérale de `HFRswift/Swift/MainWindow.swift` (`iPadSidebarSystemImage`), en-tête et barres d'outils de l'éditeur de `HFRswift/Swift/AnswerView.swift`, tous à `build#37`.
- **Ce qui change, et seulement cela** :
  - `L1` « pages améliorées » : séparateur des nouveaux messages bien visible (aujourd'hui un tireté gris, `.separator1`) et message de la liste noire replié sur une ligne qu'on déplie, comme le lecteur de SwiftHFR (`TopicHTMLBuilder.swift`, `blocked-post`). Tout cela reste dans la WebView. Le changement de page sans écran blanc ne se voit pas sur une image fixe : la liste des détails sous la réponse le dit.
  - `L1` « lecture continue » : la page 3 s'affiche à la suite de la page 2 avec un repère « Page 3 » discret, et le numéro de page du titre suit. Les messages montrés après le repère reprennent des passages de la page 2 : la page 3 n'a pas été capturée.
  - `D2` « tableau de bord » : une entrée « À suivre » dans la barre latérale et une colonne qui regroupe reprise de la lecture, MP non lus, favoris et drapeaux avec le nombre de nouveaux messages. Les titres des sujets sont ceux de la liste Hardware de la capture iPad ; l'état connecté (MP, compteurs) est inventé pour la maquette, et les objets des deux MP sont fictifs.
  - `D2` « côte à côte » : le sujet reste à gauche, l'éditeur de l'app à droite, et un aperçu local du message sous le texte (l'aperçu calculé sur l'appareil, LOT-152, pas l'aperçu serveur classé Non). Le préremplissage d'une citation suit la forme `[quotemsg=…]` de `docs/lots/LOT-036-hop-form-parser.md`, identifiants masqués. La réponse tapée est fictive.
- **Duo déplié** : 951 × 669 points en paysage, @3x, d'après le profil de l'appareil « iPhone Duo » du simulateur (écran intérieur de 2007 × 2853 pixels). La barre latérale y est masquée, comme dans le legacy (`docs/lots/LOT-147-duo-ipad-columns.md`, « Sidebar pinned or on demand »).
- **Rien de ce qui est classé Non** (`docs/ux/tri-m5-decisions.md` §3.5) : ni scrubber, ni plateau de citations, ni aperçu serveur, ni nouvelle couleur d'accent.
- **Fabrication** : pages HTML rendues par Chrome sans interface à la taille exacte des appareils, vidéos encodées en H.264 avec AVFoundation, images réduites à 256 couleurs comme les captures de #631. Le code de maquette est jetable et n'entre pas dans le dépôt.

Fichiers du formulaire : `scenarios/` pour les maquettes, `actuel/` pour les captures, tous copiés à plat dans `tooling/ux-survey/web/visuels/` (un test les veut identiques). Pour `D2` sur Duo déplié, « comme aujourd'hui » reprend la capture iPad (décision du PO).

| Fichier | Texte alternatif | Question | Appareil | Nature |
|---|---|---|---|---|
| `L1-pages-ameliorees-iphone.png` | Maquette sur iPhone, même sujet que la capture actuelle : un message masqué replié sur une ligne « Message masqué de … Afficher », puis un séparateur bien visible « Nouveaux messages » avant le message suivant. | `L1` | iPhone 17 Pro, 402 × 874 points | maquette, 1206 × 2622 px |
| `L1-lecture-continue-iphone.mp4` | Vidéo de 8 secondes sur iPhone : en faisant défiler le sujet, la page 3 s'affiche à la suite de la page 2 avec un discret repère « Page 3 », et le numéro en haut passe de 2 / 712 à 3 / 712. | `L1` | iPhone 17 Pro, 402 × 874 points | vidéo H.264, 8 s, 804 × 1748 px, sans son |
| `L1-lecture-continue-iphone.png` | Image d'attente de L1-lecture-continue-iphone.mp4 : son dernier état. Le repère « Page 3 » au milieu de l'écran, entre la fin de la page 2 et le début de la page 3. | `L1` | iPhone 17 Pro, 402 × 874 points | image d'attente de la vidéo, 1206 × 2622 px |
| `L1-comme-aujourdhui-iphone.png` | Lecture d'un long sujet dans l'app actuelle sur iPhone : un message et sa citation, texte plein écran, barre de navigation en haut, boutons de page et de réponse flottants en bas. | `L1` | iPhone 17 Pro, simulateur iOS 27.0 | capture (#631), copie de `actuel/` |
| `D2-comme-aujourdhui-ipad.png` | Disposition actuelle sur iPad en paysage, trois colonnes : barre latérale (Forum, Outils, Plus), liste des sujets du forum Hardware, sujet ouvert à droite. Sert aussi à D1 (barre latérale actuelle). | `D2` | iPad Pro 13 pouces (M5), simulateur iOS 27.0 | capture (#631), copie de `actuel/` ; sert aussi au Duo déplié |
| `D2-tableau-de-bord-ipad.png` | Maquette sur iPad en paysage : la barre latérale gagne « À suivre », la colonne du milieu regroupe la reprise de la lecture, les messages privés non lus, les favoris et les drapeaux avec leur nombre de nouveaux messages, et le sujet repris s'ouvre à droite. | `D2` | iPad Pro 13 pouces, paysage, 1376 × 1032 points | maquette, 2752 × 2064 px |
| `D2-tableau-de-bord-duo.mp4` | Vidéo de 7 secondes sur iPhone Duo déplié, en paysage : la colonne « À suivre » à gauche ; toucher « Reprendre la lecture » ouvre le sujet à droite, au séparateur des nouveaux messages. | `D2` | iPhone Duo déplié, paysage, 951 × 669 points | vidéo H.264, 7 s, 1902 × 1338 px, sans son |
| `D2-tableau-de-bord-duo.png` | Image d'attente de D2-tableau-de-bord-duo.mp4 : son dernier état. La colonne « À suivre » à gauche, le sujet repris ouvert à droite au séparateur des nouveaux messages. | `D2` | iPhone Duo déplié, paysage, 951 × 669 points | image d'attente de la vidéo, 2853 × 2007 px |
| `D2-cote-a-cote-ipad.png` | Maquette sur iPad en paysage : le sujet reste visible à gauche pendant qu'on écrit une citation à droite, et un aperçu sous le texte montre le message tel qu'il sera affiché, avant l'envoi. | `D2` | iPad Pro 13 pouces, paysage, 1376 × 1032 points | maquette, 2752 × 2064 px |
| `D2-cote-a-cote-duo.mp4` | Vidéo de 8 secondes sur iPhone Duo déplié, en paysage : le sujet à gauche, l'éditeur à droite, et l'aperçu sous le texte qui se met à jour pendant la frappe. | `D2` | iPhone Duo déplié, paysage, 951 × 669 points | vidéo H.264, 8 s, 1902 × 1338 px, sans son |
| `D2-cote-a-cote-duo.png` | Image d'attente de D2-cote-a-cote-duo.mp4 : son dernier état. Le sujet à gauche, la citation écrite à droite et son aperçu dessous. | `D2` | iPhone Duo déplié, paysage, 951 × 669 points | image d'attente de la vidéo, 2853 × 2007 px |

## Cartes des sections de la barre latérale (`D1`)

Dans `scenarios/D1-cartes/`, une carte par section de `D1` (questions.md), 340 × 76 points @2x, fond transparent, et la planche des neuf cartes. Icônes de la barre latérale actuelle ; `flag` pour Drapeaux et `newspaper` pour À suivre, que la barre n'a pas. Le formulaire les affiche (#919), une par section, à côté de son état, copiées dans `tooling/ux-survey/web/visuels/D1-cartes/` (un test les veut identiques) ; la planche sert au test à cinq. Les noms d'icônes SF Symbols (`star.fill`, `folder.fill`, `envelope`, `flag`, `newspaper`, `bell`, `pin`, `magnifyingglass`, `gearshape`) restent pour qui refait les cartes ; le texte alternatif les dit en français.

| Fichier | Texte alternatif | Question | Appareil |
|---|---|---|---|
| `D1-cartes/D1-carte-favoris.png` | Carte « Favoris » : étoile, aujourd'hui dans le groupe Forum | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-categories.png` | Carte « Catégories » : dossier, aujourd'hui dans le groupe Forum | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-mp.png` | Carte « Messages privés » : enveloppe, aujourd'hui dans le groupe Forum | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-drapeaux.png` | Carte « Drapeaux » : drapeau, aujourd'hui dans Favoris | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-a_suivre.png` | Carte « À suivre » : journal, les nouveautés de tous vos sujets suivis, avec l'étiquette « Nouveau » | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-alertes_qualitay.png` | Carte « Alertes Qualitay » : cloche, aujourd'hui dans le groupe Outils | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-bookmarks.png` | Carte « Bookmarks » : épingle, aujourd'hui dans le groupe Outils | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-recherche.png` | Carte « Recherche » : loupe, aujourd'hui dans le groupe Plus | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-reglages.png` | Carte « Réglages » : roue dentée, aujourd'hui dans le groupe Plus | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-cartes-planche.png` | Les neuf cartes de la barre latérale sur trois colonnes, dans l'ordre de la question. | `D1` | Aucun (planche) |
