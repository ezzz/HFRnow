# Backlog retours utilisateurs HFRnow

Synthese issue du topic HFR, pages 495 a 499, apres publication de la version 4.0.

Priorites:

- P1: bug bloquant ou tres visible, impact fort, a corriger en premier.
- P2: impact fort ou regression nette, mais moins bloquant ou correction plus large.
- P3: amelioration importante, inconfort regulier ou demande frequente.
- P4: mineur, confort, finition ou faible occurrence.
- P5: loggue mais non corrige pour l'instant.

Principe de mise a jour:

- Les issues corrigees, testees OK, rejetees ou sorties du backlog actif sont deplacees dans l'historique des issues livrees en fin de fichier.
- Les sections P1 a P5 ne gardent que les issues encore a faire, a auditer ou explicitement logguees pour plus tard.

## Prochaine livraison

### Build #25

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-035 | Hors analyse initiale | iPad portrait: scroll topic parfois ignore ou intercepte | Bug UX | Moyen a fort | Faible | Palliatif applique: ajout du reglage `Swipe changement de page` dans `Sujets`, actif par defaut. Le passage a Non desactive le swipe horizontal de changement de page pour verifier si ce geste est a l'origine des scrolls ignores, tout en conservant le swipe edge retour natif. | Palliatif, a tester |
| HFR-036 | Hors analyse initiale | Tab Messages: marquer des MP en non lus et supprimer des MP | Fonction / UX | Fort | Moyenne | Ajout d'une action contextuelle `Marquer non lu` visible uniquement sur les MP lus. Ajout de l'action contextuelle `Supprimer` avec confirmation, en appelant le flux forum `valid_eff_prive`, puis retrait local de la conversation. | Livré |
| HFR-041 | Beta p.19 | MessagesView: taille de police qui change parfois dans un topic | Bug UI | Moyen a fort | Moyenne | Correction appliquee: la taille de police des messages est injectee dans le HTML rendu avant chargement WebView, puis reverifiee apres chargement avec reapplique JS en cas d'ecart. | Corrige, a tester |
| HFR-047 | Hors analyse initiale | AnswerView/MessagesView: clarifier reponse rapide, reponse forum et brouillons | UX / Fonction | Fort | Moyenne | Refonte du flux de reponse: reglage `Bouton +` a trois choix (`Reponse rapide`, `Repondre comme le forum`, `Pas d'icone`), action `Repondre` forum explicite dans le menu `...`, brouillon actif contextualise par topic, brouillons archives limites a trois par topic, archivage avant remplacement, sheet de brouillons avec action `Mettre de cote et vider`, suppression par swipe et action globale `Vider`. Specification ajoutee dans `specifications.md`. | Livré, a tester |

## P1

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |

## P2

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-006 | p.495, p.496 | Perte du panneau lateral iPad liste topics/favoris + topic | Regression UX | Fort | Elevee | Gros impact pour les utilisateurs iPad en paysage. Correction probablement structurelle si la navigation SwiftUI a ete revue. A planifier apres les bugs de saisie/navigation. | A faire |
| HFR-008 | p.497, p.498 | Fin de page / fin de topic moins lisible | UX | Moyen | Faible a moyenne | Important pour la comprehension du statut de lecture. Probablement corrigeable par indicateur visuel explicite ou separateur plus net. | A faire |
| HFR-031 | Hors analyse initiale | Filtrer les posts: le bandeau `Resultats suivants` ne fonctionne pas | Bug UX | Moyen | Faible | Le cas peut arriver: le filtrage s'arrete volontairement apres un lot de resultats, notamment a partir de 40 posts trouves, sans forcement avoir scanne tout le topic. Le bouton sert alors a relancer le filtrage a partir de la page suivante, mais l'UX reste a clarifier car il peut donner l'impression d'un bouton redondant ou inactif. | A clarifier |
| HFR-040 | Hors analyse initiale | MessagesView: refaire fonctionner les previews de videos intra-topic | Regression UX | Moyen a fort | Moyenne | Les previews video dans la vue intra-topic ameliorent fortement la lecture des messages avec contenus multimedia. A auditer cote parsing/HTML embarque/WebView et compatibilite des providers video. | A faire |
| HFR-048 | Hors analyse initiale | View image: la croix bleue de fermeture ne ferme pas la fenetre | Bug UX | Moyen a fort | Faible a moyenne | Le bouton de fermeture s'affiche mais le tap ne ferme pas le viewer image. Impact visible car l'utilisateur peut se retrouver bloque dans une vue media ou devoir utiliser un autre geste de sortie. | A faire |

## P3

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-012 | p.498 | Interface jugee moins dense | UX | Moyen | Moyenne | Sujet sensible mais subjectif. A traiter via option compact plus efficace plutot qu'un redesign global. | A faire |
| HFR-013 | p.495, p.496 | Option compact pas assez visible / effet insuffisant | UX | Moyen | Faible a moyenne | Bon levier pour repondre aux critiques de densite sans penaliser tout le monde. Priorite raisonnable si les changements sont localises. | A faire |
| HFR-014 | p.495 | Mode sombre trop gris / manque de contraste | UX | Moyen | Faible | Correction probablement simple sur les couleurs. Attention a garder les contrastes accessibles et coherents avec Liquid Glass / iOS 26. | A faire |
| HFR-015 | p.495 | Separation anciens/nouveaux posts moins visible | UX | Moyen | Faible | Quick win probable: separateur plus net ou reprise d'un marqueur proche de l'ancien comportement. | A faire |
| HFR-016 | p.497, p.498 | Pastilles drapeaux/favoris moins identifiables | UX | Moyen | Faible a moyenne | Impact sur le scan des listes. Peut etre traite avec icones/couleurs plus distinctes sans revenir integralement a l'ancien design. | A faire |
| HFR-018 | p.496 | Pull-to-refresh des favoris trop difficile a declencher | UX | Moyen | Faible a moyenne | Geste frequent, probablement corrigeable par ajustement de layout/scroll view si le probleme est localise. | A faire |
| HFR-020 | p.497 | Insertion photo moins directe | UX | Faible a moyen | Moyenne | A optimiser apres les bugs editeur principaux. Peut etre lie aux contraintes modernes de Photo Picker. | A faire |
| HFR-038 | Hors analyse initiale | MessagesView: masquer l'icone sondage si vote possible mais aucun choix disponible | Bug UX | Moyen | Faible a moyenne | Cas distinct d'un sondage deja repondu: si le detail indique qu'on peut voter mais qu'aucun choix n'est disponible, l'icone d'action est trompeuse et doit etre masquee. | A faire |
| HFR-039 | Hors analyse initiale | MessagesView: toujours afficher l'icone sondage, prominent si reponse possible | UX | Moyen | Faible a moyenne | Rendre l'etat sondage plus coherent: icone visible des qu'un sondage existe, prominent uniquement quand l'utilisateur peut voter, non prominent sinon. A articuler avec HFR-038 pour le cas sans choix disponible. | A faire |
| HFR-042 | Beta p.19 | Images miniatures: tap simple ouvre une version illisible | UX / Bug media | Moyen | Moyenne | Sur certaines miniatures, le tap simple ouvre une version peu lisible alors que l'appui long permet d'ouvrir correctement l'image. Le geste naturel attendu est le tap simple vers l'image originale ou exploitable. | A faire |

## P4

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-021 | p.495 | Barre de defilement ou indicateur de position dans les topics | Amelioration | Faible a moyen | Faible a moyenne | Utile pour l'orientation dans les longues pages. Non bloquant, mais peut renforcer la lisibilite de fin de page. | A faire |
| HFR-022 | p.498 | Bouton `...` demande plus bas, pres du `+` | UX | Faible a moyen | Faible | Ajustement ergonomique iPhone. A evaluer avec les contraintes de hierarchy toolbar/navigation. | A faire |
| HFR-023 | p.495 | Espacement en haut des listes en theme sombre | Finition UI | Faible | Faible | Finition visuelle, probablement simple. A grouper avec les ajustements theme sombre. | A faire |
| HFR-024 | p.495 | Taille de caracteres plus petite | Amelioration | Faible a moyen | Faible a moyenne | Demande legitime pour les utilisateurs qui veulent plus de densite. Peut etre combine avec HFR-013. | A faire |
| HFR-025 | p.495 | Filtrage des topics par drapeaux dans Categories | Fonction | Faible a moyen | Moyenne | Amelioration utile, mais pas une regression bloquante. | A faire |
| HFR-027 | p.495 | Creation de topic / TU peu claire ou indisponible selon appareil | Fonction / UX | Faible a moyen | Moyenne | A clarifier: si la fonction existe, ameliorer la decouvrabilite; sinon a planifier hors correctifs 4.0. | A faire |
| HFR-028 | p.495 | Creation de sondage dans un topic | Fonction | Faible | Moyenne a elevee | Fonction avancee et rare. A garder en backlog, pas prioritaire. | A faire |
| HFR-029 | p.495 | Plus de choix d'icones d'app | Finition | Faible | Faible | Simple si les assets existent, mais faible impact d'usage. | A faire |
| HFR-043 | Beta p.19 | AnswerView: crash dans la recherche de smileys | Crash | Faible a moyen | A auditer | Un crash isole rapporte apres recherche de smiley puis scroll des resultats. Le feedback TestFlight ne contient pas de stack trace; conserver les smileys animes et surveiller les prochains crash logs avant correction intrusive. | A surveiller |

## P5

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-030 | Synthese p.495-p.499 | Revenir strictement a l'ancien design | Demande generale | Variable | Elevee | Demande exprimee indirectement via plusieurs irritants. Ne pas traiter comme une issue unique: preferer corriger les regressions precises listees ci-dessus. | Loggue |

## Ordre recommande

1. Traiter le prochain P1 actif quand il sera identifie.
2. Restaurer le confort iPad: HFR-006.
3. Corriger les quick wins visibles: HFR-015, HFR-014, HFR-031, HFR-038, HFR-039.
4. Repondre aux critiques de densite/lisibilite: HFR-013, HFR-012, HFR-016, HFR-008.
5. Traiter les ameliorations fonctionnelles non bloquantes: HFR-025, HFR-027 a HFR-029.

## Historique des issues livrees

### Livrees build #21

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-001 | p.496 | Clavier tiers non conserve, surtout SwiftKey | Bug | Fort | Moyenne | Tres irritant pour les gros contributeurs: la saisie est centrale dans l'app et le bug revient a chaque reponse. Cause probable: `keyboardType = .asciiCapable` forcait un clavier compatible et pouvait exclure SwiftKey. Contrainte retiree, filtre anti-emoji conserve cote delegate. | Corrige, a verifier sur appareil |
| HFR-003 | p.495, p.497, p.499 | Multiquote peu clair ou casse | Bug / UX | Fort | Moyenne | Le bouton `+` et `Citer` utilisent maintenant la meme memoire de brouillon. Une citation ajoutee depuis un post est concatenee au brouillon existant avec une ligne vide, puis reste disponible si la fenetre est fermee et rouverte via `+`. | Teste OK |
| HFR-004 | p.498 | Signalement forum qui renvoie une 404 | Bug | Moyen | Faible | Cause probable: l'action du formulaire `modo.php?...` et `referer_page` etaient parsees avec `&amp;` non decode, donnant des parametres invalides au POST. Les attributs du formulaire sont maintenant decodes et le champ `Submit` est garanti. | Teste OK |
| HFR-005 | p.495 | Liens des alertes qualite inoperants | Bug | Moyen | Faible a moyenne | Impact ponctuel mais c'est une regression visible. Cause confirmee: l'ouverture AQ reconstruisait le topic en forcant page 1. L'URL AQ est maintenant conservee avec sa page et son ancre de message. | Teste OK |
| HFR-011 | p.497 | Swipe retour bord gauche tres peu fiable | Bug UX | Fort | Moyenne | Cause mieux cernee: le probleme apparait sur le `MessagesView` pousse depuis un lien interne de topic. Le bouton retour custom avec badge et les fallbacks de swipe ont ete retires pour laisser le back natif. Un bouton leading type undo, a cote du back natif, affiche le nombre de vues empilees et permet de revenir au premier `MessagesView` empile. | Teste OK |
| HFR-026 | p.496 | Support multi-fenetre iPad / Split View | Fonction | Fort | Faible a moyenne | Demande prioritaire iPad. Cote SwiftUI, `WindowGroup` supporte les fenetres multiples si `UIApplicationSupportsMultipleScenes` est actif dans l'Info.plist. Flag active dans `HFRswift/Info.plist`; verifier sur iPad que l'etat global ne casse pas plusieurs scenes. | Corrige, a verifier sur iPad |
| HFR-032 | Hors analyse initiale | Bottom bar MessagesView: boutons page/refresh parfois sans effet | Bug UX | Fort | Moyenne | Correction minimale appliquee: zone tactile externe stable 44x44 ajoutee aux boutons page precedente, page suivante, refresh et `+`, en conservant leur rendu principal et leur logique. | Corrige, a verifier sur appareil |
| HFR-033 | Hors analyse initiale | AnswerView: recherche smiley ne remonte pas en haut | Bug UX | Moyen a fort | Faible | Correction appliquee: la liste smileys utilise une ancre haute via `ScrollViewReader` et revient en haut quand une nouvelle recherche termine, que les resultats soient vides ou non. | Corrige, a verifier sur appareil |
| HFR-007 | p.495, p.496 | Menu lateral iPad qui revient ouvert apres repli / retour app | Bug UX | Moyen a fort | Moyenne | Correction appliquee: la visibilite du `NavigationSplitView` iPad est maintenant pilotee explicitement et persistee, pour conserver l'etat replie/ouvert choisi par l'utilisateur au retour dans l'app. | Corrige, a verifier sur iPad |
| HFR-010 | p.497, p.499 | Insertion de liens regressees dans l'editeur | Regression UX | Moyen | Moyenne | Correction appliquee: l'action `Lien` sur une selection detecte une URL HTTP(S) dans le presse-papier, demande confirmation, puis insere directement `[url=URL]texte[/url]`. Sans URL detectee, le comportement standard `[url]texte[/url]` est conserve. | Corrige, a verifier sur appareil |
| HFR-017 | p.498 | Fenetre de reponse non conservee quand elle est glissee vers le bas | UX / Perte de donnees | Moyen | Moyenne a elevee | Corrige via HFR-003: le bouton `+` et `Citer` partagent la meme memoire de brouillon, donc le contenu saisi est conserve quand l'editeur est ferme puis rouvert. | Corrige, a verifier sur appareil |
| HFR-019 | p.498 | Demarrage pas au bon endroit / choix de l'ecran initial | UX | Moyen | Faible a moyenne | Correction appliquee: ajout du reglage `Ecran de demarrage` en premier dans les reglages, avec choix entre Categories, Favoris et Messages, dans l'ordre des tabs. Le choix s'applique au prochain lancement/restart de l'app. | Corrige, a verifier sur appareil |

### Livrés build #24

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-034 | Hors analyse initiale | AnswerView: zone d'edition ne suit pas le curseur sur message long | Bug UX | Fort | Moyenne | Correctif complementaire: les insertions programmatiques smiley/image/GIF conservent maintenant le curseur a la fin du contenu insere, et les remplacements rapides de suggestions clavier declenchent une stabilisation TextKit. | Corrige, test utilisateur OK |
| HFR-037 | Hors analyse initiale | Tab Favoris: marquer un topic comme lu doit etre synchronise forum | Bug / Sync | Fort | Moyenne | Correction appliquee: l'action `Lu` retire immediatement le topic de la liste locale et lance en arriere-plan une requete vers la derniere page du topic, comme le legacy, pour synchroniser l'etat lu cote forum. | Corrige, a verifier sur appareil |

### Livrés build #23

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-034 | Hors analyse initiale | AnswerView: zone d'edition ne suit pas le curseur sur message long | Bug UX | Fort | Moyenne | Correction appliquee: l'editeur de reponse evite les rerenders SwiftUI sur simple repositionnement du curseur, conserve la selection dans un store non observe et ne force le scroll du caret qu'apres un vrai changement de texte, focus ou selection programmatique. | Corrige, test utilisateur OK |

### Livrés build #22

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-002 | p.496, p.498 | Retour au mauvais endroit apres reponse/citation | Bug | Fort | Moyenne | Correction amelioree: refresh/post/edition utilisent maintenant des ancres de message plutot qu'une restauration fragile par offset de scroll. | Corrige et teste OK |
| HFR-009 | p.498 | Refresh en bas de page qui saute au dernier message au lieu du dernier lu | Bug | Moyen | Moyenne | Correction amelioree avec la meme logique que HFR-002: en bas de derniere page, l'ancien dernier post sert d'ancre et le bas de page est conserve s'il n'y a pas de nouveau message. | Corrige et teste OK |
