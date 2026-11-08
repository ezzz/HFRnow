# Cadrage des points UX à traiter

> **Remplacé** le 6 novembre 2026 par `docs/ux/tri-m5-decisions.md`, qui fait foi pour la sélection du questionnaire. Ce document reste comme historique : certaines pistes citées ici ont été classées Non par le PO, comme la couleur d'accent unique ou Spotlight.

Date : 4 novembre 2026. État de référence : `master`, version 4.0.4 (37). Inventaire fait sur le code actuel (`MainWindow.swift`, `MessagesView.swift`, `AppSettingsView.swift`, `Common.swift`, `Favorites.swift`, `MPListView.swift`, `PlusTab.swift`), le backlog (`backlog.md`) et l'inventaire des PR #3-#6 (`docs/review-pr-master-3-4-5-6.md`). Ce document précède et remplace la section « Décisions » de `docs/ux/cadrage-questionnaire-ux.md`, à réaligner une fois la liste validée.

## 1. Critères de tri

Un point passe au questionnaire seulement s'il remplit les quatre conditions :

1. **Impactant** : il touche la boucle principale (lire un sujet, parcourir ses favoris, répondre) ou la structure de navigation, et concerne une large part des utilisateurs.
2. **Subjectif ou à compromis** : il n'y a pas de bonne réponse technique ; deux publics peuvent vouloir l'inverse (densité, repères, scroll).
3. **Pas déjà tranché** : ni livré en 4.0.x, ni imposé par les guidelines Apple, ni un bug.
4. **Coûteux à revenir en arrière** : un changement de structure ou d'habitude, pas un réglage que l'on peut ajouter sans rien casser.

Tout ce qui échoue à une condition va en section 3 (à faire sans sondage) ou 4 (exclu).

## 2. Points qui méritent un avis utilisateur

| # | Point | État actuel sur `master` | Pourquoi un avis | Pistes à mettre en balance (neutres) | Public |
|---|---|---|---|---|---|
| A1 | **Boucle de lecture d'un sujet : pages ou flux continu** | Une page à la fois ; ‹ › en barre du bas, page suivante arrive en haut, précédente en bas ; swipe horizontal désactivable ; actualisation par bouton seulement sur la dernière page ; séparateur « nouveaux messages » ; retour à la position conservé. | C'est le cœur de l'app et une habitude forte du forum, où les pages servent de repère (« p.495 »). Un scroll infini change la lecture, l'actualisation, le repère de page et la citation. Les deux camps existent. | Pages telles quelles · chargement de la page suivante à la volée avec repère de page visible · pull-to-refresh en bas ou en haut · bouton « dernier message non lu » permanent | Tous, surtout gros lecteurs |
| A2 | **Densité et lisibilité des listes** | Mode compact = marges réduites uniquement (Favoris et Réglages), aucun effet sur le contenu des lignes ni sur la liste d'un forum ; texte réglable de 0 à +30 % ; lignes à 2 lignes de titre + pied auteur · date. Retours « moins dense qu'avant », « compact pas visible » (HFR-012/013/024). | « Dense » veut dire des choses différentes selon les gens : titres sur une ligne, pied masqué, texte plus petit, lignes plus serrées. Le signal « revenir à l'ancien design » (HFR-030) est largement un signal de densité à décomposer. | Compact réel (1 ligne, pied réduit) · deux presets « forum » / « mobile » · densité par écran (Favoris dense, Catégories aérée) · rien de plus, texte réglable suffit | Tous, surtout anciens v3 |
| A3 | **Repères de lecture dans les lignes de sujets** | Fond coloré par type de drapeau (jaune / bleu / rouge) dans la liste d'un forum, fond super-favori seulement dans Favoris ; badge = nombre de **pages** non lues ; titre gris si déjà vu ; « ⚑ cur / max », « ≣ » si sondage ; séparateur anciens/nouveaux dans le sujet. Demandes : indicateur de position, séparation plus nette (HFR-015/016/021). | Ces codes sont hérités du site et identifient l'app pour les anciens ; les retirer ou les remplacer par des pastilles change la lecture rapide des listes. Pages vs messages non lus est un vrai choix d'information. | Garder les fonds colorés · pastille / icône de drapeau sans fond · compteur en messages non lus plutôt qu'en pages · indicateur « vous en êtes à p. N / M » | Tous connectés |
| A4 | **Thème sombre, contraste et accent** | Thème auto ou manuel ; teinte d'accent libre (curseur) ; luminosité du thème sombre réglable en % ; pas de noir pur OLED. Retours : sombre trop gris, manque de contraste (HFR-014/023). | Le contraste est perçu différemment selon l'écran et l'usage nocturne ; un curseur ne règle pas le fond des cartes ni les séparateurs. Passer de la teinte libre à des couleurs fixes retire une liberté existante. | Préréglages Sombre / Noir pur en plus du curseur · teinte libre conservée vs palette fixe · Liquid Glass tel quel vs fonds plus opaques | Tous, surtout lecture nocturne |
| A5 | **iPad et grands écrans : disposition** | Split view 3 colonnes livré (HFR-006) : barre latérale (Forum / Outils / Plus), liste 300-480 pt, sujet ; 2 colonnes pour les pages directes ; bouton « Masquer la liste » ; Duo portrait = sujet plein écran. Multi-fenêtre activé. | Gros impact de la régression initiale (HFR-006) : les utilisateurs iPad sont sensibles et peu nombreux, donc leur avis vaut plus qu'une moyenne. Reste à savoir ce qu'ils veulent en priorité : largeur de liste, barre latérale escamotable, lecture plein écran. | 3 colonnes permanentes · liste masquable mémorisée · sujet plein écran au tap et liste en survol · barre d'onglets iPad plutôt que barre latérale | iPad, Duo |
| A6 | **Composition des onglets et place des pages** | 4 onglets fixes : Catégories, Favoris, Messages, Plus ; écran de démarrage réglable ; Recherche, Bookmarks, Alertes Qualitay, Réglages dans Plus ; aucune entrée de recherche dans les listes. | Changer les onglets touche tout le monde à chaque ouverture. iOS 26 propose un onglet Recherche dédié ; certains vivent dans les Alertes Qualitay ou les Bookmarks, d'autres jamais. | Onglets fixes actuels · onglet Recherche à la place ou en plus · onglets choisis par l'utilisateur (ordre et contenu) · Plus réduit aux réglages | Tous |
| A7 | **Actions sur un message** | Tap sur le message ou l'avatar ouvre une feuille de 13 actions (Citer, multi-citation, Éditer, Profil, MP, listes noire/blanche, Favoris, Lien, Alerter, AQ, Bookmark, Supprimer) ; sélection de texte → Citer extrait / gras ; appui long image. | Pour les gros posteurs c'est le geste le plus répété ; une feuille de 13 entrées est lente. Mais tap = feuille est l'habitude v3. Changer pour appui long ou actions inline casse une habitude. | Feuille actuelle · 3 actions fréquentes inline sous le message + menu pour le reste · appui long à la place du tap · actions personnalisables | Posteurs |
| A8 | **Favoris : organisation de l'écran principal** | Sections par catégorie repliables (option), compteur par section, « Drapeaux & Favoris » ou « Favoris uniquement », actualisation automatique optionnelle, swipe Lu / Supprimer, super favoris. | Favoris est l'écran de démarrage le plus probable et chaque utilisateur l'organise à sa manière ; tri par catégorie, par date ou « non lus d'abord » sont incompatibles entre eux. | Par catégorie (actuel) · par date du dernier message · non lus en tête puis le reste · super favoris épinglés en haut | Tous connectés |
| A9 | **Réglages : ce qui est utilisé, ce qui peut partir** | 25 réglages environ (écran de démarrage, favoris, compact, tab bar réduite, texte, haptique, rotation, navigateur, icône, thème ×4, style des messages, listes, swipe page, bouton +, signatures, filtrage, badge MP, stockage MP, caches). | Simplifier les réglages est impactant pour ceux qui utilisent une option rare, et invisible pour les autres ; seule une mesure d'usage permet de couper sans se tromper. | Question d'usage par réglage, pas de choix de design | Tous |
| A10 | **Nouvelles fonctions à prioriser** | Présent : notification locale et badge à l'arrivée d'un MP via tâche d'arrière-plan. Absent : widget, Live Activity, App Intents / Siri, Spotlight. Backlog : filtrage par drapeau dans Catégories, création de sujet plus visible, création de sondage, nouvelles icônes. | L'effort est limité, il faut choisir ; seuls les utilisateurs savent lequel changerait leur usage. | Budget à répartir : widget favoris non lus · raccourcis Siri / Spotlight sur les favoris · filtrage par drapeau · nouveau sujet et sondage · mode lecture texte seul · icônes | Tous |

Point transversal, à poser en ouverture et non comme un choix : **ce que les anciens de la v3 regrettent précisément** (densité, couleurs de drapeaux, position des boutons, taille de texte). Il alimente A2, A3 et A7 et neutralise la réponse globale « avant c'était mieux ».

## 3. À faire sans sondage

Évidences, bugs ou conformité aux guidelines : un avis n'apporterait rien.

| Point | État | Action |
|---|---|---|
| Permission de notifications demandée au lancement (`HFRswiftApp.swift` ~28) | Contraire aux HIG | Demander au moment où l'utilisateur active le badge ou le stockage MP |
| Libellés anglais restants : « Save to Photos », « Link », « Blacklist », « Whitelist » | Finition | Franciser |
| Réglage taille des smileys commenté, valeur par défaut « double » (`AppSettingsView.swift` ~499) | Réglage fantôme | Rétablir ou supprimer la clé |
| « Réduire la tab bar au scroll » affiché en mode barre latérale | Réglage sans effet dans ce contexte | Masquer quand la barre latérale est active |
| Messages privés : actions seulement par menu contextuel, pas de swipe, pas de bouton nouveau MP | Incohérent avec Favoris qui a des swipes | Ajouter swipe Lu / Supprimer et un bouton de composition |
| Catégories : pas de tirer-pour-actualiser | Incohérent avec les autres listes | Ajouter |
| Pagination des listes avec un faux total quand HFR n'en donne pas (HFR ne liste que « … 400 500 ») | Information fausse | Afficher « Page N » et désactiver « Dernière page » dans ce cas (à vérifier sur `master`) |
| Actions rapides d'icône déclarées dans l'ancien plist seulement | Fonction perdue | Déclarer dans `HFRswift/Info.plist` ou retirer le code |
| HFR-031 bandeau « Résultats suivants » du filtrage | Bug UX connu | Clarifier le libellé et l'état |
| HFR-040 aperçus vidéo dans un sujet | Régression planifiée 4.1 | Corriger |

## 4. Exclu du questionnaire

### 4.1 Déjà livré en 4.0.x, ne pas reposer la question

Flux de réponse et brouillons (HFR-047, `specifications.md`), écran de démarrage (HFR-019), split view iPad 3 colonnes (HFR-006), multi-fenêtre iPad (HFR-026), MP non lus et suppression (HFR-036), synchronisation « Lu » (HFR-037), retour au bon endroit après réponse (HFR-002/009), bouton page suivante mis en avant en bas de page (HFR-088), swipe de page désactivable (HFR-035), luminosité du thème sombre, sélection d'onglet iOS 27 (HFR-092), routage des Alertes Qualitay (HFR-005), visionneuse d'images (HFR-042/048), iPhone Duo (HFR-093).

Pour ces points on peut au plus **mesurer la satisfaction** en une question (« la réponse rapide vous convient-elle ? »), sans proposer d'alternative.

### 4.2 Repris des PR #3-#6 mais déjà traités sur `master` ou en doublon

P3-15 (routage AQ / Bookmarks), P4-02 (onglet qui revenait sur Favoris), P5-27 (swipe de page près du bord), P6-18 (fermeture de la visionneuse), P4-01 et P6-01 (barre latérale : `master` a son propre split view), P5-17 (MP façon Mail : `master` a depuis ses propres actions MP), P5-23 (sondages : `master` a depuis retravaillé le composeur et les sondages), P4-04/P4-05/P4-09 (Duo : couvert par HFR-093).

### 4.3 Idées des PR volontairement non retenues comme questions

Elles sont soit des finitions, soit des choix d'implémentation, soit trop liées à la proposition « Natif calme » pour être posées sans la copier :

- catégories regroupées en 4 familles par mots-clés (P5-07) : faible impact, et classement fragile ;
- réorganisation de l'onglet Plus en carte compte (P5-18) : finition, couverte par A6 ;
- états vides avec lien Safari (P5-15/P5-20) : contraire au principe « les liens HFR restent dans l'app » ;
- refonte du profil (P5-24), styles de sondage (P5-23), bouton retour custom (P6-07) : implémentation ;
- barre latérale custom 300 pt (P6-01) : contraire aux HIG, l'intention est couverte par A5 ;
- corps de texte 17 pt par défaut (P5-25) : couvert par A2 sous forme de densité, pas de valeur fixe ;
- couleur d'accent unique à 7 choix (P5-03) : couvert par A4 sans imposer la palette ;
- tutoiement (P6-10) : question de ton, à décider par le mainteneur.

Les idées des PR qui restent **en balance** sont intégrées dans les pistes de A1, A3, A4 et A5 au même rang que les autres, sans être nommées.

## 5. Points à vérifier avant de figer la liste

- Actualisation de la liste d'un forum : recharge-t-elle la page courante ou la page 1 sur `master` ? (P3-08 ; si page 1, c'est un bug pour la section 3.)
- Pagination honnête (« Page N » sans faux total) : présente ou non sur `master` ? (P3-02)
- Nombre réel d'utilisateurs iPad et Duo (App Store Connect) pour calibrer A5.
- Usage réel du bouton « Nouveau sujet » (+) dans la liste d'un forum : HFR-027 le dit « peu clair ou indisponible selon appareil ».

## 6. Proposition d'ordre d'importance

1. A1 lecture d'un sujet, A2 densité, A3 repères : le cœur et le signal « ancien design ».
2. A5 iPad, A6 onglets : structure, décisions difficiles à défaire.
3. A4 thème, A7 actions sur un message, A8 favoris : confort quotidien.
4. A9 réglages, A10 nouvelles fonctions : alimentent la feuille de route plus que le design.

Si le questionnaire doit tenir en 7 minutes, les groupes 1 et 2 suffisent pour une première vague ; 3 et 4 peuvent faire une seconde vague courte.
