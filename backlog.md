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

## Backlog actif

| Priorite | ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P2 | HFR-031 | Hors analyse initiale | Filtrer les posts: le bandeau `Resultats suivants` ne fonctionne pas | Bug UX | Moyen | Faible | Le cas peut arriver: le filtrage s'arrete volontairement apres un lot de resultats, notamment a partir de 40 posts trouves, sans forcement avoir scanne tout le topic. Le bouton sert alors a relancer le filtrage a partir de la page suivante, mais l'UX reste a clarifier car il peut donner l'impression d'un bouton redondant ou inactif. | A clarifier |
| P3 | HFR-038 | Hors analyse initiale | MessagesView: masquer l'icone sondage si vote possible mais aucun choix disponible | Bug UX | Moyen | Faible a moyenne | Correction appliquee: le bouton sondage est maintenant pilote par `pollData` exploitable, pas seulement par `hasPoll`; un sondage annonce comme votable mais sans choix parseable ne produit donc plus de bouton inactif. | Corrige, a tester |
| P3 | HFR-039 | Hors analyse initiale | MessagesView: toujours afficher l'icone sondage, prominent si reponse possible | UX | Moyen | Faible a moyenne | Correction appliquee: le bouton sondage est permanent des qu'un sondage exploitable existe, en style prominent quand le vote est possible et en style standard pour les resultats. Apres vote, la sheet reste ouverte, recharge les donnees du sondage et bascule directement sur les resultats. | Corrige, a tester |
| P3 | HFR-042 | Beta p.19 | Images miniatures: tap simple ouvre une version illisible | UX / Bug media | Moyen | Moyenne | Sur certaines miniatures, le tap simple ouvre une version peu lisible alors que l'appui long permet d'ouvrir correctement l'image. Le geste naturel attendu est le tap simple vers l'image originale ou exploitable. | A faire |
| P4 | HFR-025 | p.495 | Filtrage des topics par drapeaux dans Categories | Fonction | Faible a moyen | Moyenne | Amelioration utile, mais pas une regression bloquante. | A faire |
| P4 | HFR-027 | p.495 | Creation de topic / TU peu claire ou indisponible selon appareil | Fonction / UX | Faible a moyen | Moyenne | A clarifier: si la fonction existe, ameliorer la decouvrabilite; sinon a planifier hors correctifs 4.0. | A faire |
| P4 | HFR-028 | p.495 | Creation de sondage dans un topic | Fonction | Faible | Moyenne a elevee | Fonction avancee et rare. A garder en backlog, pas prioritaire. | A faire |
| P4 | HFR-029 | p.495 | Plus de choix d'icones d'app | Finition | Faible | Faible | Simple si les assets existent, mais faible impact d'usage. | A faire |
| P4 | HFR-043 | Beta p.19 | AnswerView: crash dans la recherche de smileys | Crash | Faible a moyen | A auditer | Un crash isole rapporte apres recherche de smiley puis scroll des resultats. Le feedback TestFlight ne contient pas de stack trace; conserver les smileys animes et surveiller les prochains crash logs avant correction intrusive. | A surveiller |

## Backlog version 4.1

| Priorite | ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P2 | HFR-006 | p.495, p.496 | Perte du panneau lateral iPad liste topics/favoris + topic | Regression UX | Fort | Elevee | Gros impact pour les utilisateurs iPad en paysage. Correction probablement structurelle si la navigation SwiftUI a ete revue. A planifier apres la prochaine release. | Planifie 4.1 |
| P2 | HFR-040 | Hors analyse initiale | MessagesView: refaire fonctionner les previews de videos intra-topic | Regression UX | Moyen a fort | Moyenne | Les previews video dans la vue intra-topic ameliorent fortement la lecture des messages avec contenus multimedia. A auditer cote parsing/HTML embarque/WebView et compatibilite des providers video. | Planifie 4.1 |
| P5 | HFR-089 | Hors analyse initiale | iOS 27 beta: audit compatibilite et regressions UI | Compatibilite | A determiner | A auditer | Ticket de suivi a ouvrir au demarrage des betas iOS 27: verifier navigation, WebView, toolbars, Liquid Glass, saisie, partage media et comportements iPad. | Planifie 4.1 |

## Ameliorations UX

Ces points regroupent les feedbacks de confort et de finition. Ils ne sont pas traites comme des bugs unitaires bloquants: l'objectif est de les reprendre en fil rouge, par zones d'interface.

| Priorite | References | Zone | Theme | Avis | Statut |
| --- | --- | --- | --- | --- | --- |
| P3 | HFR-012, HFR-013, HFR-024 | Densite | Interface jugee moins dense, option compact pas assez visible, taille de caracteres plus petite | A traiter comme un chantier coherent: rendre le mode compact plus lisible, plus visible et vraiment utile sans imposer un redesign global. | A cadrer |
| P3 | HFR-014, HFR-023 | Theme sombre | Mode sombre trop gris, manque de contraste, espacement haut des listes | Grouper les ajustements de contraste, fonds et espacements pour eviter des corrections visuelles contradictoires. | A cadrer |
| P3 | HFR-015, HFR-016, HFR-021 | Lisibilite de lecture | Separation anciens/nouveaux posts, pastilles drapeaux/favoris, indicateur de position dans les topics | Ameliorer les reperes de lecture et le scan des listes; eviter de traiter chaque micro-symptome isolement. | A cadrer |
| P3 | HFR-018, HFR-020, HFR-022 | Ergonomie gestes/actions | Pull-to-refresh favoris, insertion photo, position du bouton `...` | Reprendre les gestes frequents et les actions de composition apres stabilisation des bugs principaux. | A cadrer |
| P5 | HFR-030 | Direction produit | Revenir strictement a l'ancien design | Conserver comme signal de fond, sans en faire une issue implementable telle quelle. Les irritants precis doivent etre traites par les chantiers ci-dessus. | Loggue |

## Ordre recommande

1. Traiter le prochain P1 actif quand il sera identifie.
2. Corriger les quick wins visibles du backlog actif: HFR-031, HFR-038, HFR-039.
3. Corriger les medias et cas isoles: HFR-042, HFR-043.
4. Cadrer les ameliorations UX par zone: densite, theme sombre, reperes de lecture, gestes/actions.
5. Preparer la version 4.1: HFR-006, HFR-040, HFR-089.
6. Traiter les ameliorations fonctionnelles non bloquantes: HFR-025, HFR-027 a HFR-029.

## Historique des issues livrees

### Livrees build #25

| ID | Pages | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HFR-008 | p.497, p.498 | Fin de page / fin de topic moins lisible | UX | Moyen | Faible a moyenne | Ajout d'un repere plus explicite en bas de page: le bouton page suivante repasse en style prominent sur les pages intermediaires, et le refresh reste reserve au bas de la derniere page. | Livré build #25 |
| HFR-035 | Hors analyse initiale | iPad portrait: scroll topic parfois ignore ou intercepte | Bug UX | Moyen a fort | Faible | Palliatif applique: ajout du reglage `Swipe changement de page` dans `Sujets`, actif par defaut. Le passage a Non desactive le swipe horizontal de changement de page pour verifier si ce geste est a l'origine des scrolls ignores, tout en conservant le swipe edge retour natif. | Palliatif, a tester |
| HFR-036 | Hors analyse initiale | Tab Messages: marquer des MP en non lus et supprimer des MP | Fonction / UX | Fort | Moyenne | Ajout d'une action contextuelle `Marquer non lu` visible uniquement sur les MP lus. Ajout de l'action contextuelle `Supprimer` avec confirmation, en appelant le flux forum `valid_eff_prive`, puis retrait local de la conversation. | Livré |
| HFR-041 | Beta p.19 | MessagesView: taille de police qui change parfois dans un topic | Bug UI | Moyen a fort | Moyenne | Correction appliquee: la taille de police des messages est injectee dans le HTML rendu avant chargement WebView, puis reverifiee apres chargement avec reapplique JS en cas d'ecart. | Corrige, a tester |
| HFR-047 | Hors analyse initiale | AnswerView/MessagesView: clarifier reponse rapide, reponse forum et brouillons | UX / Fonction | Fort | Moyenne | Refonte du flux de reponse: reglage `Bouton +` a trois choix (`Reponse rapide`, `Repondre comme le forum`, `Pas d'icone`), action `Repondre` forum explicite dans le menu `...`, brouillon actif contextualise par topic, brouillons archives limites a trois par topic, archivage avant remplacement, sheet de brouillons avec action `Mettre de cote et vider`, suppression par swipe et action globale `Vider`. Specification ajoutee dans `specifications.md`. | Livré, a tester |
| HFR-048 | Hors analyse initiale | View image: la croix bleue de fermeture ne ferme pas la fenetre | Bug UX | Moyen a fort | Faible | Correctif minimal applique: le bouton de fermeture du viewer image garde son action `dismiss`, mais dispose maintenant d'une zone tactile explicite 44x44, d'une forme de hit test circulaire et reste au-dessus du viewer. | Corrige, a tester |
| HFR-088 | Hors analyse initiale | MessagesView: remettre en avant le bouton page suivante en bas de page intermediaire | UX | Moyen | Faible | Retablissement de l'ancien repere: quand l'utilisateur arrive en bas d'une page qui n'est pas la derniere, le bouton page suivante passe en style prominent avec une animation legere. Le bouton refresh reste reserve au bas de la derniere page. | Corrige, a tester |

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
