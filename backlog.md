# Backlog retours utilisateurs HFRnow

Synthese issue du topic HFR, pages 495 a 499, apres publication de la version 4.0.

Priorites:

- P1: bug bloquant ou tres visible, impact fort, a corriger en premier.
- P2: impact fort ou regression nette, mais moins bloquant ou correction plus large.
- P3: amelioration importante, inconfort regulier ou demande frequente.
- P4: mineur, confort, finition ou faible occurrence.
- P5: loggue mais non corrige pour l'instant.

## P1

| ID | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- |
| HFR-001 | Clavier tiers non conserve, surtout SwiftKey | Bug | Fort | Moyenne | Tres irritant pour les gros contributeurs: la saisie est centrale dans l'app et le bug revient a chaque reponse. Cause probable: `keyboardType = .asciiCapable` forcait un clavier compatible et pouvait exclure SwiftKey. Contrainte retiree, filtre anti-emoji conserve cote delegate. | Corrige, a verifier sur appareil |
| HFR-002 | Retour au mauvais endroit apres reponse/citation | Bug | Fort | Moyenne | Regression majeure du flux de lecture: apres avoir poste, l'utilisateur perd son contexte. Prioritaire car touche une action frequente. | A faire |
| HFR-003 | Multiquote peu clair ou casse | Bug / UX | Fort | Moyenne | Fonction avancee mais tres utilisee sur HFR. Impact fort pour les discussions longues. Verifier d'abord s'il s'agit d'un vrai bug de generation ou d'un probleme de decouvrabilite. | A faire |
| HFR-004 | Signalement forum qui renvoie une 404 | Bug | Moyen | Faible | Correction probablement rapide si l'URL ou les parametres ont derive. Bon candidat quick win. | A faire |
| HFR-005 | Liens des alertes qualite inoperants | Bug | Moyen | Faible a moyenne | Impact ponctuel mais c'est une regression visible. A verifier avec un exemple d'alerte et corriger le routage interne ou l'ouverture web. | A faire |

## P2

| ID | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- |
| HFR-006 | Perte du panneau lateral iPad liste topics/favoris + topic | Regression UX | Fort | Elevee | Gros impact pour les utilisateurs iPad en paysage. Correction probablement structurelle si la navigation SwiftUI a ete revue. A planifier apres les bugs de saisie/navigation. | A faire |
| HFR-007 | Menu lateral iPad qui revient ouvert apres repli / retour app | Bug UX | Moyen a fort | Moyenne | Tres visible sur iPad et donne une impression d'instabilite. Moins lourd que restaurer l'ancien layout, donc a traiter separement si possible. | A faire |
| HFR-008 | Fin de page / fin de topic moins lisible | UX | Moyen | Faible a moyenne | Important pour la comprehension du statut de lecture. Probablement corrigeable par indicateur visuel explicite ou separateur plus net. | A faire |
| HFR-009 | Refresh en bas de page qui saute au dernier message au lieu du dernier lu | Bug | Moyen | Moyenne | Peut faire perdre le contexte de lecture. A rapprocher de HFR-002 si le meme modele de position de lecture est implique. | A faire |
| HFR-010 | Insertion de liens regressees dans l'editeur | Regression UX | Moyen | Moyenne | Moins bloquant que la saisie elle-meme, mais ralentit les posts construits. A corriger si l'ancien comportement peut etre restaure simplement via selection + presse-papier. | A faire |

## P3

| ID | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- |
| HFR-011 | Swipe retour moins fiable | Bug UX | Moyen | Moyenne | Impact notable car le geste est muscle memory. Demande reproduction precise, notamment apres ouverture d'un lien avec compteur sur le bouton retour. | A faire |
| HFR-012 | Interface jugee moins dense | UX | Moyen | Moyenne | Sujet sensible mais subjectif. A traiter via option compact plus efficace plutot qu'un redesign global. | A faire |
| HFR-013 | Option compact pas assez visible / effet insuffisant | UX | Moyen | Faible a moyenne | Bon levier pour repondre aux critiques de densite sans penaliser tout le monde. Priorite raisonnable si les changements sont localises. | A faire |
| HFR-014 | Mode sombre trop gris / manque de contraste | UX | Moyen | Faible | Correction probablement simple sur les couleurs. Attention a garder les contrastes accessibles et coherents avec Liquid Glass / iOS 26. | A faire |
| HFR-015 | Separation anciens/nouveaux posts moins visible | UX | Moyen | Faible | Quick win probable: separateur plus net ou reprise d'un marqueur proche de l'ancien comportement. | A faire |
| HFR-016 | Pastilles drapeaux/favoris moins identifiables | UX | Moyen | Faible a moyenne | Impact sur le scan des listes. Peut etre traite avec icones/couleurs plus distinctes sans revenir integralement a l'ancien design. | A faire |
| HFR-017 | Fenetre de reponse non conservee quand elle est glissee vers le bas | UX / Perte de donnees | Moyen | Moyenne a elevee | Risque de perte de texte, donc a prendre au serieux. Complexite depend du mode de presentation de l'editeur et du stockage d'un brouillon temporaire. | A faire |
| HFR-018 | Pull-to-refresh des favoris trop difficile a declencher | UX | Moyen | Faible a moyenne | Geste frequent, probablement corrigeable par ajustement de layout/scroll view si le probleme est localise. | A faire |
| HFR-019 | Demarrage pas au bon endroit / choix de l'ecran initial | UX | Moyen | Faible a moyenne | Peut se regler par preference utilisateur ou restauration du dernier onglet. Impact fort pour certains usages quotidiens. | A faire |
| HFR-020 | Insertion photo moins directe | UX | Faible a moyen | Moyenne | A optimiser apres les bugs editeur principaux. Peut etre lie aux contraintes modernes de Photo Picker. | A faire |

## P4

| ID | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- |
| HFR-021 | Barre de defilement ou indicateur de position dans les topics | Amelioration | Faible a moyen | Faible a moyenne | Utile pour l'orientation dans les longues pages. Non bloquant, mais peut renforcer la lisibilite de fin de page. | A faire |
| HFR-022 | Bouton `...` demande plus bas, pres du `+` | UX | Faible a moyen | Faible | Ajustement ergonomique iPhone. A evaluer avec les contraintes de hierarchy toolbar/navigation. | A faire |
| HFR-023 | Espacement en haut des listes en theme sombre | Finition UI | Faible | Faible | Finition visuelle, probablement simple. A grouper avec les ajustements theme sombre. | A faire |
| HFR-024 | Taille de caracteres plus petite | Amelioration | Faible a moyen | Faible a moyenne | Demande legitime pour les utilisateurs qui veulent plus de densite. Peut etre combine avec HFR-013. | A faire |
| HFR-025 | Filtrage des topics par drapeaux dans Categories | Fonction | Faible a moyen | Moyenne | Amelioration utile, mais pas une regression bloquante. | A faire |
| HFR-026 | Support multi-fenetre iPad | Fonction | Faible a moyen | Moyenne a elevee | Interessant pour power users iPad, mais plus large techniquement et moins urgent que restaurer le confort iPad de base. | A faire |
| HFR-027 | Creation de topic / TU peu claire ou indisponible selon appareil | Fonction / UX | Faible a moyen | Moyenne | A clarifier: si la fonction existe, ameliorer la decouvrabilite; sinon a planifier hors correctifs 4.0. | A faire |
| HFR-028 | Creation de sondage dans un topic | Fonction | Faible | Moyenne a elevee | Fonction avancee et rare. A garder en backlog, pas prioritaire. | A faire |
| HFR-029 | Plus de choix d'icones d'app | Finition | Faible | Faible | Simple si les assets existent, mais faible impact d'usage. | A faire |

## P5

| ID | Sujet | Type | Impact | Complexite | Avis | Statut |
| --- | --- | --- | --- | --- | --- | --- |
| HFR-030 | Revenir strictement a l'ancien design | Demande generale | Variable | Elevee | Demande exprimee indirectement via plusieurs irritants. Ne pas traiter comme une issue unique: preferer corriger les regressions precises listees ci-dessus. | Loggue |

## Ordre recommande

1. Corriger les quick wins visibles: HFR-004, HFR-005, HFR-015, HFR-014.
2. Stabiliser les flux principaux: HFR-001, HFR-002, HFR-003, HFR-009.
3. Restaurer le confort iPad: HFR-007 puis HFR-006.
4. Repondre aux critiques de densite/lisibilite: HFR-013, HFR-012, HFR-016, HFR-008.
5. Traiter les ameliorations fonctionnelles non bloquantes: HFR-025 a HFR-029.
