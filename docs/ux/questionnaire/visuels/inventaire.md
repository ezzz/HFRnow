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

- **Sujet, thème, appareils** : ceux des captures ci-dessus, pour qu'on compare d'un coup d'œil. Même sujet et même page, thème clair, heure 9:41. Pseudos, auteurs de citation, « édité par », expéditeurs de MP et identifiants de citation sont masqués par les mêmes rectangles gris. Aucune requête vers HFR.
- **Base** : l'app 4.0.3 (37), tag `build#37`. La barre d'état, les barres de navigation et les boutons flottants reprennent les captures de #631 au pixel près. Le reste est redessiné à l'identique d'après le code à `build#37` :
  - styles du lecteur : `SuperHFRplus/Assets/HTML/style-liste-light.css` ;
  - icônes de la barre latérale : `HFRswift/Swift/MainWindow.swift` (`iPadSidebarSystemImage`) ;
  - en-tête et barres d'outils de l'éditeur : `HFRswift/Swift/AnswerView.swift`.
- **Ce qui change, et seulement cela** :
  - `L1` « pages améliorées » : séparateur des nouveaux messages en pastille bien visible, et message de la liste noire replié sur une ligne qu'on déplie (cible de 44 points). Tout reste dans la WebView. Le changement de page sans écran blanc ne se voit pas sur une image fixe : la liste des détails sous la réponse le dit.
  - `L1` « lecture continue » : la page 3 s'affiche à la suite de la page 2 avec un repère « Page 3 » discret, et le numéro de page du titre suit.
  - `D2` « tableau de bord » : une entrée « À suivre » dans la barre latérale, et une colonne qui regroupe la reprise de la lecture, les MP non lus, les favoris et les drapeaux avec leur nombre de nouveaux messages. Sur Duo, le sujet s'ouvre dans le lecteur actuel (séparateur en tireté gris), sans les améliorations de `L1`. Le titre « À suivre » y est en ligne, comme les titres du legacy sur le Duo (`docs/lots/LOT-147-duo-ipad-columns.md`).
  - `D2` « côte à côte » : le sujet reste à gauche, l'éditeur de l'app est à droite, et un aperçu local du message s'affiche sous le texte. C'est l'aperçu calculé sur l'appareil (LOT-152), pas l'aperçu serveur classé Non. Sur iPad, un clavier externe est supposé. Sur Duo, qui n'a pas de clavier matériel, le clavier à l'écran couvre le bas de l'écran et il ne reste de l'aperçu que son début ; la hauteur du clavier (286 points) est estimée. Le préremplissage d'une citation suit la forme `[quotemsg=…]` de `docs/lots/LOT-036-hop-form-parser.md`, identifiants masqués.
- **Nouveaux dessins, pas l'existant** : la pastille « Nouveaux messages » et la ligne repliée « Message masqué de … Afficher » sont dessinées pour la proposition. SwiftHFR a aujourd'hui un tireté d'un pixel (`App/SwiftHFR/Reader/Resources/reader.css:73`) et une ligne « Message masqué » (`App/SwiftHFR/Reader/TopicHTMLBuilder.swift:193`). Le cadrage (`cadrage-construction.md` §5) recommandait de capturer SwiftHFR pour ce qui existe déjà ; tout est redessiné ici sur la base de la 4.0.3, pour que les visuels se comparent à la capture de référence.
- **Ce qui est inventé** :
  - `L1-pages-ameliorees-iphone.png` : le message masqué entre 19:14:14 et 19:32:05 n'existe pas ; ces deux messages se suivent dans la capture réelle.
  - `L1-lecture-continue-iphone.*` : les messages affichés après le repère « Page 3 » reprennent des passages de la page 2, car la page 3 n'a pas été capturée.
  - `D2-tableau-de-bord-*` : l'état connecté (MP non lus, compteurs de nouveaux messages) et les objets des deux MP. Les titres des sujets sont ceux de la liste Hardware de la capture iPad.
  - `D2-tableau-de-bord-duo.*` : le contenu du message de 19:38:38 est masqué, faute de l'avoir sur une capture lisible.
  - `D2-cote-a-cote-*` : le texte de la réponse tapée.
- **Asymétrie connu / non connecté** : la référence `D2-comme-aujourdhui-ipad.png` est prise sans compte (bandeau « Connexion requise… »), alors que le tableau de bord est montré connecté, avec des MP et des compteurs. À garder en tête en lisant les réponses à `D2` ; le libellé peut le dire, ou la capture être refaite avec un compte.
- **Contraste** : tout texte ajouté atteint au moins 4,5:1 (texte d'accent `#006a8e`, blanc sur `#007aa0`, gris `#6c6c70` et `#636366`). Ce qui vient de l'app actuelle n'est pas modifié.
- **Rien de ce qui est classé Non** (`docs/ux/tri-m5-decisions.md` §3.5) : ni scrubber, ni plateau de citations, ni aperçu serveur, ni nouvelle couleur d'accent.
- **Fabrication** : les pages HTML sont rendues par Chrome sans interface, à la taille exacte des appareils. Les vidéos sont encodées en H.264 avec AVFoundation (en-tête `moov` au début du fichier, pas de piste son). Les images sont réduites à 256 couleurs, comme les captures de #631. Le code de maquette est jetable et n'entre pas dans le dépôt.
- **Duo déplié** : 951 × 669 points en paysage, @3x, d'après le profil de l'appareil « iPhone Duo » du simulateur (écran intérieur de 2007 × 2853 pixels). La barre latérale y est masquée, comme dans le legacy (`LOT-147`, « Sidebar pinned or on demand »).

Fichiers du formulaire : `scenarios/` pour les maquettes, `actuel/` pour les captures, tous copiés à plat dans `tooling/ux-survey/web/visuels/` (un test les veut identiques). Pour `D2` sur Duo déplié, « comme aujourd'hui » reprend la capture iPad (décision du PO).

| Fichier | Texte alternatif | Question | Appareil | Nature |
|---|---|---|---|---|
| `L1-pages-ameliorees-iphone.png` | Maquette sur iPhone, même sujet que la capture actuelle : un message masqué replié sur une ligne « Message masqué de … Afficher », puis un séparateur bien visible « Nouveaux messages » avant le message suivant. | `L1` | iPhone 17 Pro, 402 × 874 points | maquette, 1206 × 2622 px |
| `L1-lecture-continue-iphone.mp4` | Vidéo de 7 secondes sur iPhone : en faisant défiler le sujet, la page 3 s'affiche à la suite de la page 2 avec un discret repère « Page 3 », et le numéro en haut passe de 2 / 712 à 3 / 712. | `L1` | iPhone 17 Pro, 402 × 874 points | vidéo H.264, 7 s, 804 × 1748 px, sans son |
| `L1-lecture-continue-iphone.png` | Image d'attente de L1-lecture-continue-iphone.mp4 : le repère « Page 3 » au milieu de l'écran, entre la fin de la page 2 et le début de la page 3 ; le titre indique encore 2 / 712. | `L1` | iPhone 17 Pro, 402 × 874 points | image d'attente de la vidéo, 1206 × 2622 px |
| `L1-comme-aujourdhui-iphone.png` | Lecture d'un long sujet dans l'app actuelle sur iPhone : un message et sa citation, texte plein écran, barre de navigation en haut, boutons de page et de réponse flottants en bas. | `L1` | iPhone 17 Pro, simulateur iOS 27.0 | capture (#631), copie de `actuel/` |
| `D2-comme-aujourdhui-ipad.png` | Disposition actuelle sur iPad en paysage, trois colonnes : barre latérale (Forum, Outils, Plus), liste des sujets du forum Hardware, sujet ouvert à droite. Sert aussi à D1 (barre latérale actuelle). | `D2` | iPad Pro 13 pouces (M5), simulateur iOS 27.0 | capture (#631), copie de `actuel/` ; sert aussi au Duo déplié |
| `D2-tableau-de-bord-ipad.png` | Maquette sur iPad en paysage : la barre latérale gagne « À suivre », la colonne du milieu regroupe la reprise de la lecture, les messages privés non lus, les favoris et les drapeaux avec leur nombre de nouveaux messages, et le sujet repris s'ouvre à droite. | `D2` | iPad Pro 13 pouces, paysage, 1376 × 1032 points | maquette, 2752 × 2064 px |
| `D2-tableau-de-bord-duo.mp4` | Vidéo de 5 secondes sur iPhone Duo déplié, en paysage : la colonne « À suivre » à gauche ; toucher « Reprendre la lecture » ouvre le sujet à droite dans le lecteur actuel, au séparateur des nouveaux messages en tireté gris. | `D2` | iPhone Duo déplié, paysage, 951 × 669 points | vidéo H.264, 5 s, 1902 × 1338 px, sans son |
| `D2-tableau-de-bord-duo.png` | Image d'attente de D2-tableau-de-bord-duo.mp4, son dernier état : la colonne « À suivre » à gauche avec « Reprendre la lecture » sélectionné, le sujet ouvert à droite au séparateur en tireté gris. | `D2` | iPhone Duo déplié, paysage, 951 × 669 points | image d'attente de la vidéo, 2853 × 2007 px |
| `D2-cote-a-cote-ipad.png` | Maquette sur iPad en paysage, clavier externe supposé : le sujet reste visible à gauche pendant qu'on écrit une citation à droite, et un aperçu sous le texte montre le message tel qu'il sera affiché, avant l'envoi. | `D2` | iPad Pro 13 pouces, paysage, 1376 × 1032 points | maquette, 2752 × 2064 px, clavier externe supposé |
| `D2-cote-a-cote-duo.mp4` | Vidéo de 8 secondes sur iPhone Duo déplié, en paysage : le sujet à gauche, l'éditeur à droite et le clavier à l'écran en bas ; pendant la frappe, seul le haut de l'aperçu reste visible au-dessus du clavier. | `D2` | iPhone Duo déplié, paysage, 951 × 669 points | vidéo H.264, 8 s, 1902 × 1338 px, sans son, clavier à l'écran |
| `D2-cote-a-cote-duo.png` | Image d'attente de D2-cote-a-cote-duo.mp4, son dernier état : la réponse tapée, le clavier à l'écran, et l'aperçu réduit au début de la citation, au-dessus du clavier. | `D2` | iPhone Duo déplié, paysage, 951 × 669 points | image d'attente de la vidéo, 2853 × 2007 px |

## Cartes des sections de la barre latérale (`D1`)

Dans `scenarios/D1-cartes/`, une carte par section de `D1` (questions.md), 340 × 76 points @2x, fond transparent, et la planche des neuf cartes. Icônes de la barre latérale actuelle ; `flag` pour Drapeaux et `newspaper` pour À suivre, que la barre n'a pas. Le formulaire les affiche (#919), une par section, à côté de son état, copiées dans `tooling/ux-survey/web/visuels/D1-cartes/` (un test les veut identiques) ; la planche sert au test à cinq. Les noms d'icônes SF Symbols (`star.fill`, `folder.fill`, `envelope`, `flag`, `newspaper`, `bell`, `pin`, `magnifyingglass`, `gearshape`) restent pour qui refait les cartes ; le texte alternatif les dit en français.

| Fichier | Texte alternatif | Question | Appareil |
|---|---|---|---|
| `D1-cartes/D1-carte-favoris.png` | Carte « Favoris » : étoile, aujourd'hui dans le groupe Forum | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-categories.png` | Carte « Catégories » : dossier, aujourd'hui dans le groupe Forum | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-mp.png` | Carte « Messages privés » : enveloppe, aujourd'hui dans le groupe Forum | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-drapeaux.png` | Carte « Drapeaux » : drapeau, aujourd'hui dans Favoris | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-a_suivre.png` | Carte « À suivre » : journal, aujourd'hui n'existe pas | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-alertes_qualitay.png` | Carte « Alertes Qualitay » : cloche, aujourd'hui dans le groupe Outils | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-bookmarks.png` | Carte « Bookmarks » : épingle, aujourd'hui dans le groupe Outils | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-recherche.png` | Carte « Recherche » : loupe, aujourd'hui dans le groupe Plus | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-carte-reglages.png` | Carte « Réglages » : roue dentée, aujourd'hui dans le groupe Plus | `D1` | Aucun (carte seule) |
| `D1-cartes/D1-cartes-planche.png` | Les neuf cartes de la barre latérale sur trois colonnes, dans l'ordre de la question. | `D1` | Aucun (planche) |
