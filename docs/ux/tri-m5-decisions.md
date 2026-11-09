# Tri des propositions M5 : décisions du PO et suite

Date : 6 novembre 2026. Tri fait par le PO dans le tableau [Tri des propositions M5](https://claude.ai/artifact/6F8omW1so6MDW4Z1s2U1yx), à partir de l'audit `docs/ux/audit-m5-ux-ui.md`. Les impacts et complexités sont restés à l'estimation de départ : aucun n'a été corrigé.

## 1. Résultat brut

| Décision | Nombre |
|---|---|
| Oui | 20 |
| Peut-être | 9 |
| Non | 10 |

Écarts avec ma recommandation de départ :
- **Passés en Oui** : barre de mise en forme (LOT-174), création de sondage (LOT-100), MP à plusieurs destinataires (LOT-182), notifications MP fines (#509), raccourcis clavier (LOT-149), thèmes saisonniers.
- **Passés en Non** : plateau de citations (LOT-153), scrubber de pages (LOT-112), aperçu serveur (LOT-184).

## 2. Lignes directrices tirées des notes du PO

1. **Donner de la place au contenu.** C'était la ligne de la refonte Swift V4. Prudence sur tout élément visuel permanent ajouté au lecteur. C'est la raison du Non sur le scrubber.
2. **L'iPad est le terrain de la plus-value.** Le design iPhone est assez figé. Les ajouts qui demandent de l'espace, comme « À suivre » ou l'aperçu avant envoi, se discutent sur iPad uniquement.
3. **Ne pas rouvrir ce qui a été réglé après la 4.0.** La citation et la multi-citation ont été améliorées en 4.0.2. Le sujet est clos.
4. **Le legacy de référence est l'app actuelle.** Beaucoup de notes disent « déjà traité en legacy ». Une partie de M5 n'est donc pas une évolution, mais une fonction déjà livrée que le portage doit reprendre.

## 3. Reclassement

### 3.1 Déjà dans l'app actuelle : parité, pas évolution

Le rapport d'écarts du portage compare au commit `2440d79`, antérieur aux versions 4.0.1 à 4.0.4. Ces fonctions y apparaissent donc comme nouvelles, alors que les utilisateurs les ont déjà. Les reporter en M5 créerait une régression visible au passage à SwiftHFR.

| ID | Proposition | Note du PO | Action proposée |
|---|---|---|---|
| X-PLUS | Modes du bouton + | Existe déjà, garder le comportement legacy | Lot de parité M4 |
| X-ICONES | Icônes des catégories | Déjà implémenté en legacy | Lot de parité M4 |
| LOT-146 | Multi-fenêtre iPad | Déjà traité en legacy | Remonter en M4 |
| LOT-149 | Raccourcis clavier | Déjà traité en legacy | Vérifier sur `master`, puis remonter en M4 |
| LOT-179 | Taille des caches et vidage | Déjà traité en legacy | Remonter en M4 |
| LOT-138 | Liens HFR ouverts dans l'app | Déjà traité, avec le réglage associé | Remonter en M4 pour la partie existante |
| LOT-174 | Barre de mise en forme | Déjà présente en 4.0.2 ou 4.0.3 | Remonter en M4 |
| LOT-101 | Brouillons archivés | — | Remonter en M4, existe depuis 4.0.1 |
| LOT-181 | Suppression de MP, membres d'un groupe | — | Suppression en M4, existe depuis 4.0.1 ; membres en M5 |
| I-513 | Visionneuse HD | Déjà implémenté, à étendre à d'autres hébergeurs | Base en M4 déjà livrée ; extension en M5 |

**Conséquence pour l'orchestration :** la note de convergence n°1 du rapport d'écarts, le choix de la révision de référence, doit être tranchée en faveur de l'app actuelle sur `master`. Sinon d'autres fonctions livrées en 4.0.x risquent le même sort.

### 3.2 Oui : vraies évolutions à faire

| ID | Proposition | Impact | Complexité | Condition |
|---|---|---|---|---|
| LOT-110 | Navigateur de pages depuis le titre | Moyen | Faible | Aucune |
| X-NEWS | Écran « Quoi de neuf » | Moyen | Faible | Aucune |
| LOT-100 | Création de sondage | Faible | Moyenne | Capture du formulaire (#170) |
| LOT-182 | MP à plusieurs destinataires | Faible | Moyenne | Sans l'entrée depuis un profil |
| I-509 | Notifications MP fines, sourdine | Faible | Moyenne | Transformer l'issue en lot |
| I-513 | Plus d'hébergeurs pour la visionneuse | Moyen | Moyenne | Captures de paires d'URL |
| LOT-147 | Colonnes iPhone Duo et iPad | Fort | Élevée | Document de design Phase 5 |
| X-SAISON | Thèmes saisonniers étendus | Moyen | Moyenne | Aucune |

### 3.3 Oui sous réserve de vérification

| ID | Proposition | Ce qu'il faut vérifier |
|---|---|---|
| LOT-142 | Reconnexion quand la session expire | Le problème est peut-être ancien et déjà réglé dans l'app actuelle |
| LOT-145 | Restauration d'état par scène | Les bugs iPad sont peut-être déjà corrigés ; [ezzz/HFRnow#512](https://github.com/ezzz/HFRnow/issues/512) en traite un en M4 |
| X-TEINTE | Teinte des lignes par drapeau | À étudier, en cohérence avec la ligne « place au contenu » |

### 3.4 Peut-être

| ID | Proposition | Note du PO |
|---|---|---|
| LOT-148 | Lecture continue | Un des premiers candidats à l'étude UX |
| LOT-143, LOT-144 | Écran « À suivre » | Non sur iPhone, oui sur iPad comme vraie plus-value |
| LOT-152 | Aperçu avant envoi | Non sur iPhone, pourquoi pas sur iPad |
| LOT-178 | Bannière « Nouveau » | Améliorer le repère, sans forcément aller aussi loin qu'une bannière |
| LOT-177 | Swipes uniformes | À étudier |
| LOT-154 | « On t'a cité » | Difficile, le forum ne donne pas l'information. **Contre-proposition** : améliorer le design de « Filtrer les posts » et le rendre plus facile à déclencher |
| LOT-141 | « Vérifier HFR » | À étudier, en lien avec la détection des citations |
| X-DIAG | Envoi de diagnostics | — |

### 3.5 Non

LOT-153 plateau de citations, LOT-112 scrubber, LOT-184 aperçu serveur, LOT-151 refus des emoji, LOT-175 suppression du premier post, LOT-183 avis AQ, LOT-180 accent unique, Spotlight (LOT-150), thème selon l'heure, actions rapides d'icône.

Pour LOT-153, l'issue [ezzz/HFRnow#243](https://github.com/ezzz/HFRnow/issues/243) et FEAT-006 restent ouvertes côté orchestration. Il faudra les fermer en « non planifié » avec la raison, pour qu'aucun agent ne les reprenne.

## 4. Sélection pour le questionnaire UX

Critère : on ne soumet aux utilisateurs que ce qui reste ouvert et dont la forme dépend de leur usage. Les Oui simples se font sans attendre. Les Non et la parité ne figurent pas dans le questionnaire.

Structure retenue :
1. Questions de profil.
2. Question d'ouverture sur l'appétit de nouveauté.
3. Thème 1 : lecture d'un long sujet.
4. Thème 2 : ce que l'iPad et le Duo apportent en plus.
5. Cartes de réaction sur les idées, suivies d'une question ouverte et d'une question sur les messages privés.
6. Champ libre.

Tous les libellés sont écrits du point de vue de l'utilisateur, sans jargon technique.

### 4.1 Questions de profil

Trois questions en ouverture, pour lire ensuite les réponses par groupe. Sans elles, le thème iPad et Duo serait noyé dans la majorité iPhone, et on ne verrait pas si les anciens utilisateurs sont plus conservateurs que les nouveaux.

| Question | Réponses |
|---|---|
| Sur quel appareil utilisez-vous surtout l'app ? | iPhone · iPad · iPhone Duo · plusieurs |
| Comment utilisez-vous le forum ? | Je lis surtout · Je lis et je réponds parfois · Je poste souvent |
| Depuis quand utilisez-vous l'app ? | Avant la version 4.0 · Depuis la 4.0 |

### 4.2 Question d'ouverture

« Pour la suite, vous préférez que l'app : reste comme elle est · évolue par petites touches · ose des nouveautés. »

Elle mesure directement le niveau de conservatisme, croisé avec le profil.

### 4.3 Thème 1 : lecture d'un long sujet

Porte sur LOT-148 et LOT-178, avec LOT-110 déjà décidé. Deux scénarios seulement :

| Scénario | Ce que voit l'utilisateur |
|---|---|
| **Pages améliorées** | Les pages restent. Changement de page instantané, sans écran blanc. Aller directement à une page depuis le titre. Séparateur des nouveaux messages plus visible et qui ne bouge pas pendant le chargement des images. Messages masqués par la liste noire remplacés par une ligne qu'on déplie d'un geste. Texte à la taille du réglage iOS. |
| **Lecture continue en option** | Tout ce qui précède, plus un réglage, désactivé par défaut, qui charge la page suivante au bas de la page en cours, avec un repère discret du numéro de page. |

**Décision du PO, 7 novembre 2026** : le lecteur garde la WebView pour le moment ; le rendu natif sera une décision technique ultérieure, hors questionnaire. Le scénario « pages améliorées » ne présente donc que des améliorations possibles avec la WebView : la plupart existent déjà dans le lecteur de SwiftHFR, et le changement de page instantané relève du préchargement. Le swipe qui suit le doigt et la position à la ligne près, réservés au rendu natif, ne sont pas présentés.

Question : un choix entre les deux scénarios, puis « Qu'est-ce qui vous manquerait avec ce choix ? ».

### 4.4 Thème 2 : ce que l'iPad et le Duo apportent en plus

Porte sur LOT-147, LOT-143, LOT-144, LOT-152 et le contenu de la barre latérale. Posé seulement aux répondants iPad, Duo ou plusieurs appareils.

**Partie A : la barre latérale.** Ce qu'elle contient décide de l'intérêt des deux autres colonnes. Si elle déplie favoris ou MP, la colonne du milieu devient redondante ; si elle reste un menu, la colonne du milieu porte tout.

Exercice de tri de cartes : l'utilisateur garde les sections qu'il veut voir en permanence, les ordonne, et indique celles qu'il voudrait pouvoir déplier.

| Section proposée | Aujourd'hui |
|---|---|
| Favoris | Groupe Forum |
| Catégories | Groupe Forum |
| Messages privés | Groupe Forum |
| Drapeaux | Dans Favoris |
| À suivre (nouveautés de tous les sujets suivis) | N'existe pas |
| Alertes Qualitay | Groupe Outils |
| Bookmarks | Groupe Outils |
| Recherche | Groupe Plus |
| Réglages | Groupe Plus |

**Partie B : la disposition.** Trois scénarios :

| Scénario | Ce que voit l'utilisateur |
|---|---|
| **Comme aujourd'hui** | Barre latérale, liste, sujet ; sur le Duo, l'interface iPhone sur l'écran extérieur |
| **Tableau de bord « À suivre »** | Sur iPad et Duo déplié, une colonne « À suivre » : reprise de lecture, MP, favoris et drapeaux avec nouveautés |
| **Lecture et écriture côte à côte** | Sur iPad et Duo déplié, le sujet reste visible pendant la rédaction, avec un aperçu du message avant envoi |

Pour le Duo, prévoir une bêta TestFlight où les dispositions s'essaient derrière un réglage, et des vidéos courtes dans le questionnaire pour ceux qui n'ont pas l'appareil.

### 4.5 Cartes de réaction

**But.** Les fonctions se feront vite : l'intérêt n'est pas de les classer, mais de mesurer l'appétit de nouveauté et de faire émerger d'autres idées.

**Format.** Une carte par idée, une phrase de description, trois réactions : « J'adore » · « Pourquoi pas » · « Inutile pour moi ».

**Mention en tête de section :** « Ce sont des pistes à l'étude, pas des engagements. »

| Carte | Libellé proposé | Proposition source |
|---|---|---|
| Filtrer les posts | Retrouver en un geste les messages les plus cités d'un sujet, ou ceux de vos pseudos favoris | Contre-proposition à LOT-154 |
| Vérification automatique | Vérifier vos MP et vos drapeaux depuis l'app Raccourcis d'iOS, à l'heure que vous choisissez | LOT-141 |
| Notifications MP réglables | Choisir les MP qui vous notifient, et couper un MP de groupe trop bavard | #509 |
| MP à plusieurs | Écrire un MP à plusieurs personnes à la fois | LOT-182 |
| Création de sondage | Ajouter un sondage en créant un sujet | LOT-100 |
| Gestes identiques partout | Les mêmes gestes de glissement dans toutes les listes : marquer lu, retirer, super favori | LOT-177 |
| Thèmes de saison | Des thèmes pour chaque saison, qui s'activent tout seuls si vous voulez | X-SAISON |
| Images nettes | Toucher une miniature ouvre l'image en grand et nette, quel que soit le site qui l'héberge | #513 |
| Alertes Qualitay dans le sujet | Repérer d'un coup d'œil, en lisant un sujet, les messages signalés en Alerte Qualitay | Idée du PO, 7 novembre 2026 |
| Répondre en bas du sujet | Écrire une réponse courte directement en bas du sujet, comme dans une messagerie, sans ouvrir l'éditeur | Idée du PO ; moitié « réponse » de FEAT-006 |

Libellés volontairement non trompeurs :
- aucune carte ne promet une alerte quand on est cité, jugée difficilement faisable ;
- aucune ne nomme un hébergeur ou une technique.

**Question ouverte juste après les cartes :** « Ces idées vous en inspirent une autre ? »

**Question dédiée aux messages privés**, après les cartes. Elle touche la barre d'onglets, que le principe « préserver ce qui marche » protège, et demande donc le soutien de la communauté :
- « Comment préférez-vous retrouver vos messages privés ? »
- Réponses : « Un seul onglet, comme aujourd'hui » · « Deux listes dans l'onglet Messages, déjà possible en réglage » · « Deux onglets : MP et MP à plusieurs » · « Je n'utilise pas les MP à plusieurs ».

Ajouts du 7 novembre 2026 : voir `docs/ux/retours-equipe-github.md`.

Hors cartes, à faire sans attendre l'avis : navigateur de pages, écran « Quoi de neuf », reprise des fonctions de parité.

### 4.6 Champ libre

Une seule question ouverte en fin, 280 caractères.

### 4.7 Contrôle : aucune proposition classée Non

Vérifié le 6 novembre 2026, puis le 7 novembre après les ajouts : aucune des dix propositions classées Non n'apparaît dans cette sélection. La carte « Répondre en bas du sujet » relance seulement la barre de réponse de FEAT-006 ; le plateau de citations, classé Non, n'y figure pas. Le scrubber est explicitement exclu du thème 1, et l'aperçu présenté au thème 2 est l'aperçu local (LOT-152, Peut-être), pas l'aperçu serveur (LOT-184, Non).

Les deux cadrages plus anciens, `docs/ux/cadrage-questionnaire-ux.md` et `docs/ux/cadrage-points-ux.md`, citent encore la couleur d'accent unique et Spotlight. Ils sont marqués comme remplacés par ce document.

## 5. Décision technique interne : rendu natif des sujets

**Différée** (PO, 7 novembre 2026) : la WebView est conservée pour le moment ; cette section reste comme analyse pour la décision technique ultérieure. Elle ne conditionne plus le questionnaire.

**État actuel.** Le moteur fournit un HTML normalisé, avec des listes typées à côté : smileys, images, liens, signature. L'ADR 0006 avait étudié un arbre de contenu typé rendu nativement et l'avait écarté « pour l'instant », à cause du coût de réécriture du rendu CSS. Passer au natif demande un ADR qui remplace ce choix. Redface 2 rend déjà le contenu HFR nativement sur Android.

**Lien avec la lecture continue.** Elle reste possible avec la WebView, en ajoutant la page suivante par injection, mais c'est fragile : mémoire, repères de position, marquage lu page par page. Le rendu natif la rend propre. Il se justifie seul, même en gardant les pages.

**Gains attendus, en gardant les pages :**

| Domaine | Gain |
|---|---|
| Dynamique des pages | Page suivante préparée hors écran, changement instantané, swipe interactif, position retrouvée au message près, plus de page bloquée par une image lente |
| Liste noire et liste blanche | Message masqué remplacé par une ligne dépliable, ajout ou retrait d'un pseudo depuis le message avec effet immédiat, mise en avant cohérente avec le thème |
| Lisibilité et accessibilité | Taille de texte dynamique iOS dans les messages, VoiceOver message par message, thèmes identiques au reste de l'app |
| Contenu | Citations longues repliables, saut vers le message cité, spoilers et code natifs, séparateur stable, intégration directe de la visionneuse et des vidéos |
| Recherche | Recherche dans la page et « Filtrer les posts » avec surlignage natif |
| Grands écrans | Réagencement immédiat au pliage du Duo ou au redimensionnement iPad, sans recharger |
| Maintenance | Rendu testable par tests unitaires et captures, suppression du pont JavaScript |

**Risques :**
- sélection de texte pour « Citer extrait », le point le plus dur, qui demande TextKit ;
- fidélité sur la longue traîne du contenu HFR : tableaux, couleurs, smileys dans le texte, liens chiffrés ;
- performances sur les pages lourdes en images et smileys.

**Proposition.** Un prototype sur trois cas difficiles, tirés des captures existantes : citations imbriquées avec smileys, citation d'extrait, tableau ou bloc de code. Le résultat décide de l'ADR, et de ce que le scénario « pages améliorées » peut promettre.

## 6. Actions suivantes proposées

1. Signaler à l'orchestrateur le reclassement en parité de la section 3.1, et le choix de `master` comme référence legacy.
2. Vérifier sur l'app actuelle les trois points de la section 3.3.
3. Fermer LOT-153 et FEAT-006 en « non planifié », ainsi que les autres Non, avec la raison du PO.
4. Ouvrir une FEAT pour la contre-proposition « Filtrer les posts » amélioré.
5. Rendu natif : différé, décision technique ultérieure (section 5).
6. Préparer les visuels des deux thèmes et le texte des cartes du questionnaire.
