# Questionnaire utilisateurs : rédaction finale

Date : 8 novembre 2026. Rédaction finale (UX-05, #629) du questionnaire, à partir de `docs/ux/tri-m5-decisions.md` §4. Le parcours et les identifiants viennent de `docs/ux/questionnaire/cadrage-construction.md` §2, la forme des blocs de sa §3.2. Les décisions du PO du 8 novembre 2026 s'appliquent : `L1` porte une troisième réponse « Garder les pages comme aujourd'hui » (D1), le pseudo `I1` est demandé à la fin (D2).

Statut : texte rédigé par Sonnet, relecture Opus, validation du PO à venir. Le formulaire (#634) transcrit ce fichier, et un test vérifie que les identifiants, les codes et les libellés sont identiques.

## Règles de lecture

- Les identifiants et les codes de réponse sont stables (cadrage §3.1). Un code est en minuscules ASCII, avec `_` comme séparateur. Changer un identifiant ou un code demande de modifier le cadrage.
- Le libellé est ce que le répondant lit. Entre `·`, chaque réponse est écrite `` `code` Libellé ``.
- Toutes les questions sont facultatives. Le formulaire n'en rend aucune obligatoire.
- Le texte entre guillemets à la ligne « Aide » est affiché sous la question. « (aucune) » ou « (facultative) » veut dire que rien n'est affiché.
- Une réponse « comme aujourd'hui » existe partout où une évolution est proposée : `O1`, `L1`, `D1`, `D2`, `M1`. Les cartes `C01` à `C10` s'en passent : « Inutile pour moi » y remplit ce rôle, et rien n'y change sans réponse.
- Aucune proposition classée Non par le PO (tri §3.5 et §4.7) n'apparaît. Le thème 1 ne montre que des améliorations possibles avec la WebView (tri §4.3).

## Questions

### E0
- Section du tri : §4 (introduction)
- Question : Aidez-nous à choisir la suite de l'app
- Réponses : (aucune, écran de lecture)
- Aide : « Vous utilisez l'app HFR : dites-nous ce que vous aimeriez y voir évoluer. Une vingtaine de réponses à cocher, environ 5 minutes, toutes facultatives, sans mauvaise réponse. Vos réponses sont anonymes sauf si vous laissez votre pseudo à la fin. Ce sont des pistes à l'étude, pas des engagements. Lire la mention sur les données. »
- Condition : (aucune)

### P1
- Section du tri : §4.1
- Question : Sur quel appareil utilisez-vous surtout l'app ?
- Réponses : `iphone` iPhone · `ipad` iPad · `duo` iPhone Duo · `plusieurs` Plusieurs
- Aide : (facultative)
- Condition : (aucune)

### P2
- Section du tri : §4.1
- Question : Comment utilisez-vous le forum ?
- Réponses : `lit_surtout` Je lis surtout · `lit_repond` Je lis et je réponds parfois · `poste_souvent` Je poste souvent
- Aide : (facultative)
- Condition : (aucune)

### P3
- Section du tri : §4.1
- Question : Depuis quand utilisez-vous l'app ?
- Réponses : `avant_4_0` Avant la version 4.0 · `depuis_4_0` Depuis la version 4.0
- Aide : (facultative)
- Condition : (aucune)

### O1
- Section du tri : §4.2
- Question : Pour la suite, vous préférez que l'app…
- Réponses : `rester` Reste comme elle est · `petites_touches` Évolue par petites touches · `oser` Ose des nouveautés
- Aide : (facultative)
- Condition : (aucune)

### L1
- Section du tri : §4.3 (décision D1 du 8 novembre 2026)
- Question : Pour lire un long sujet, quelle version de l'app préférez-vous ?
- Réponses : `pages_ameliorees` Des pages améliorées · `lecture_continue` Des pages améliorées, avec en option la lecture continue · `comme_aujourdhui` Garder les pages comme aujourd'hui
- Aide : « Pages améliorées : les pages restent. Passer d'une page à l'autre sans écran blanc. Aller directement à une page depuis le titre du sujet. Un séparateur des nouveaux messages plus visible, qui ne bouge pas pendant le chargement des images. Les messages masqués par votre liste noire remplacés par une ligne qu'on déplie d'un geste. Un texte à la taille choisie dans les réglages d'iOS. Lecture continue en option : tout cela, plus un réglage, désactivé par défaut, qui affiche la page suivante à la suite de la page en cours, avec un repère discret du numéro de page. Garder les pages comme aujourd'hui : rien ne change. »
- Condition : (aucune)

### L2
- Section du tri : §4.3
- Question : Qu'est-ce qui vous manquerait avec ce choix ?
- Réponses : (texte libre, 280 caractères au plus)
- Aide : « Une phrase suffit. Laissez vide si rien ne vous manque. »
- Condition : `L1` répondue

### D1
- Section du tri : §4.4, partie A
- Question : Sur iPad et sur iPhone Duo déplié, que voulez-vous voir en permanence dans la barre latérale ?
- Réponses : cartes à trier, une par section. Sections : `favoris` Favoris · `categories` Catégories · `mp` Messages privés · `drapeaux` Drapeaux · `a_suivre` À suivre (les nouveautés de tous vos sujets suivis) · `alertes_qualitay` Alertes Qualitay · `bookmarks` Bookmarks · `recherche` Recherche · `reglages` Réglages. Pour chaque carte : `garder` Je la veux dans la barre · `deplier` Je la veux, et dépliable · `ecarter` Pas dans la barre. Ordre de la barre : celui choisi par le répondant. Réponse seule : `comme_aujourdhui` Laisser la barre comme aujourd'hui
- Aide : « Gardez les sections que vous voulez voir en permanence, mettez-les dans l'ordre qui vous convient, et indiquez celles que vous aimeriez pouvoir déplier, par exemple pour voir vos favoris sans quitter la barre. Aujourd'hui : Favoris, Catégories et Messages privés dans le groupe Forum ; Drapeaux dans Favoris ; Alertes Qualitay et Bookmarks dans le groupe Outils ; Recherche et Réglages dans le groupe Plus ; À suivre n'existe pas. »
- Condition : `P1` vaut `ipad`, `duo` ou `plusieurs`

### D2
- Section du tri : §4.4, partie B
- Question : Sur iPad et sur iPhone Duo déplié, quelle disposition préférez-vous ?
- Réponses : `comme_aujourdhui` Comme aujourd'hui : la barre latérale, la liste, puis le sujet · `tableau_de_bord` Avec une colonne « À suivre » : reprise de la lecture, messages privés, favoris et drapeaux avec leurs nouveautés · `cote_a_cote` Lecture et écriture côte à côte : le sujet reste visible pendant que vous écrivez, avec un aperçu de votre message avant l'envoi
- Aide : « Sur le Duo, aujourd'hui, l'écran extérieur affiche l'interface de l'iPhone. Des vidéos courtes montrent chaque disposition si vous n'avez pas l'appareil. »
- Condition : `P1` vaut `ipad`, `duo` ou `plusieurs`

### C01
- Section du tri : §4.5 (carte « Filtrer les posts », contre-proposition à LOT-154)
- Question : Filtrer les posts : retrouver en un geste les messages les plus cités d'un sujet, ou ceux de vos pseudos favoris
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : « Ce sont des pistes à l'étude, pas des engagements. » (en tête de la section des cartes, affichée une fois)
- Condition : (aucune)

### C02
- Section du tri : §4.5 (carte « Vérification automatique », LOT-141)
- Question : Vérification automatique : vérifier vos messages privés et vos drapeaux depuis l'app Raccourcis d'iOS, à l'heure que vous choisissez
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C03
- Section du tri : §4.5 (carte « Notifications MP réglables », #509)
- Question : Notifications de MP réglables : choisir les messages privés qui vous notifient, et couper un MP de groupe trop bavard
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C04
- Section du tri : §4.5 (carte « MP à plusieurs », LOT-182)
- Question : MP à plusieurs : écrire un message privé à plusieurs personnes à la fois
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C05
- Section du tri : §4.5 (carte « Création de sondage », LOT-100)
- Question : Création de sondage : ajouter un sondage en créant un sujet
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C06
- Section du tri : §4.5 (carte « Gestes identiques partout », LOT-177)
- Question : Gestes identiques partout : les mêmes gestes de glissement dans toutes les listes, pour marquer comme lu, retirer ou passer en super favori
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C07
- Section du tri : §4.5 (carte « Thèmes de saison », X-SAISON)
- Question : Thèmes de saison : des thèmes pour chaque saison, qui s'activent tout seuls si vous le voulez
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C08
- Section du tri : §4.5 (carte « Images nettes », #513)
- Question : Images nettes : toucher une miniature ouvre l'image en grand et nette, quel que soit le site qui l'héberge
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C09
- Section du tri : §4.5 (carte « Alertes Qualitay dans le sujet », idée du PO du 7 novembre 2026)
- Question : Alertes Qualitay dans le sujet : repérer d'un coup d'œil, en lisant un sujet, les messages signalés en Alerte Qualitay
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C10
- Section du tri : §4.5 (carte « Répondre en bas du sujet », idée du PO, moitié « réponse » de FEAT-006)
- Question : Répondre en bas du sujet : écrire une réponse courte directement en bas du sujet, comme dans une messagerie, sans ouvrir l'éditeur
- Réponses : `adore` J'adore · `pourquoi_pas` Pourquoi pas · `inutile` Inutile pour moi
- Aide : (aucune)
- Condition : (aucune)

### C11
- Section du tri : §4.5 (question ouverte après les cartes)
- Question : Ces idées vous en inspirent une autre ?
- Réponses : (texte libre, 280 caractères au plus)
- Aide : « Une phrase suffit. Laissez vide si rien ne vous vient. »
- Condition : (aucune)

### M1
- Section du tri : §4.5 (question dédiée aux messages privés)
- Question : Comment préférez-vous retrouver vos messages privés ?
- Réponses : `un_onglet` Un seul onglet, comme aujourd'hui · `deux_listes` Deux listes dans l'onglet Messages, déjà possible en réglage · `deux_onglets` Deux onglets : MP et MP à plusieurs · `pas_mp_plusieurs` Je n'utilise pas les MP à plusieurs
- Aide : (facultative)
- Condition : (aucune)

### F1
- Section du tri : §4.6
- Question : Un dernier mot sur l'app, ou sur ce questionnaire ?
- Réponses : (texte libre, 280 caractères au plus)
- Aide : « Une phrase suffit. Laissez vide si vous n'avez rien à ajouter. »
- Condition : (aucune)

### I1
- Section du tri : §4 (décisions du PO D2 du 8 novembre 2026 et décision 3 du plan de préparation)
- Question : Votre pseudo HFR (facultatif)
- Réponses : (texte libre, un pseudo)
- Aide : « Facultatif. Sans pseudo, vos réponses restent anonymes. Si vous en laissez un, vous pouvez demander à tout moment qu'il soit supprimé : écrivez à Bruno Arene, ezzz75@gmail.com. Le détail est dans la mention sur les données. »
- Condition : (aucune)

### E1
- Section du tri : §4 (message de fin) ; cadrage de la construction §4 (écran de fin)
- Question : Merci !
- Réponses : (aucune, écran de lecture)
- Aide : « Merci d'avoir pris ce temps. Voici vos réponses à côté de celles des autres utilisateurs. Ce sont des pistes à l'étude, pas des engagements : vos réponses éclairent les choix, elles ne les décident pas. » Sous le message, chaque réponse du répondant est mise en regard de la répartition de la communauté, en pourcentages arrondis, quand le seuil d'affichage est atteint (décision D3). Avant ce seuil : « Les résultats s'afficheront quand assez de personnes auront répondu. »
- Condition : (aucune)

## Textes de diffusion

Ces textes ne sont pas des questions : le formulaire ne les transcrit pas. Ils sont publiés par le PO (UX-13, action publique, à confirmer au moment de la diffusion). Le lien et les dates de fermeture sont à compléter à la mise en ligne.

#### Annonce pour le topic HFR

> **Votre avis sur la suite de l'app HFR (5 minutes)**
>
> Je prépare la suite de l'app et je voudrais savoir ce qui compte pour vous : comment vous lisez les longs sujets, ce que vous aimeriez sur iPad et iPhone Duo, et quelques idées en vrac.
>
> Quelques minutes, toutes les questions sont facultatives. Vos réponses sont anonymes, sauf si vous laissez votre pseudo à la fin. Ce sont des pistes à l'étude, pas des engagements.
>
> Questionnaire : [lien à compléter], ouvert jusqu'au [date à compléter].
>
> Merci d'avance, et n'hésitez pas à le faire passer aux autres utilisateurs de l'app.

#### Note TestFlight

> **Donnez votre avis sur la suite de l'app.** Un questionnaire de 5 minutes, toutes les questions sont facultatives : [lien à compléter]. Ouvert jusqu'au [date à compléter].

## Contrôle

- Toutes les questions de la sélection du tri §4 figurent : profil §4.1 (`P1` à `P3`), ouverture §4.2 (`O1`), thème 1 §4.3 (`L1`, `L2`), thème 2 §4.4 (`D1`, `D2`), dix cartes §4.5 (`C01` à `C10`), question ouverte (`C11`), messages privés (`M1`), champ libre §4.6 (`F1`), plus `E0`, `I1` et `E1`.
- Aucune des dix propositions classées Non (tri §3.5) n'est présente : ni plateau de citations, ni scrubber, ni aperçu serveur (l'aperçu de `D2` est l'aperçu local de LOT-152), ni refus des emoji, suppression du premier post, avis AQ, accent unique, Spotlight, thème selon l'heure, actions rapides d'icône.
- Aucune carte ne promet une alerte quand on est cité (tri §4.5), et aucune ne nomme un hébergeur ou une technique.
- `L1` ne présente que des améliorations possibles avec la WebView : ni swipe qui suit le doigt, ni position à la ligne près.
- Cohérence avec la mention sur les données (#630) à vérifier à la fusion : pseudo facultatif, suppression sur demande à Bruno Arene, ezzz75@gmail.com.
