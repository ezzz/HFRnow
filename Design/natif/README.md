# Handoff : HFRnow, refonte de l'interface (direction « Natif calme »)

## Vue d'ensemble
HFRnow est un client iOS natif (SwiftUI) du forum Hardware.fr (HFR). Cette refonte couvre toute l'interface : catégories, listes de sujets, favoris (drapeaux), lecture, rédaction, messages privés, onglet Plus, réglages, profil, sondage, multi-comptes, états vides/chargement/erreur. Elle cible trois formats : **iPhone**, **iPhone Duo** (pliable, écran extérieur compact et écran intérieur regular) et **iPad**.

La direction retenue s'appelle **« Natif calme »**. L'app doit ressembler à une app système (Mail, Réglages) : composants SwiftUI standard, SF Pro partout, couleur d'accent réservée aux états (non lu, sélection, actions). L'identité HFR passe par le contenu : smileys GIF, citations, signatures, vocabulaire (drapeau, drapal, Qualitay…).

## À propos des fichiers de design
Les fichiers `.dc.html` de ce dossier sont des **références de design réalisées en HTML**. Ce sont des maquettes statiques qui montrent l'apparence et le comportement attendus. **Ce n'est pas du code à copier.** Il faut **recréer ces écrans en SwiftUI** dans le projet HFRnow existant, avec ses patterns, son modèle de données et sa couche réseau. Ouvrez-les dans un navigateur (avec `support.js` dans le même dossier) : chaque fichier est une grande planche à faire défiler ou zoomer.

Exception : le **rendu des messages** se fait dans une WebView (HTML/CSS). Pour cette partie, `post.css` est un vrai point de départ, à intégrer et adapter au HTML produit par le parseur actuel.

Conventions des maquettes à connaître :
- Les icônes viennent de **Material Symbols Rounded** et ne servent que de substituts. Utilisez les **SF Symbols** équivalents (tableau plus bas).
- La « Liquid Glass » est simulée en CSS (flou + transparence). Dans l'app, utilisez **les barres système d'iOS 26** (`NavigationStack` toolbar, `TabView`, `.glassEffect()` seulement là où le système ne le fournit pas). **Aucune barre custom ne doit remplacer une barre système.**
- Les données (pseudos, sujets, chiffres) sont fictives.

## Fidélité
**Haute fidélité** pour les couleurs, la typographie, la hiérarchie, les espacements et les états. Les valeurs ci-dessous sont à respecter. Elles sont exprimées en points (pt = px CSS des maquettes). Quand un composant système existe (List, Menu, Toggle, Slider, Picker segmenté, sheet, swipeActions), **préférez le composant système**, même s'il diffère de quelques points de la maquette.

---

## Contraintes plateforme (non négociables)
1. **iOS 26/27, Liquid Glass** : barres de navigation, barre d'onglets, toolbars et barre latérale sont celles du système.
2. **Contenu stable des boutons de toolbar** : un bouton ne se transforme jamais en spinner. Pendant un chargement ou un envoi, l'icône peut s'animer (`.symbolEffect(.pulse)` / `.rotate`), mais le symbole reste le même. Exemple : « Envoyer » reste `arrow.up` et pulse pendant l'envoi.
3. **Dynamic Type** partout (`.font(.body)` etc., pas de tailles fixes en dur dans SwiftUI). La WebView reçoit la taille via une variable CSS (`--body-size`).
4. **Accessibilité** : contraste AA, cibles tactiles ≥ 44 × 44 pt (y compris le bouton « ••• » des messages et les lignes en mode compact).
5. **Thèmes** : Clair, Sombre, **Noir OLED** (fond `#000000`) et Auto. Accent personnalisable par l'utilisateur.
6. **Formats** : iPhone (onglets en bas), iPhone Duo extérieur (~466 × 678 pt, compact, barres à la verticale à droite), iPhone Duo intérieur (~670 × 950 pt, regular, barre latérale + toolbars verticales à droite), iPad.

---

## Architecture de navigation

### Onglets (4)
| Onglet | SF Symbol | Badge |
|---|---|---|
| Catégories | `square.grid.2x2.fill` | – |
| Favoris | `flag.fill` | nombre de sujets avec non-lus |
| Messages | `envelope.fill` | nombre de MP non lus |
| Plus | `ellipsis` | nombre d'alertes Qualitay |

Utilisez `TabView` avec `.tabViewStyle(.sidebarAdaptable)`. Cela donne des onglets en bas sur iPhone et une barre latérale en regular (Duo intérieur, iPad). Dans la barre latérale, ajoutez une `TabSection` **« Forums »** qui liste les 17 catégories : en regular, choisir un forum ouvre directement sa liste de sous-forums.

### Compte
- iPhone et Duo extérieur : l'**avatar** est le premier élément de toolbar, en haut à gauche (`.topBarLeading`). Il ouvre un `Menu` multi-comptes.
- Duo intérieur et iPad : l'avatar et le pseudo sont en **tête de barre latérale** et ouvrent le même menu.

### Size classes et rails verticaux du Duo
- **iPhone / compact standard** : barres en haut, onglets en bas. Accessoire de barre d'onglets (`tabViewBottomAccessory`) pour la pagination des listes.
- **Duo extérieur (compact, 466 × 678)** : le système place les barres **à la verticale sur le bord droit** (rail d'environ 60 pt de large, marge 12 pt). Ordre de haut en bas :
  - groupe d'actions de navigation (avatar ou retour, puis actions de l'écran) ;
  - espace flexible ;
  - pastille de pagination verticale (▲ / page / total / ▼) ;
  - onglets verticaux (4 × 54 pt) ou, en lecture, le bouton Répondre.
  - Le contenu occupe `largeur − 78 pt`.
- **Duo intérieur (regular, 670 × 950)** : barre latérale flottante (214 pt, marges 10 pt) + colonne de contenu + rail vertical droit (56 pt). **En lecture, la barre latérale est masquée par défaut** (bouton `sidebar.right`) et le texte est centré à 600 pt max.
- **iPad** : trois colonnes `NavigationSplitView` (barre latérale, liste 360 pt, lecture). Toolbars en haut, comme sur iPhone (les rails verticaux sont propres au Duo). Lecture limitée à 640–660 pt, centrée.

> Si l'API système de placement vertical n'expose pas exactement cet ordre, gardez l'**ordre logique** des items de toolbar (navigation → actions → pagination → action principale) et laissez le système le disposer.

---

## Design tokens

### Couleurs : thème Clair
| Token | Hex | Usage |
|---|---|---|
| `bg` | `#FFFFFF` | fond des listes plain, lecture |
| `bgGrouped` | `#F2F3F5` | fond des listes groupées (Catégories, Favoris, Plus, Réglages) |
| `cell` | `#FFFFFF` | cellules groupées |
| `surface` | `#F2F3F5` | blocs de citation niv. 1, panneau smileys, bouton ••• |
| `surface2` | `#E6E8EB` | citation niv. 2, champs, pistes de slider |
| `text` | `#151618` | texte principal |
| `text2` | `#606369` | métadonnées, sous-titres |
| `text3` | `#A2A5AA` | chevrons, états désactivés |
| `separator` | `rgba(60,60,67,0.18)` | filets 0,5 pt |
| `accent` | `#2171CC` | accent par défaut (« bleu HFR ») |
| `accentSoft` | `#E4F0FF` | fond des pictos de catégorie/Plus |
| `destructive` | `#E23532` | badges rouges, Blacklister, Supprimer |

### Couleurs : thème Sombre
| Token | Hex |
|---|---|
| `bg` | `#111213` |
| `bgGrouped` | `#0A0B0D` |
| `cell` | `#191B1D` |
| `surface` | `#202224` |
| `surface2` | `#2F3033` |
| `text` | `#F0F2F4` |
| `text2` | `#A1A5AB` |
| `text3` | `#606369` |
| `separator` | `rgba(255,255,255,0.12)` |
| `accent` (texte / icônes) | `#6AA7F4` |
| `accentFill` (fonds pleins : capsules, boutons) | `#2474CF` |
| `accentSoft` | `#1B2A3C` |

### Couleurs : thème Noir OLED
Comme Sombre, avec : `bg` et `bgGrouped` = `#000000`, `cell` = `#131416`, `surface` = `#151618`, `surface2` = `#232426`.

### Accent personnalisable
Sept pastilles dans Réglages, avec la même luminosité et la même saturation (oklch L 0.55 / C 0.16) et seule la teinte qui change. Valeurs pour le thème clair :
`#2171CC` (bleu, défaut) · `#008A96` (sarcelle) · `#008A39` (vert) · `#B25400` (orange) · `#BD423A` (rouge) · `#A3489D` (magenta) · `#735CC7` (violet).
En sombre, dérivez une variante plus claire pour le texte/icônes (≈ oklch L 0.72, C 0.13) et gardez la variante 0.56 pour les fonds pleins. Le blanc sur l'accent doit rester ≥ 4,5:1.

### Avatars par défaut (sans image)
Cercle de couleur `oklch(0.62 0.13 h)`, où la teinte h est dérivée d'un hash du pseudo. Initiale en blanc, graisse 700, taille = 44 % du diamètre. Exemples : `#C86265`, `#58994A`, `#418AD1`, `#9372C8`, `#009F89`.

### Typographie (SF Pro, styles Dynamic Type)
| Rôle | Style iOS | Maquette (taille par défaut) |
|---|---|---|
| Grand titre d'écran | `.largeTitle` bold | 34 / 700 (28 sur Duo ext., 30 sur Duo int.) |
| Sous-titre de navigation | `.subheadline` | 15 / 400, `text2` (« Hardware », « 2 non lus ») |
| Titre de sujet (ligne) | `.headline` | 16 / 600, interligne 1,3, 2 lignes max |
| Méta de ligne | `.footnote` | 13 / 400, `text2` |
| Titre dans la barre (lecture) | `.subheadline` semibold | 15 / 600 + ligne 12 / 400 « Page 2 847 / 2 851 » |
| Pseudo (message) | `.subheadline` semibold | 15 / 600 |
| Date (message) | `.caption` | 12,5 / 400, `text2` |
| Corps de message (WebView) | `--body-size` | 17 / 400, interligne 1,45 |
| Auteur de citation | – | 13 / 600, couleur `accent` |
| Signature | `.caption` | 12,5 / 400, `text2` |
| En-tête de section groupée | `.footnote` semibold | 13 / 600, `text2` |
| En-tête de section Favoris | `.headline` bold | 17 / 700 |
| Libellé d'onglet | système | 10 / 600 |

### Rayons, espacements, ombres
- Cellules groupées : conteneur inset, **rayon 24**, marge horizontale 16 (12 sur Duo). Comportement par défaut de `List(.insetGrouped)` sur iOS 26.
- Citation niv. 1 : rayon **12**, padding 10 × 12. Niv. 2 : rayon **9**, padding 8 × 10.
- Images dans un message : rayon 12, largeur 100 %.
- Pictos de catégorie : carré 30 × 30, rayon 8, fond `accentSoft`, symbole 19 pt rempli en `accent`.
- Capsule de compteur : hauteur 21, padding horizontal 7, rayon 11, fond `accentFill`, texte blanc 13 / 600.
- Pastille non-lu : cercle 10 pt plein `accent`. Sujet suivi à jour : **anneau** 10 pt, trait 1,5 pt `accent`.
- Badge rouge (onglets, Qualitay) : hauteur 18, rayon 9, `destructive`, 12 / 600 blanc.
- Marges de page : 20 pt sur iPhone, 16 pt sur Duo, 24 pt en lecture sur Duo int., 28 pt sur iPad.
- Menus et popovers : système (`Menu`, `.popover`). En maquette, rayon 22 à 26 et ombre `0 18 50 rgba(0,0,0,.22)` (clair) / `.6` (sombre).
- Bouton d'action principal flottant (Répondre, Envoyer) : cercle 52 (54 sur Duo), fond `accentFill`, symbole 24 pt blanc. En lecture, il est placé dans la toolbar du bas, à droite.

### Correspondance des icônes (Material → SF Symbols)
`grid_view` → `square.grid.2x2.fill` · `flag` → `flag.fill` · `star` → `star.fill` · `mail` → `envelope.fill` · `more_horiz` → `ellipsis` · `search` → `magnifyingglass` · `edit_square` → `square.and.pencil` · `chevron_left/right` → `chevron.left/right` · `keyboard_arrow_up/down` → `chevron.up/down` · `first_page/last_page` → `chevron.left.to.line` / `chevron.right.to.line` · `keep` → `pin.fill` · `lock` → `lock.fill` · `format_quote` → `quote.opening` · `playlist_add` → `text.badge.plus` · `person` → `person` · `link` → `link` · `report` → `exclamationmark.bubble` · `block` → `nosign` · `dock_to_right` → `sidebar.right` · `filter_list` → `line.3.horizontal.decrease` · `close` → `xmark` · `visibility` → `eye` · `arrow_upward` → `arrow.up` · `format_bold/italic/underlined` → `bold` / `italic` / `underline` · `add_photo_alternate` → `photo.badge.plus` · `visibility_off` (spoiler) → `eye.slash` · `mood` → `face.smiling` · `gif_box` → `gift` ou un symbole custom « GIF » · `mark_chat_read` → `checkmark.message` · `delete` → `trash` · `switch_account` → `person.2.circle` · `bookmark` → `bookmark.fill` · `campaign` → `megaphone.fill` · `settings` → `gearshape.fill` · `gavel` → `book.closed.fill` · `favorite` → `heart.fill` · `ballot` → `chart.bar.fill` · `wifi_off` → `wifi.slash` · `done_all` → `checkmark.circle` · `person_add` → `person.badge.plus` · `manage_accounts` → `person.crop.circle.badge.gearshape` · `logout` → `rectangle.portrait.and.arrow.right` · `ios_share` → `square.and.arrow.up` · `brightness_low/high` → `sun.min` / `sun.max`.

---

## Composants réutilisables (à créer en SwiftUI)

### `TopicRow`
- Disposition : gouttière d'état 12 pt à gauche (pastille ou anneau, alignée sur la 1re ligne du titre), puis une colonne :
  - ligne 1 : titre (2 lignes max), précédé de `pin.fill` / `lock.fill` en 15 pt `text2` si le sujet est épinglé ou verrouillé ; `CountCapsule` des non-lus à droite ;
  - ligne 2 : « 2 851 pages · Kaiju » à gauche, heure (« 14:32 », « Hier », « Lun. », « 12/03/24 ») à droite.
- Padding vertical 12, séparateur inséré (part du début du texte, pas de la gouttière).
- États : non lu (pastille + capsule), suivi à jour (anneau), neutre (rien).
- **Mode compact** : titre sur 1 ligne (15 / 600), méta fusionnée « 2 851 p. · Kaiju · 14:32 » (12 pt), hauteur ≥ 44 pt, capsule centrée verticalement.
- Swipe (Favoris) : `.swipeActions(edge: .trailing)` avec **« Lu »** (`accentFill`, `checkmark.message`) et **« Retirer »** (`destructive`, `trash`). Un glissement complet = marquer lu.

### `FavoriteRow` (variante de TopicRow)
Icône de type en tête (18 pt) : `flag.fill` = sujet où l'utilisateur a posté (drapeau HFR), `star.fill` = favori. En `accent` s'il y a des non-lus, en `text3` si le sujet est à jour. Méta : « dernier posteur · heure » à gauche, « p. 2 847 / 2 851 » (dernière page lue / total) à droite. Titre en 600 si non lu, en 400 sinon.

### `SectionHeader`
- Variante groupée : 13 / 600 `text2`, padding haut 22, bas 8.
- Variante Favoris, repliable : nom de la catégorie en 17 / 700, chevron `chevron.down` (ouverte) / `chevron.right` (repliée) en `accent`, zone tactile ≥ 44 pt. Repliée, elle affiche « 4 sujets · 23 non lus » en `text2`. Utilisez `Section(isExpanded:)`.

### `CategoryRow`
Picto 30 pt (voir tokens), nom (17 regular), nombre de sous-forums en `text2` à droite, chevron `text3`. Hauteur minimale 52.

### `CountCapsule`, `UnreadDot`, `TabBadge`
Voir les tokens. `TabBadge` = `.badge()` du système sur les onglets.

### `Avatar`
Tailles 26 (compact), 32 (toolbar), 34 (comptes), 36 (message), 44 (MP), 56 (Plus), 88 (profil). Image distante si elle existe, sinon cercle coloré avec l'initiale.

### `MessageCard` (rendu HTML dans la WebView, voir `post.css`)
- En-tête : avatar 36 · colonne (pseudo 15 / 600 ; « Aujourd'hui, 14:02 · modifié » 12,5 `text2`) · bouton « ••• » (cercle 30 `surface` dans une zone tactile de 44). Dans un MP, les messages de l'utilisateur portent « (vous) » après le pseudo.
- Corps : 17 / 1,45, `text-wrap: pretty`. Les **smileys GIF** restent inline (`vertical-align: -3px`), à leur taille native × `--smiley-scale` (1, 1,5 ou 2). Liens en `accent` soulignés (offset 3 px).
- Citations : bloc `surface`, rayon 12, en-tête « Grumly a écrit : » 13 / 600 `accent`, texte 15 pt à 85 % d'opacité. Une **citation imbriquée** prend `surface2`, rayon 9, texte 14 pt. Au-delà de 2 niveaux, gardez `surface2` et réduisez seulement le padding.
- Images : largeur 100 %, rayon 12. Vidéos selon le réglage (Toujours / Au toucher / Jamais).
- Signature : filet 0,5 pt, puis 12,5 pt `text2`. Masquée si le réglage est désactivé.
- Séparation entre messages : filet 0,5 pt pleine largeur. Padding 14 / 20 / 18.
- **Mode compact** : avatar 26 en ligne avec pseudo et heure (une seule ligne d'en-tête), corps 15 pt, padding 8 / 20 / 12.
- Les messages filtrés (blacklist, mots-clés) sont **repliés**, jamais supprimés : une ligne « Message de X masqué · Afficher ».
- Le bouton « ••• » envoie un message JS → natif (`window.webkit.messageHandlers.postAction.postMessage({id})`), et le natif présente le **menu système** ancré sur le bouton.

### `PollCard` (dans le 1er message, en HTML)
- Bloc `surface`, rayon 16, padding 14.
- Contenu de haut en bas :
  - eyebrow « SONDAGE » 12 / 600 avec icône ;
  - question 17 / 600 ;
  - options (44 pt chacune) avec bouton radio 22 pt ;
  - bouton « Voter » (capsule 44 pt `accentFill`) ;
  - pied « 1 284 votes · clôture le 31/12 ».
- **Après vote** : barres de 44 pt, rayon 12, fond `surface2`, remplissage proportionnel au pourcentage (en `accentSoft`, ou `accentFill` + coche pour le choix de l'utilisateur), pourcentage à droite 15 / 600.

### `EmptyState`
Pastille 84 pt (`surface`) avec un symbole de 40 pt `text2` · titre 21 / 700 (`text-wrap: balance`) · phrase 15 pt `text2`, 290 pt de large max · action principale (capsule 48 pt `accentFill`), éventuellement une action secondaire (capsule 44 pt `surface`, texte `accent`). Équivalent de `ContentUnavailableView` avec des actions.

### `PageControl`
- Horizontal (iPhone, iPad) : capsule de verre 48 pt, avec `chevron.left` · « Page 1 / 500 » (15 / 600) · `chevron.right`. Sur iPad, ajoutez première / dernière page.
- Vertical (Duo) : pastille de 52 pt de large, avec `chevron.up` · numéro courant · filet de 18 pt · total en `text2` · `chevron.down`.
- Le précédent est désactivé (`text3`) en page 1, et le suivant est en `accent`.
- **Toucher le numéro ouvre « Aller à la page »** : popover sur grand écran, sheet en détente moyenne sur iPhone. Contenu :
  - champ numérique pré-rempli (page courante) avec « / 2 851 » ;
  - slider ;
  - trois raccourcis : Première, 1er non lu, Dernière ;
  - bouton « Aller ».

---

## Écrans

Référence visuelle : les identifiants (2a, 3b…) correspondent aux badges des fichiers HTML.

### 2a · Catégories (`HFRnow Natif - Lot 1.dc.html`)
- `List(.insetGrouped)` en 4 sections :
  - **Matériel** : Hardware, Hardware – Périphériques, Ordinateurs portables, Overclocking cooling & modding, Électronique & DIY, Apple ;
  - **Multimédia** : Vidéo & son, Photo numérique, Jeux vidéo, Graphisme ;
  - **Logiciels** : Windows & logiciels, Linux & OS alternatifs, Réseaux & domotique, Programmation ;
  - **Communauté** : Achats & ventes, Emploi & études, Discussions.
  - Les noms et les regroupements sont à aligner sur les vraies catégories HFR.
- Toolbar : avatar (gauche), recherche (droite).
- Regular : les forums sont dans la barre latérale. La colonne de contenu affiche « Hardware », le sous-titre « Choisissez un sous-forum », puis « Tous les sujets » (en `accent`) et la liste des sous-forums.

### 2b · Liste des sujets
- Grand titre = nom du sous-forum + `chevron.down`, sous-titre = catégorie parente. **Toucher le titre ouvre un `Menu`** : « Tous les sous-forums », séparateur, puis les sous-forums, avec une coche sur le courant (`ToolbarTitleMenu`).
- Picker segmenté : **Tous / Favoris / Suivis / Lus**.
- Lignes `TopicRow`. Les sujets épinglés sont en tête.
- Pagination « Page 1 / 500 » : accessoire de la barre d'onglets sur iPhone, pastille verticale dans le rail du Duo, capsule en bas de colonne sur iPad.
- Toolbar : avatar · recherche · nouveau sujet (`square.and.pencil`).

### 2c · Favoris
- Grand titre « Favoris », sous-titre « 204 messages non lus » (total).
- Une section repliable par catégorie (`SectionHeader` Favoris), avec des `FavoriteRow` et des actions de swipe.
- Toolbar : avatar · filtre « Non lus uniquement » (`line.3.horizontal.decrease`, rempli + fond sélection quand il est actif) · recherche.
- Toucher une ligne ouvre le sujet **à la première page non lue, au premier message non lu**.

### 2d · Lecture d'un sujet
- Barre : retour · titre (1 ligne, tronqué) + « Page 2 847 / 2 851 » · groupe [drapeau `flag.fill` en `accent` (suivre / ne plus suivre), `ellipsis` (actions du sujet)].
- Contenu : une WebView par page (ou une WebView continue), avec des `MessageCard`.
- Toolbar du bas : `PageControl` + Répondre (`square.and.pencil`, plein `accentFill`).
- **Menu d'actions d'un message** (menu système, avec séparateurs épais entre les groupes) :
  1. Citer · Ajouter à la multi-citation
  2. Envoyer un MP · Voir le profil · Copier le lien
  3. Alerter la modération · **Blacklister {pseudo}** (destructif). Si le pseudo est déjà blacklisté : « Retirer de la blacklist ». Ajoutez « Whitelister » dans le même groupe si cela s'applique.
- Duo intérieur : barre latérale masquée, colonne de 600 pt centrée. Le rail contient : barre latérale, retour, puis drapeau et menu, puis pagination et Répondre.

### 3a · Rédaction d'une réponse (`Lot 2`)
- **Sheet** plein écran (détente large).
- Barre : fermer (`xmark`) · « Répondre » + titre du sujet (12 pt `text2`) · groupe [aperçu `eye`, envoyer (cercle 40 `accentFill`, `arrow.up`)].
- Éditeur BBCode, 17 pt :
  - balises (`[quote=56931,Kaiju]`, `[/quote]`, `:jap:`) en **SF Mono 14 `text2`** ;
  - texte cité estompé (`text2`) ;
  - le reste en `text`.
  - Coloration via `AttributedString`.
- Barre de mise en forme au-dessus du clavier (capsule de verre 48 pt) : gras, italique, souligné, citation, lien, image, spoiler, smileys, GIF.
- **Panneau smileys** (remplace le clavier, ~356 pt, fond `surface`) :
  - champ « Rechercher un smiley ou un mot-clé » (40 pt, rayon 20, `surface2`) ;
  - segmenté **Récents / HFR / Persos / GIF** ;
  - grille de 7 colonnes en 46 pt (6 sur le Duo intérieur), smileys à 1,3×.
  - Toucher un smiley insère son code.
- **GIF** : recherche « Rechercher sur Giphy », mosaïque de 3 colonnes (rayon 10), mention obligatoire « Powered by GIPHY ».
- **Images** : vignettes de 72 pt (rayon 12) avec une barre de progression d'envoi de 4 pt en bas (fond `accentFill`), et une case « + » en pointillés 1,5 pt. Libellé « Images · envoi 60 % ».
- Regular : éditeur et **aperçu** côte à côte (deux colonnes égales, filet vertical). L'aperçu rend la `MessageCard` réelle sur fond `bgGrouped`, dans une carte blanche de rayon 20.
- Envoi : la flèche **pulse** sans être remplacée. En cas d'erreur, une alerte s'affiche et le brouillon est conservé.

### 3b · Messages privés
- Liste (comme Mail) : pastille non lu (10 pt) · avatar 44 · ligne 1 : correspondant 16 / 600 + heure 14 `text2` + chevron · ligne 2 : sujet 15 pt (600 si non lu) · ligne 3 : aperçu 15 `text2`, 2 lignes max. Recherche sous le grand titre. Toolbar : nouveau MP.
- Conversation : barre « sujet » + « avec Grumly · 3 messages », mêmes `MessageCard`, bouton Répondre flottant en bas à droite.
- Duo intérieur : liste (262 pt) et conversation côte à côte, barre latérale repliée.

### 3c · Plus
- Carte compte : avatar 56, pseudo 19 / 600, « Voir mon profil », puis « Changer de compte · 2 comptes ».
- Sections :
  - **Forum** : Recherche sur le forum, Bookmarks (12), Alertes Qualitay (badge rouge, qui remonte sur l'onglet Plus) ;
  - **Application** : Réglages ;
  - **À propos** : Charte du forum, Crédits.
- Section isolée : **Supprimer mon compte** (texte `destructive`), avec la note « Le compte HFR est supprimé côté forum. Cette action est irréversible. » Une confirmation est obligatoire (`confirmationDialog` + saisie du pseudo).

### 3d · Réglages
`Form` groupé.
- **Apparence**
  - Thème : segmenté **Auto / Clair / Sombre / OLED**.
  - Luminosité du thème : slider avec `sun.min` / `sun.max`.
  - Teinte d'accent : 7 pastilles de 36 pt ; la sélection a un anneau de 2,5 pt espacé de 2 pt.
  - Icône de l'app : 4 vignettes de 60 pt, rayon 15 (Classique, Sombre, Teintée, Rétro ; visuels à fournir), sélection par anneau.
- **Lecture**
  - Taille du texte : slider A / A.
  - Style des messages : menu, « Pleine largeur ».
  - Taille des smileys : segmenté **1× / 1,5× / 2×**.
  - Mode compact : toggle, sous-titre « Listes et messages plus serrés ».
  - Afficher les signatures : toggle.
  - Vidéos intégrées : menu « Toujours / Au toucher / Jamais ».
- **Notifications** : Nouveaux messages privés (toggle).
- **Filtres de posts** : Blacklist (3), Whitelist (1), Mots-clés masqués (2). Pied de section : « Les messages filtrés sont repliés, jamais supprimés : un toucher suffit à les afficher. »
- Regular (Duo intérieur) : liste à gauche (340 pt) et **aperçu en direct** d'une `MessageCard` à droite, mis à jour à chaque réglage.

### 4a · Profil utilisateur (`Lot 3`)
- En-tête centré : avatar 88, pseudo 26 / 700, « Membre depuis mars 2009 ».
- Trois actions rapides (tuiles de 60 pt, rayon 16, fond `cell`, texte et icône `accent`) : MP, Ses messages, Plus.
- Section Infos : Messages, Inscription, Dernière visite, Localisation (valeurs à droite).
- Sections Configuration et Signature (texte libre).
- Section isolée : « Ajouter à la whitelist » (`accent`) et « Blacklister {pseudo} » (`destructive`).
- iPhone : poussé dans la pile. Duo intérieur et iPad : **sheet centrée de 440 pt** au-dessus de la lecture.

### 4b · Sondage
Voir `PollCard`. Il est affiché dans le premier message de la page 1. Les états avant et après vote sont dans le fichier.

### 4c · Multi-comptes
- **Menu avatar** :
  - comptes (avatar 34, pseudo, sous-titre « Compte actif » ou « 2 MP non lus », coche sur l'actif) ;
  - Ajouter un compte ;
  - Gérer les comptes ;
  - séparateur ;
  - Se déconnecter (destructif).
- **Ajouter un compte** (sheet) :
  - texte d'aide centré ;
  - champs Pseudo / Mot de passe (cellules groupées, libellé de 110 pt) ;
  - bouton « Se connecter » (capsule 50 pt) ;
  - note « Les identifiants sont stockés dans le trousseau iOS. » ;
  - lien « Créer un compte sur hardware.fr ».
- **Gérer les comptes** : liste avec swipe pour retirer un compte, et « Ajouter un compte » en `accent`. Pied : les notifications de MP sont reçues pour tous les comptes.
- Changer de compte recharge les onglets (favoris, MP, badges) sans quitter l'onglet courant.

### 4d · États vides, chargement, erreur
- **Non connecté** (Favoris, MP) : avatar remplacé par une silhouette, `EmptyState` « Connectez-vous pour accéder aux favoris » / « Vos drapeaux et favoris HFR apparaîtront ici, groupés par catégorie. », avec les actions [Se connecter] [Créer un compte].
- **Chargement** : squelettes qui reprennent la forme des `TopicRow` (barres de 14 pt de haut, rayon 7, `surface2`, largeurs variées, 2 ou 3 barres par ligne). Les barres, le segmenté et la pagination restent en place **avec leur contenu**. Un léger shimmer est possible ; respectez *Réduire les animations*.
- **Erreur réseau** (lecture) : `EmptyState` avec `wifi.slash`, « Impossible de charger la page 2 848 » / « Vérifiez votre connexion. Les pages déjà lues restent disponibles hors ligne. », avec les actions [Réessayer] [Revenir à la page 2 847]. Le rail et la toolbar restent utilisables.
- **Vide après filtre** : `checkmark.circle`, « Tout est lu » / « Aucun message non lu dans vos 42 sujets suivis. », avec l'action [Afficher tous les favoris]. Le bouton filtre reste visiblement actif.

### 4e · iPad
- Paysage 11" (1 180 × 820) en trois colonnes : barre latérale 214 · liste 360 (sujet ouvert surligné avec le fond de sélection) · lecture.
- Lecture : titre centré dans la barre, [drapeau, menu] à droite, `PageControl` complet centré en bas + Répondre.
- Barre latérale masquée : liste 380 + lecture, texte à 660 pt max. La lecture gagne de la marge, pas de la longueur de ligne.

---

## Interactions et comportement
- **Ouvrir un sujet** depuis une liste ou les favoris : arriver au premier message non lu (ancre). Si tout est lu, arriver à la dernière page.
- **Pagination** : ▲▼ / ‹ › changent de page. Toucher le numéro ouvre « Aller à la page ». Sur iPhone, un swipe horizontal entre pages est envisageable (à valider).
- **Drapeau dans la barre de lecture** : bascule suivi / non suivi, avec `.symbolEffect(.bounce)` et un retour haptique léger.
- **Swipe dans Favoris** : vers la gauche « Lu » / « Retirer ». Le glissement complet déclenche « Lu ». Annulation possible via un toast.
- **Sections repliables** : l'état est mémorisé par catégorie (`@AppStorage`).
- **Menus** : uniquement des `Menu` / `contextMenu` système. Un appui long sur un message ouvre le même menu que « ••• ».
- **Rédaction** : le brouillon est sauvegardé automatiquement par sujet. La multi-citation alimente l'éditeur.
- **Animations** : celles du système uniquement (push, sheet, menu). Les icônes peuvent être animées via `symbolEffect`. Pas de transitions custom.
- **Retour haptique** : envoi réussi (`.success`), marquer lu (`.light`).

## État (suggestion)
- `AppSettings` (`@Observable`, persistant) : `theme` (auto/light/dark/oled), `themeBrightness`, `accentHue`, `appIcon`, `textSizeOffset` (en plus de Dynamic Type), `postStyle`, `smileyScale` (1 / 1,5 / 2), `compactMode`, `showSignatures`, `videoMode` (always/tap/never), `notifyPM`, `blacklist`, `whitelist`, `mutedKeywords`.
- `AccountStore` : comptes (Keychain), `activeAccountID`, badges par compte (MP non lus).
- `TopicListState` : `forum`, `subforum`, `filter` (all/favorites/followed/read), `page`, `pageCount`, `loadState` (idle/loading/loaded/error).
- `TopicReaderState` : `topic`, `page`, `pageCount`, `firstUnreadAnchor`, `isFollowed`, `loadState`, `multiQuote: [PostID]`.
- `ComposerState` : `text` (BBCode), `attachments` (avec progression), `panel` (keyboard/smileys/gif), `smileySearch`, `isSending`, `showPreview`.
- `FavoritesState` : sections par catégorie, `expanded: Set<CategoryID>`, `unreadOnly`.

## Pont WebView ↔ natif
- Le natif injecte les variables CSS à chaque changement de réglage (`document.documentElement.style.setProperty(...)`) : thème (`data-theme="light|dark|oled"` sur `<html>`), `--accent`, `--body-size` (selon Dynamic Type), `--smiley-scale`, et la classe `compact` sur `<body>`.
- Messages JS → natif : `postAction` (id du message + rect du bouton, pour ancrer le menu), `openProfile`, `openLink`, `openImage`, `vote` (sondage), `showFiltered`.
- Le HTML d'un message doit suivre la structure de `post.css` (`.post`, `.post-head`, `.avatar`, `.pseudo`, `.date`, `.edited`, `.post-menu`, `.post-body`, `.quote`, `.quote-author`, `img.smiley`, `.signature`, `.poll`…).

## Assets
- **Smileys HFR** : GIF servis par `https://forum-images.hardware.fr/icones/` (officiels : `smile.gif`, `wink.gif`, `redface.gif`, `smilies/lol.gif`…) et smileys persos du forum. Cache local recommandé.
- **GIF** : API Giphy (clé à fournir, attribution obligatoire).
- **Icônes d'app alternatives** : 4 visuels à produire (Classique, Sombre, Teintée, Rétro). Les maquettes ne contiennent que des emplacements.
- **Icônes d'interface** : SF Symbols (correspondances ci-dessus).
- **Images** des maquettes : simples emplacements rayés.

## Fichiers
| Fichier | Contenu |
|---|---|
| `HFRnow Natif - Lot 1.dc.html` | 2e composants, thèmes et CSS · 2a Catégories · 2b Liste des sujets · 2c Favoris · 2d Lecture |
| `HFRnow Natif - Lot 2.dc.html` | 3a Rédaction · 3b Messages privés · 3c Plus · 3d Réglages |
| `HFRnow Natif - Lot 3.dc.html` | 4a Profil · 4b Sondage · 4c Multi-comptes · 4d États · 4e iPad |
| `HFRnow Directions.dc.html` | Exploration initiale des 4 directions ; seule la **1a « Natif calme »** est retenue. Pour contexte uniquement. |
| `post.css` | CSS de référence pour les messages dans la WebView (tokens des 3 thèmes, citations, smileys, signature, sondage, mode compact, messages filtrés) |
| `support.js` | Runtime nécessaire pour ouvrir les `.dc.html` dans un navigateur |

Chaque écran apparaît sur trois cadres : **iPhone** (393 × 852), **Duo extérieur** (466 × 678) et **Duo intérieur** (670 × 950), plus deux cadres iPad (1 180 × 820). La colonne de notes à gauche de chaque écran résume les règles d'adaptation.

## Ordre d'implémentation conseillé
1. `Theme` (tokens des 3 thèmes + accent dynamique), `AppSettings`.
2. `TabView(.sidebarAdaptable)` + navigation, menu compte.
3. `TopicRow`, `CategoryRow`, `SectionHeader`, `CountCapsule`, `Avatar`, `EmptyState`, squelettes.
4. Catégories, liste des sujets (menu de sous-forum, segmenté, pagination), Favoris (sections, swipe).
5. Lecture : `post.css`, pont JS, menu d'actions, `PageControl` + « Aller à la page ».
6. Rédaction (éditeur BBCode, smileys, Giphy, images, aperçu).
7. MP, Plus, Réglages (avec aperçu), Profil, Sondage, Multi-comptes.
8. Vérifications Duo extérieur / intérieur et iPad, Dynamic Type XXL, VoiceOver, contrastes en OLED.
