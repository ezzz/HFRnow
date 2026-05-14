# Plan — Finalisation migration SwiftUI et réduction Objective-C

## Objectif

Porter toutes les features avec UI en SwiftUI. Garder Objective-C pour les traitements lourds ou risqués tant qu’ils sont utilisés : parsing forum, services legacy, comptes/session, stockage historique, caches.

Le plan initial a été dépassé par l’implémentation : la majorité des écrans UI sont maintenant SwiftUI. La suite doit donc éviter de continuer à raisonner comme une migration “à démarrer” et se concentrer sur les manques restants et la réduction prudente du legacy.

## Contraintes

1. Ne pas porter `OfflineMessagesTableViewController`.
2. Garder le rendu fichier-local de `MessagesView`.
3. Ne pas ajouter de nouvelle UI XIB/NIB.
4. Ne pas supprimer de code Objective-C tant que son inutilité n’est pas prouvée.
5. Les choix UI récents priment : SwiftUI natif, Liquid Glass iOS 26 via helpers, fallback lisible iOS antérieurs.
6. Pas d’effort dédié à compléter les tests dans cette phase.
7. Les suppressions Objective-C arriveront après cartographie, pas pendant la finalisation UI.

## État Actuel

UI SwiftUI couverte :

| Zone | Fichiers |
|---|---|
| Root/navigation/forums/topics | `MainWindow.swift`, `Common.swift` |
| Messages topic/actions | `MessagesView.swift` |
| Composer réponse/édition/MP | `AnswerView.swift`, `ReplyComposer.swift`, `ReplyService.swift` |
| Profil | `UserProfileView.swift` |
| Sondage | `PollView.swift`, `PollData.swift` |
| Recherche forum | `ForumSearchView.swift`, `ForumSearchService.swift` |
| Recherche topic | `TopicSearchSheetView.swift`, `TopicSearchService.swift` |
| Favoris | `Favorites.swift` |
| MP | `MPListView.swift` |
| Bookmarks | `BookmarksPlusView.swift` |
| AQ | `AQPlusView.swift` |
| Settings/listes BL/WL | `AppSettingsView.swift` |
| Plus principal | `PlusTab.swift` |
| Crédits/charte | `StaticInfoPageView.swift` |
| Comptes/login | `AddAccountView.swift`, `AccountsStore.swift`, `LoginService.swift`, `AccountSessionService.swift` |

Manques probables :

| Priorité | Manque | Action |
|---|---|---|
| P0 | Cartographie Objective-C restant | Inventorier avant réduction |
| P0 | Session/compte startup/background | Valider manuellement et documenter |
| P1 | Filtres rapides forum | Porter ou abandonner explicitement |
| P1 | Aide / Infos / Feedback / Pay | Confirmer si encore produits utiles |
| P1 | Thème avancé legacy | Comparer au nouveau `AppSettingsView` et décider |
| P2 | iPad | Étude seulement |
| P2 | Previews exhaustives | Opportuniste uniquement |

## Phase F1 — Recalage Documentaire

Objectif : aligner les docs sur l’état réel.

Travail :

1. Mettre à jour `GAPv2.md`.
2. Reclasser les gaps historiques en `Done`, `Done/Watch`, `InProgress`, `NotStarted`, `Deferred`.
3. Identifier les derniers manques UI probables.
4. Retirer l’obligation d’étendre les tests comme critère bloquant.

Critère de sortie :

- Le plan reflète les features réellement livrées.
- Les prochaines tâches ne réouvrent pas des migrations déjà faites.

## Phase F2 — Audit Objective-C Sans Suppression

Objectif : savoir exactement ce qui reste utilisé.

Statut 2026-05-01 : première passe statique effectuée et documentée dans `GAPv2.md`. Les routes SwiftUI actives ont aussi été validées statiquement. Un smoke simulateur a validé build, installation et lancement sans crash immédiat. Aucune suppression proposée. La suite de F2 doit valider par navigation manuelle sur simulateur/device, puis resserrer les wrappers.

Travail :

1. Lister les références Swift vers Objective-C. **Fait en statique.**
2. Lister les XIB/NIB encore référencés dans le projet Xcode. **Fait en statique.**
3. Classer chaque zone Objective-C. **Première classification faite.**
   - `KEEP_TREATMENT` : traitement lourd encore utilisé.
   - `WRAP` : traitement utilisé mais interface à isoler.
   - `PORT_UI` : UI legacy encore visible à porter.
   - `QUARANTINE` : probablement inutilisé, à garder temporairement.
   - `DELETE_LATER` : suppression future après preuve.
4. Documenter la table dans un fichier dédié ou dans `GAPv2.md`. **Fait dans `GAPv2.md`.**
5. Valider statiquement les routes SwiftUI principales pour confirmer que les wrappers UIKit quarantaine ne sont pas routés. **Fait.**
6. Valider par lancement manuel les routes SwiftUI principales pour confirmer que les wrappers UIKit quarantaine ne sont pas affichés. **Smoke lancement fait ; navigation manuelle restante.**
7. Rédiger ensuite un plan de réduction par petits lots, sans suppression groupée.

Critère de sortie :

- Aucune suppression dans F2.
- Une carte fiable du legacy restant.
- Les routes runtime ont confirmé les zones `QUARANTINE`.

Résultat de première passe :

| Classement | Conclusion |
|---|---|
| `KEEP_TREATMENT` | `MultisManager`, `MPStorage`, `BlackList`, `SmileyCache`, `MessagesTableViewController`, `ParseMessagesOperation`, loaders forums/topics/favoris/MP/search, `ThemeManager`, `k`, `SDWebImage` restent utiles |
| `WRAP` | Priorité à resserrer `MessagesTableViewController`, session/compte, `MPStorage`, `BlackList` |
| `PORT_UI` | Aide, Infos, Feedback, Pay, Configuration/liens profil secondaires, G02 filtres rapides forum à décider |
| `QUARANTINE` | Plus/settings/login/profil/poll/alerte/composer/bookmarks/AQ UIKit remplacés côté SwiftUI mais encore compilés |
| `DELETE_LATER` | Aucun candidat immédiat |

Validation routes SwiftUI statique :

| Route | Résultat |
|---|---|
| Root tabs | `RootTabView` route vers `CategoriesListView`, `FavoritesListView`, `MPListView`, `PlusHomeView` |
| iPad/sidebar | `selectedTabContent` route vers les mêmes vues SwiftUI |
| Plus | `AppSettingsView`, `ForumSearchView`, `BookmarksPlusView`, `AQPlusView`, `StaticInfoPageView`, mail suppression compte |
| Topics/listes | Navigation vers `MessagesView` |
| Composer/profil/poll/alerte | SwiftUI (`AnswerView`, `UserProfileView`, `PollSheet`, `ModerationAlertComposerView`) |
| Wrappers non routés | `PlusTableViewWrapper`, `MessageViewWrapper`, `ObjCMessageComposerView`, `ObjCViewControllerHost` |

Smoke simulateur :

| Étape | Résultat |
|---|---|
| Build Debug iPhone 17 Pro iOS 26.4 | OK |
| Install app | OK |
| Launch `hfrplus.red.super` | OK, PID retourné |
| Screenshot automatique | Non concluant, `simctl io screenshot` bloqué |

## Phase F3 — Derniers Manques UI

Objectif : fermer les écarts utilisateur visibles.

Ordre conseillé :

1. G02 filtres rapides forum si encore considérés utiles.
2. Aide/Infos/Feedback/Pay : décider route par route.
3. Thème avancé : comparer legacy et `AppSettingsView`; ne porter que ce qui a une valeur réelle.
4. Passe UI cohérence Liquid Glass sur les écrans récemment ajoutés.

Critère de sortie :

- Plus aucun écran UIKit/XIB visible dans le flux iPhone principal, sauf exception documentée.

## Phase F4 — Stabilisation Runtime

Objectif : éviter les régressions silencieuses liées au legacy conservé.

Travail :

1. Checklist manuelle startup/background.
2. Checklist compte : ajout, switch, logout, cookies, hash.
3. Checklist messages : ouvrir topic, répondre, éditer si applicable, MP, profil, sondage, AQ, alerte modération.
4. Checklist Plus : settings, recherche, bookmarks, AQ, crédits/charte, suppression compte.

Critère de sortie :

- Les flux principaux iPhone passent en manuel.
- Les anomalies deviennent des tickets ciblés, pas des refontes.

## Phase F5 — Réduction Objective-C Progressive

Objectif : réduire Objective-C au strict scope utile sans casser le projet.

Plan opérationnel détaillé : `.vscode/plans/F5-objective-c-reduction.md`.

Règles :

1. Une suppression doit avoir une preuve statique et une preuve runtime.
2. Une classe de traitement peut rester Objective-C si elle est stable et risquée à porter.
3. Une UI Objective-C encore visible doit être portée ou explicitement acceptée comme exception temporaire.
4. Les wrappers doivent devenir plus petits avant que les fichiers legacy soient supprimés.

Ordre conseillé :

1. Isoler les traitements utilisés derrière protocoles Swift quand cela réduit le couplage.
2. Retirer les routes SwiftUI vers wrappers UIKit si elles existent encore.
3. Quarantiner les controllers legacy non visibles.
4. Supprimer seulement les fichiers prouvés morts, en petits commits dédiés.

Lots de resserrage avant suppression :

| Lot | Cible | Pourquoi | Priorité |
|---|---|---|---|
| W1 | `BlackList` | Fait : façade Swift unique pour BL/WL | P0 |
| W2 | `MPStorage` | Fait : bookmarks post-level centralisés dans `ObjCMPStorageBridge` | P0 |
| W4 | `MultisManager` session/compte | Fait côté code : identité Swift pour les vues ; validation manuelle restante | P0 |
| W5 | `SmileyCache` | Fait : favoris smileys via `ReplySmileyCacheBridge` unique | P1 |
| W3 | `MessagesTableViewController` worker | Fait côté Swift : runtime/selectors centralisés, extraction non-UI future | P1 |

## Backlog Actuel

| ID | Tâche | Priorité |
|---|---|---|
| B01 | Valider sur simulateur/device la classification Objective-C/XIB | P0 |
| B02 | Partiel : tests session + build OK ; startup/background runtime à valider | P0 |
| B03 | Fait : W1 créer façade Swift unique `BlackList` / BL-WL | P0 |
| B04 | Fait : W2 étendre façade `MPStorage` pour bookmarks post-level | P0 |
| B05 | Partiel : W4 automatisé OK ; login/logout/switch manuel restant | P0 |
| B06 | Décision et éventuel portage filtres rapides forum | P1 |
| B07 | Décision Aide/Infos/Feedback/Pay | P1 |
| B08 | Décision thème avancé legacy | P1 |
| B09 | Fait : W5 unifier façade `SmileyCache` | P1 |
| B10 | Fait : W3 documenter contrat `MessagesTableViewController` worker | P1 |
| B11 | Passe cohérence UI Liquid Glass | P2 |
| B12 | Étude iPad | P2 |

## Validation B02/B05

Automatisé :

1. `ObjCAccountSessionServiceTests` OK sur simulateur iPhone 17.
2. Build `HFRswift` Debug iOS Simulator OK.
3. Tests wrappers remis à jour sur le contrat `ForumTopicsLoadResult`.

Manuel restant :

1. Fresh install puis lancement avec et sans compte.
2. Ajout de compte, vérification cookies et compte courant.
3. Switch de compte et persistance après relance.
4. Suppression/logout d’un compte et fallback du compte actif.
5. Passage background/foreground sur messages, AQ et réponse.
6. Vérification qu’aucun fallback UIKit compte/session visible ne réapparaît.

## Non-Objectifs

1. Réécrire le parsing forum en Swift maintenant.
2. Supprimer massivement Objective-C.
3. Recréer l’intégralité des tests UI.
4. Porter les flux offline topic dépréciés.
5. Garder une parité pixel-perfect avec UIKit si la SwiftUI récente offre une meilleure UX.
