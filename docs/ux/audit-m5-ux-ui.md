# Audit M5 « UX evolutions » : synthèse des impacts UX/UI

Date : 6 novembre 2026. Rédigé pour le PO comme matière première du cadrage et de l'orchestration de la suite.

## 0. Sources lues et limites

Toutes les sources viennent de la branche `dev-swift` d'`ezzz/HFRnow`, état du 6 novembre 2026 au commit `8384b4c6`. La copie locale est sur `master`, qui n'a pas ces documents.

| Source | Contenu utile |
|---|---|
| `docs/ROADMAP.md` | Définition de M5 et critère de sortie |
| `docs/LOTS.md`, section « M5 · UX evolutions » | Lots déplacés, découpages (a)/(b), dépendances modifiées |
| `docs/lots/LOT-174` à `LOT-184` | Fiches des lots issus des découpages (gabarits à compléter) |
| `docs/FEATURES.md` | Backlog FEAT-001 à 021, principes UX de l'opérateur, liste « à ne pas perdre » |
| `docs/migration/GAP-LEGACY-VS-SWIFT.md` | 155 écarts legacy / SwiftHFR, classement H.1, décisions UXD-01 à 25 |
| `docs/research/user-feedback-p450-510.md` | Retours du topic HFR pages 450 à 510, fréquences, top 10 |
| `docs/research/redface2-comparison.md`, `cross-platform-features.md`, `bybifok-proposals.md` | Comparaison Android, alignement multi-clients, origine des idées |
| Issues [#379](https://github.com/ezzz/HFRnow/issues/379), [#413](https://github.com/ezzz/HFRnow/issues/413), [#324](https://github.com/ezzz/HFRnow/issues/324), [#368](https://github.com/ezzz/HFRnow/issues/368) | Proposition M5, application des décisions, tableau de bord, orchestrateur |
| Issues des lots M5, plus [#509](https://github.com/ezzz/HFRnow/issues/509) et [#513](https://github.com/ezzz/HFRnow/issues/513) | Périmètre et critères d'acceptation |

Limites :
- M5 n'est pas un jalon GitHub. Il n'existe que dans les documents et les titres d'issues, et les étiquettes ne permettent pas de filtrer M5.
- Le rapport d'écarts est un instantané d'avant les décisions UXD. Certaines lignes « b » ont depuis été ramenées au comportement legacy par des issues de M1 ou M2 (voir §4.3).
- Rien n'a été lancé ni testé. Les fréquences de retours utilisateurs sont celles de la recherche, sur les pages 450 à 510 du topic.

## 1. Synthèse pour le PO

**Ce qu'est M5.** Le jalon regroupe toutes les évolutions UX que la parité legacy n'exige pas. La règle, décidée par l'opérateur le 2 novembre 2026 : M1 à M4 livrent l'app legacy telle que les utilisateurs la connaissent, M5 reçoit tout le reste et rien n'est abandonné. M5 est bloqué tant que la parité M4 n'est pas validée, et l'orchestrateur décide de son ouverture.

**Taille.** 30 lots, dont 1 déjà soldé :
- 19 lots déplacés en bloc depuis M2 et M4 ;
- 10 lots nés des découpages, de LOT-174 à LOT-183 ;
- LOT-184, l'aperçu serveur ;
- 2 issues M5 récentes sans lot : notifications MP fines et visionneuse d'images.

**Contrainte structurante.** Chaque évolution M5 est optionnelle : le comportement legacy reste le défaut et l'évolution arrive par un réglage ou une entrée séparée. C'est écrit dans les critères d'acceptation de chaque lot découpé et dans les principes UX de `FEATURES.md`. Toute évolution de navigation exige en plus le soutien de la communauté, consigné sur son issue.

**Ce qui pèse vraiment côté UX.** Sur les 30 lots, sept changent l'expérience en profondeur et concentrent le risque et la valeur :

| Sujet | Lots | Pourquoi c'est structurant |
|---|---|---|
| Grands écrans et iPhone Duo | LOT-147, 145, 146 | Demande forte, environ 45 retours ; dépend d'un document de design Phase 5 qui n'existe pas encore |
| Lecture continue | LOT-148 | Change la boucle de lecture ; risque protocole fort, car un GET authentifié déplace le drapeau ; avis partagés |
| Navigation dans un sujet | LOT-110, 112, 178 | Navigateur de pages, scrubber, bannière « Nouveau » ; touche chaque lecture |
| Écran « À suivre » | LOT-143, 144 | Nouvelle porte d'entrée ; doit rester optionnel selon les principes |
| Citation et réponse rapide | LOT-153 | Plus gros fil de plaintes de la 4.0, environ 25 à 35 retours |
| Liens HFR ouverts dans l'app | LOT-138 | Environ 13 retours ; dépend d'une capture du fichier d'association du site |
| Session expirée pendant la rédaction | LOT-142 | Douleur la plus ancienne, environ 30 retours ; risque de double post |

Les autres lots sont des améliorations locales : formatage, MP, thème, caches, raccourcis, Spotlight.

**Points d'attention principaux :**
1. La quasi-totalité des fiches M5 sont des gabarits vides et 16 FEAT sur 21 n'ont pas de spec. M5 n'est pas prêt à être lancé tel quel.
2. Les priorités sont incohérentes. Les lots découpés sont tous en priorité basse, alors que leurs FEAT d'origine sont en priorité haute ou moyenne.
3. Plusieurs sujets sont orphelins : aucun lot, ni en M1 à M4 ni en M5 (§4.2).

## 2. Cadre de M5

### 2.1 Règles de jalon

- **M4 = parité legacy validée.** M1 à M4 portent la couche Swift d'ezzz avec l'UX legacy, plus quelques exceptions décidées : UXD-01, 12, 13, 15 pour les brouillons par sujet, 24 pour l'iPad.
- **M5 = évolutions.** Tout écart au legacy ou au plan initial : options B différées, FEAT, moitiés (b) des lots découpés.
- **Dépendances coupées** pour que M4 n'attende jamais M5. LOT-164, la porte de parité, ne dépend plus de 100, 101, 110 et 146. LOT-163 ne dépend plus de 112.
- **Statut.** Les lots M5 sont `status: on-hold` (retenus par une décision, pas par une dépendance, #835) jusqu'à la validation de la parité M4 et l'ouverture de M5 par l'orchestrateur.

### 2.2 Principes UX de l'opérateur qui contraignent M5

| Principe | Effet sur M5 |
|---|---|
| Préserver ce qui marche | La barre d'onglets Catégories / Favoris / Messages / Plus, la liste Catégories et le menu Plus restent tels quels. « À suivre » ne vient qu'en option communautaire. |
| Dense par défaut, taille choisie par le lecteur | La référence de densité est la liste Favoris legacy. Aucun rendu zoomé par défaut. |
| Le défaut garde l'UX legacy, les changements sont des réglages | Chaque lot M5 doit livrer un réglage ou une entrée séparée. |
| Les liens HFR restent dans l'app | LOT-138 prolonge ce principe vers l'extérieur de l'app. |

### 2.3 Origine des idées

La majorité des FEAT vient des propositions de Bybifok : son message, les PR #3 à #6 et le prototype ultra-hfr. Le crédit lui reste dans les specs, les PR et `CREDITS.md`. Deux issues récentes viennent de Redface 2, le client Android : la visionneuse ([#513](https://github.com/ezzz/HFRnow/issues/513)) et l'idée de préchargement anonyme.

## 3. Impacts UX/UI par zone

Légende des colonnes :
- **Signal utilisateur** : fréquence approximative dans les retours des pages 450 à 510 (`user-feedback-p450-510.md`).
- **Prio.** : priorité inscrite sur le lot.
- **Bloqué par** : dépendances non terminées, captures attendues ou document manquant.

### 3.1 Lecture d'un sujet

| Lot | Issue | Évolution | Origine | Signal utilisateur | Prio. | Bloqué par | Impact UX/UI |
|---|---|---|---|---|---|---|---|
| LOT-110 | [#201](https://github.com/ezzz/HFRnow/issues/201) | Navigateur de pages depuis le numéro dans le titre : aller à, première et dernière, ±5, blocs de 50, toutes les pages jusqu'à 30 | FEAT-002, UXD-10 | ≈6, livré en partie en 4.0 | haute | Rien : dépendances terminées | Remplace l'invite « Page… » ; nouveau point d'entrée dans le titre ; spec FEAT-002 à écrire |
| LOT-112 | [#203](https://github.com/ezzz/HFRnow/issues/203) | Scrubber à droite : bulle « p. N », saut au relâcher, point et aimant sur la première page non lue, retour haptique toutes les 100 pages, action VoiceOver ajustable | FEAT-004 | aucun retour direct | moyenne | LOT-110, LOT-111 | Nouvel élément permanent sur le bord ; conflit possible avec le swipe de page et le geste retour ; accessibilité à garantir |
| LOT-178 | [#418](https://github.com/ezzz/HFRnow/issues/418) | Bannière « Nouveau » au premier message non lu, position stable pendant le chargement des images | FEAT-007, UXD-11 | ≈5, nostalgie du séparateur pointillé | basse | LOT-111 | Remplace ou complète le séparateur legacy ; FEAT-007 a déjà une spec |
| LOT-148 | [#238](https://github.com/ezzz/HFRnow/issues/238) | Défilement continu en option, désactivé par défaut, 10 pages en mémoire, retour haptique par page | FEAT-017 | ≈14, avis partagés : environ 8 le veulent optionnel ou pas du tout | basse | LOT-083, 045, 106 | Change la boucle de lecture, l'actualisation, le repère de page. **Risque protocole** : un GET authentifié marque lu, donc préchargement anonyme puis rechargement authentifié, deux requêtes par page |
| LOT-176 | [#416](https://github.com/ezzz/HFRnow/issues/416), fermée | Galerie HD avec swipe | FEAT-014 | ≈6 | — | — | **Soldé** : livré dans LOT-109 (#472) |
| — | [#513](https://github.com/ezzz/HFRnow/issues/513) | Visionneuse : haute définition derrière les miniatures sur plus d'hébergeurs, chargement progressif, « Ouvrir dans le navigateur » | Redface 2 | ≈12 pour les miniatures floues, ≈30 sur les outils image | — | Captures de paires d'URL | Une seule table d'hébergeur gérée aujourd'hui ; pas encore de lot ni de FEAT |

### 3.2 Rédaction et citation

| Lot | Issue | Évolution | Origine | Signal utilisateur | Prio. | Bloqué par | Impact UX/UI |
|---|---|---|---|---|---|---|---|
| LOT-153 | [#243](https://github.com/ezzz/HFRnow/issues/243) | Plateau de citations avec compteur, réponse dans l'ordre du sujet, vidé après envoi confirmé ; barre de réponse rapide dans le lecteur | FEAT-006, UXD-17 | ≈25 à 35, plus gros fil de la 4.0 | haute | LOT-086 | Nouvel élément permanent en bas du lecteur ; concurrence la barre de pages ; doit coexister avec le bascule de citation par message qui reste en M2 |
| LOT-174 | [#414](https://github.com/ezzz/HFRnow/issues/414) | Barre de mise en forme visible au-dessus du clavier | UXD-18 | ≈6 | basse | LOT-085 | Le moteur d'insertion et le menu Édition restent en M2 ; ajoute de la hauteur au composeur |
| LOT-152 | [#242](https://github.com/ezzz/HFRnow/issues/242) | Onglet d'aperçu dans le composeur, rendu local identique au lecteur | FEAT-013 | ≈1 explicite | moyenne | LOT-097, 084, 083 | Nouvel onglet du composeur ; respecter la politique d'images |
| LOT-184 | [#449](https://github.com/ezzz/HFRnow/issues/449) | Aperçu HFR à la demande par le serveur | FEAT-013, décision O-1 | — | basse | Moteur seul | Action « aperçu HFR » ajoutée ensuite par LOT-152 ; le brouillon ne quitte l'appareil qu'à la demande |
| LOT-151 | [#241](https://github.com/ezzz/HFRnow/issues/241) | Refus des emoji à l'envoi avec suggestion de smiley | FEAT-012, UXD-16 | constat p. 478 | moyenne | Capture CAP-N3 (#171) | En M2, les emoji sont bloqués silencieusement à la frappe ; M5 remplace par un refus explicite à l'envoi |
| LOT-142 | [#232](https://github.com/ezzz/HFRnow/issues/232) | Feuille de reconnexion quand la session expire, brouillon gardé, renvoi seulement si le serveur confirme l'échec | FEAT-009, UXD-19 | ≈30, douleur la plus ancienne | haute | LOT-044, 084, 081 ; capture #137 | Remplace le toast M2 ; **risque de double post** à tester |
| LOT-101 | [#192](https://github.com/ezzz/HFRnow/issues/192) | Sélecteur des brouillons archivés | UXD-01 | ≈2 | basse | LOT-084 | Existe sur `master` mais pas au commit de référence ; conflit documentaire avec LOT-084 qui le dit non porté |
| LOT-100 | [#191](https://github.com/ezzz/HFRnow/issues/191) | Création de sondage dans un nouveau sujet | backlog HFR-028 | ≈1 | basse | LOT-089 ; capture CAP-N2 (#170) | Étiqueté « parité » mais absent du legacy de référence |
| LOT-175 | [#415](https://github.com/ezzz/HFRnow/issues/415) | Supprimer le premier post d'un sujet public, ce qui supprime le sujet, avec confirmation | UXD-14 | — | basse | LOT-088 | Action destructrice ; confirmation obligatoire |

### 3.3 Listes, favoris et drapeaux

| Lot | Issue | Évolution | Origine | Signal utilisateur | Prio. | Bloqué par | Impact UX/UI |
|---|---|---|---|---|---|---|---|
| LOT-177 | [#417](https://github.com/ezzz/HFRnow/issues/417) | Même jeu de swipes dans toutes les listes : Lu avec « Annuler », Super favori, Retirer | FEAT-008, UXD-08 | ≈8 à 20 | basse | LOT-125, PR #542 en revue | Change la mémoire musculaire des swipes legacy Lu / Supprimer ; « Annuler » demande l'URL du drapeau précédent |
| LOT-143 | [#233](https://github.com/ezzz/HFRnow/issues/233) | Écran « À suivre » : reprise de lecture, MP non lus, super favoris, favoris, drapeaux groupés par catégorie | FEAT-001 | indirect | haute | LOT-126, 124, 090, 092 | Nouvelle porte d'entrée ; optionnel par principe ; ne doit jamais charger une page de sujet |
| LOT-144 | [#234](https://github.com/ezzz/HFRnow/issues/234) | « À suivre » : section Alertes Qualitay, première entrée de la barre latérale iPad, réglage d'écran de démarrage | FEAT-001 | ≈8 pour l'écran de démarrage | moyenne | LOT-143, 133, 119 | Migration des valeurs legacy de l'écran de démarrage à prévoir |
| LOT-154 | [#244](https://github.com/ezzz/HFRnow/issues/244) | « On t'a cité » dans « À suivre » et dans les notifications | FEAT-018 | ≈10 | basse | Capture #126 de faisabilité | Abandonné si le serveur ne donne aucun signal ; le libellé tutoie |

### 3.4 Messages privés et notifications

| Lot | Issue | Évolution | Origine | Signal utilisateur | Prio. | Bloqué par | Impact UX/UI |
|---|---|---|---|---|---|---|---|
| LOT-181 | [#421](https://github.com/ezzz/HFRnow/issues/421) | Suppression d'une conversation, membres d'un MP de groupe | UXD-20 | demandé dans les retours | basse | LOT-127 | Nouvelles actions sur les MP |
| LOT-182 | [#422](https://github.com/ezzz/HFRnow/issues/422) | MP à plusieurs destinataires, entrée depuis les profils | UXD-20 | ≈1, MP depuis profil sur iPad | basse | LOT-128 | Composeur MP enrichi |
| — | [#509](https://github.com/ezzz/HFRnow/issues/509) | Notifications MP fines : global, individuel, groupe ; mise en sourdine d'un MP de groupe | nouveau | — | — | LOT-140 en M4 | Nouveaux réglages et action de sourdine ; pas encore de lot |
| LOT-141 | [#231](https://github.com/ezzz/HFRnow/issues/231) | Action Raccourcis « Vérifier HFR », notification des seuls nouveaux éléments, intervalle minimal | FEAT-005 | ≈10 sur les alertes | moyenne | LOT-092, 091, 140 ; capture CAP-N5 (#173) | Notifications sans serveur ; nécessite une explication à l'utilisateur |
| LOT-183 | [#423](https://github.com/ezzz/HFRnow/issues/423) | Avis de première utilisation des Alertes Qualitay | — | — | basse | LOT-134 ; question Q-4 | Revient en M4 si App Review l'exige |

### 3.5 Grands écrans, iPhone Duo et continuité

| Lot | Issue | Évolution | Origine | Signal utilisateur | Prio. | Bloqué par | Impact UX/UI |
|---|---|---|---|---|---|---|---|
| LOT-147 | [#237](https://github.com/ezzz/HFRnow/issues/237) | Dispositions en colonnes iPhone Duo et iPad : deux colonnes déplié, onglets en rail plié, barre latérale épinglée ou à la demande | FEAT-016, UXD-25 | ≈45 iPad, ≈10 Duo | haute | **Document de design Phase 5 inexistant** ; LOT-145 | Le plus gros chantier UX de M5 ; le périmètre se résume à « selon le document de design » |
| LOT-145 | [#235](https://github.com/ezzz/HFRnow/issues/235) | Restauration d'état par scène : sélection, position de lecture, barre latérale ; jamais de colonne vide après changement d'app | FEAT-015 | ≈8 bugs iPad p. 507-509 | moyenne | LOT-090, 082, 083 | Plusieurs de ces bugs sont signalés sur l'app actuelle ; [#512](https://github.com/ezzz/HFRnow/issues/512) en traite un en M4 |
| LOT-146 | [#236](https://github.com/ezzz/HFRnow/issues/236) | Multi-fenêtre iPad : « Ouvrir dans une nouvelle fenêtre », glisser-déposer d'un sujet | parité supposée | ≈25 grands écrans | moyenne | LOT-145 | Livré sur `master` en 4.0.1 mais absent du legacy de référence |
| LOT-149 | [#239](https://github.com/ezzz/HFRnow/issues/239) | Raccourcis clavier J, K, Q, R, ⌘F | FEAT-021 | ≈1 | basse | LOT-083, 084, 110 | Faible exposition |

Reste en M4 hors M5 : remplir l'écran extérieur du Duo sans bande noire ([#432](https://github.com/ezzz/HFRnow/issues/432)).

### 3.6 Apparence et réglages

| Lot | Issue | Évolution | Origine | Signal utilisateur | Prio. | Bloqué par | Impact UX/UI |
|---|---|---|---|---|---|---|---|
| LOT-180 | [#420](https://github.com/ezzz/HFRnow/issues/420) | Couleur d'accent unique avec aperçu en direct | FEAT-010, UXD-22 | ≈25 sur les thèmes | basse | LOT-122 | Le curseur de teinte legacy reste en M4 ; ne pas écraser la teinte existante, défaut constaté dans la PR #5 |
| LOT-179 | [#419](https://github.com/ezzz/HFRnow/issues/419) | Taille des caches et vidage dans les réglages | GAP-152 | ≈3 | basse | LOT-120 | Simple ; demande réelle sur la croissance du stockage |

### 3.7 Intégrations système

| Lot | Issue | Évolution | Origine | Signal utilisateur | Prio. | Bloqué par | Impact UX/UI |
|---|---|---|---|---|---|---|---|
| LOT-138 | [#228](https://github.com/ezzz/HFRnow/issues/228) | Liens universels, partage et presse-papier vers l'app | FEAT-020 | ≈13 | haute | LOT-095, 137 ; capture du fichier d'association #127 | Dépend du site, que l'équipe ne contrôle pas |
| LOT-150 | [#240](https://github.com/ezzz/HFRnow/issues/240) | Spotlight pour les sujets lus, jamais les MP | FEAT-021 | — | basse | LOT-090, 137 | Faible exposition |

## 4. Constats de l'audit

### 4.1 Maturité et préparation

- **Fiches vides.** Les fiches LOT-174 à 183 sont des gabarits créés le 2 novembre : comportement, cas limites et fixtures sont « à écrire ». Les 19 lots déplacés n'ont pas de fiche du tout.
- **Specs FEAT manquantes.** Seules FEAT-003, 007, 011, 014 et 019 ont une spec. Parmi elles, seule FEAT-007 sert un lot M5, LOT-178. Toutes les FEAT M5 doivent passer par une spec avant code, selon l'ADR 0011.
- **Document de design Phase 5 absent.** LOT-147 ne peut pas démarrer. C'est le seul lot M5 de difficulté « difficile » avec LOT-148.
- **Captures attendues** avant code : #126 pour « On t'a cité », #127 pour les liens universels, #137 pour la session expirée, #170 pour la création de sondage, #171 pour les emoji, #173 pour « Vérifier HFR ».

### 4.2 Trous et incohérences

| Constat | Détail | Conséquence |
|---|---|---|
| Sujets sans lot nulle part | Icônes de catégories (GAP-021), teinte des lignes par drapeau (GAP-027), modes du bouton + (GAP-102), thème selon l'heure (GAP-143, abandonné), actions rapides d'icône (GAP-010, abandonné), annuler / rétablir et vider (GAP-086, rattachés à LOT-085) | Les teintes de drapeau et les modes du bouton + sont des sujets de nostalgie forte dans les retours ; à décider explicitement |
| Issues M5 hors `LOTS.md` | [#509](https://github.com/ezzz/HFRnow/issues/509) et [#513](https://github.com/ezzz/HFRnow/issues/513) n'ont ni FEAT ni lot | À intégrer à l'ouverture de M5 |
| Priorités incohérentes | Les lots découpés sont en basse priorité alors que FEAT-006, 007, 008 sont en haute ; LOT-148 est en basse alors que la lecture continue est un sujet clivant | Revoir les priorités à l'ouverture, idéalement avec l'avis des utilisateurs |
| Faux libellés « parité » | LOT-100, LOT-101, LOT-146 et la suppression de LOT-127 n'existent pas au commit de référence | Le rapport d'écarts les corrige déjà ; à garder en tête pour le message aux utilisateurs |
| Conflit brouillons archivés | LOT-084 les dit non portés, LOT-101 prévoit le sélecteur | Trancher avant LOT-101 |
| LOT-176 à fermer | Rien à faire, la galerie est livrée | Fermer en « non planifié » |
| FEAT-008 ouvert en double | La PR #542 de LOT-125 garde FEAT-008 ouvert pour LOT-177 | Rien à faire, juste à confirmer par l'orchestrateur |
| Tutoiement | « On t'a cité » | Décision de ton à prendre par le mainteneur |

### 4.3 Ce qui est déjà ramené au legacy avant M5

Ces points apparaissent comme évolutions dans le rapport d'écarts mais une décision UXD les a ramenés au legacy en M1 ou M2. Ils ne relèvent donc pas de M5 :

| UXD | Sujet | Issue |
|---|---|---|
| 02 | Barre d'onglets masquée dans le lecteur | [#424](https://github.com/ezzz/HFRnow/issues/424) |
| 03 | Menu compte avec avatar dans chaque barre de liste | [#425](https://github.com/ezzz/HFRnow/issues/425) |
| 04 | Retoucher un onglet l'actualise | [#426](https://github.com/ezzz/HFRnow/issues/426) |
| 05, 06 | Liste Catégories legacy et filtre Tous / Favoris / Suivis / Lus | [#427](https://github.com/ezzz/HFRnow/issues/427) |
| 07 | Ligne de sujet legacy | LOT-169 |
| 10 | Commandes de page legacy | [#428](https://github.com/ezzz/HFRnow/issues/428) |
| 15 | Glisser vers le bas enregistre le brouillon | [#429](https://github.com/ezzz/HFRnow/issues/429) |
| 16 | Emoji bloqués à la frappe | [#437](https://github.com/ezzz/HFRnow/issues/437) |
| 21 | « Déconnexion » restaurée | [#430](https://github.com/ezzz/HFRnow/issues/430) |
| 24 | Grand iPhone en paysage, lecteur pleine largeur | [#431](https://github.com/ezzz/HFRnow/issues/431) |

### 4.4 Ce que disent les utilisateurs et que M5 couvre peu

D'après le top 10 et les attentes de `user-feedback-p450-510.md` :
- **Thèmes saisonniers et personnalisés**, environ 25 retours : seule la couleur d'accent est en M5 ; le noir pur et l'assombrissement sont en M4.
- **Taille de texte dans les listes et le composeur**, environ 10 retours : traité en M1 par LOT-169, pas en M5.
- **Teinte des drapeaux et pastilles colorées** : sans lot.
- **Bouton + qui embarque les citations** : environ 25 retours ; LOT-153 y répond en partie, mais les modes du bouton + n'ont pas de lot.
- **Écran « Quoi de neuf »** après une mise à jour : leçon explicite du déploiement 4.0, sans lot.
- **Envoi de diagnostics depuis l'app** : suggéré, sans lot.

## 5. Lecture PO : regroupement proposé pour la suite

Proposition de thèmes pour orchestrer M5. Ce n'est pas une décision, seulement une matière de travail.

| Thème | Lots | Besoin avant code | Avis utilisateurs utile |
|---|---|---|---|
| **A. Navigation dans un sujet** | 110, 112, 178 | Specs FEAT-002 et 004 ; arbitrer la coexistence scrubber, swipe de page et geste retour | Moyen |
| **B. Lecture continue** | 148 | Évaluation technique : WebView ou rendu natif, double requête par page | **Fort** : sujet clivant |
| **C. Grands écrans et Duo** | 147, 145, 146, 149 | **Document de design Phase 5** ; maquettes à faire essayer sur Duo | **Fort** : besoin d'essai réel |
| **D. Réponse et citation** | 153, 174, 152, 184, 151, 142, 101 | Specs FEAT-006, 009, 012, 013 ; tests anti-double post | Moyen, sur LOT-153 |
| **E. Porte d'entrée « À suivre »** | 143, 144, 154 | Spec FEAT-001 ; soutien communautaire obligatoire ; capture #126 | **Fort** : optionnel par principe |
| **F. Listes et swipes** | 177 | Après fusion de LOT-125 | Faible |
| **G. MP et notifications** | 181, 182, 141, 183, #509 | Captures #173 ; transformer #509 en lot | Moyen, sur la priorité |
| **H. Apparence et réglages** | 180, 179 | Rien de bloquant | Faible |
| **I. Intégrations système** | 138, 150 | Capture #127 | Faible |
| **J. Images** | #513, 100 | Captures de paires d'URL ; transformer #513 en lot | Faible |

Lien avec le cadrage du questionnaire UX (`docs/ux/cadrage-points-ux.md`) :
- le point A1 « lecture d'un sujet » correspond aux thèmes A et B ;
- le point A5 « iPad et Duo » correspond au thème C ;
- le point A10 « nouvelles fonctions » peut prendre comme liste de jetons les thèmes D, E, G, I et J.

## 6. Décisions à prendre côté PO

1. **Ouverture de M5** : attendre la parité M4 complète, ou ouvrir par thème dès que ses dépendances sont prêtes.
2. **Document de design Phase 5** : qui le produit et quand, puisqu'il bloque le thème C.
3. **Révision des priorités** des lots M5, en particulier 148, 153, 177 et 178.
4. **Sujets orphelins** : teinte des drapeaux, modes du bouton +, écran « Quoi de neuf », diagnostics. Créer un lot ou abandonner explicitement.
5. **Intégration de #509 et #513** comme FEAT et lots.
6. **Usage du questionnaire** : sur quels thèmes recueillir l'avis avant de spécifier, en priorité B, C et E.
