# Tableau des leçons

Auto-relecture contre ce tableau **avant chaque PR et chaque correctif de revue** (skill `/lessons-check`). Après
chaque cycle de revue, comparer les constats au tableau ([REVIEW-ROUNDS](REVIEW-ROUNDS.md) étape 9) : déjà listé =
l'auto-relecture l'a manqué, resserrer cette étape ; nouveau genre = nouvelle ligne, proposée au cadre par PR si elle
vaut ailleurs, sinon gardée dans les leçons du projet.

**Incrémenter** (skill `/lesson-propose`) : une leçon valable au-delà d'un projet remonte au cadre par une **issue
« Leçon »** sur `francoisgn/agentic-harness` (formulaire dédié, label `leçon`) : portée, leçon en une phrase
vérifiable, source à un SHA, contre-exemple. Le steward du cadre la fusionne dans ce tableau par PR (numéro suivant,
MINEUR au CHANGELOG) ; les projets la reçoivent à la synchro suivante.

**Portée** : `général` (tout projet) · `swift` · `ios` · `linux-cloud` (sessions dans un conteneur Linux) · `ci` · `docs`.
Un projet sans Swift ignore `swift` et `ios`. Les leçons de domaine (protocole d'un site, règle financière) restent dans
le projet.

**Sources** : `HFR n` = ligne n de `docs/agents/LESSONS.md` de HFRnow (branche `dev-swift`) ; `HFR §11 <date>` =
journal d'`AGENTS.md` §11 de HFRnow ; `terrain` = pratique éprouvée sur un autre projet, non publié (la leçon est
reformulée pour valoir partout, sans détail de ce projet).
Les numéros `L..` sont stables : une leçon devenue fausse est barrée, jamais renumérotée.

| # | Portée | Leçon | Source |
|---|---|---|---|
| L01 | général | Un test **échoue sans le changement** et ne peut pas passer trivialement : le prouver (annuler le cœur du correctif, voir rouge, restaurer). Il passe par le vrai point d'entrée, pas seulement par un helper. Un run filtré doit annoncer des tests réellement exécutés | HFR 2 ; HFR REVIEW-ROUNDS 4 |
| L02 | général | Un test vérifie le résultat de **sa propre action**, pas la dernière notification ou le dernier état (une autre action peut l'avoir remplacé) | HFR 13 |
| L03 | général | Un correctif d'appariement ou d'ordre couvre **les deux ordres et toutes les combinaisons**, pas seulement le cas signalé | HFR 9 |
| L04 | général | Une garde couvre **tous les chemins qui agissent**, pas seulement le plus visible | HFR 11 |
| L05 | général | **Mesurer** une affirmation de performance avant de la rapporter ou de la corriger ; mesurer plutôt que supposer (comportement externe, résultats de tests) | HFR 10 ; HFR AGENTS §3.9 |
| L06 | général | Chaque chemin d'échec remonte quelque chose d'**actionnable** ; un résultat asynchrone rafraîchit l'interface | HFR 5 |
| L07 | docs | Un `\|` dans un code span d'un tableau Markdown s'échappe, sinon la ligne casse. markdownlint ne garde que les règles qui attrapent une vraie casse (MD051 ancres, MD056 colonnes) | HFR 20 ; HFR `.markdownlint-cli2.jsonc` |
| L08 | docs | Docs, description de PR et specs disent **exactement** ce que fait le code ; pas de doc pour un comportement non livré | HFR 3 |
| L09 | docs | Les docs de suivi (plan, spec, ADR, réglementation sourcée) se mettent à jour **dans le même commit** que le changement | HFR 12 ; terrain |
| L10 | docs | Un fichier, un rôle : pas de nouveau document quand un existant a ce rôle ; un fichier ponctuel (runbook, rapport) est supprimé une fois son résultat consigné dans l'ADR ou le fichier qui porte le sujet | HFR AGENTS §2 |
| L11 | général | Toute API publique ajoutée ou touchée a un commentaire de doc d'une ligne ; un commentaire dit **pourquoi**, pas quoi | HFR 1 ; HFR AGENTS §4 |
| L12 | général | Pas de copie inutile de grosses données ; dire le comportement aux limites (mémoire, disque, très gros volumes) | HFR 4 |
| L13 | général | Les identifiants sont uniques et hors des espaces de noms des autres | HFR 6 |
| L14 | général | Tous les points d'entrée d'une fonction restent cohérents (menu, bouton, geste, raccourci, lien profond) | HFR 7 |
| L15 | général | Aucune erreur ignorée sur fichiers, trousseau, permissions ; les courses sont envisagées | HFR 8 |
| L16 | général | Après un merge avec conflits, relire **tout** le fichier conflictuel contre ses deux parents | HFR 14 |
| L17 | général | Une modification scriptée se vérifie en lisant le diff ligne à ligne, pas seulement par le contrôle du script | HFR 15 |
| L18 | général | Relire la tête de branche (SHA) et l'état des contrôles **juste avant** de publier un statut | HFR 16 ; HFR ORCHESTRATION |
| L19 | général | Avant de dire « déjà corrigé », « fait » ou « doublon » : vérifier la branche d'intégration actuelle et les derniers commentaires ; un signalement peut être plus vieux que le dernier merge | HFR 46 |
| L20 | général | À chaque point d'étape, relire revues, CI et **tous** les fils ouverts de ses PR : les bots postent tard | HFR 47 |
| L21 | général | Un fait sur un système externe (URL, champ, règle, API, protocole) cite sa source (lien officiel, `fichier:ligne` à un commit nommé, capture). Rien de deviné : s'arrêter et dire quoi aller chercher | HFR 17 ; HFR AGENTS §3.1 ; terrain |
| L22 | général | Données de test et journaux sans donnée réelle (nom, cookie, jeton, contenu privé) ; une donnée réelle commitée est un incident de sécurité | HFR 18 ; HFR AGENTS §3.5 |
| L23 | général | Une anonymisation se vérifie par un contrôle **indépendant** (autres motifs, autre analyseur, recherche des noms relevés dans les données brutes), avant de pousser ; la liste qui a produit la sortie ne s'en porte jamais garante. Un test isole une position à la fois | HFR 33 ; HFR §11 2026-10-26 |
| L24 | général | Une règle de caviardage décide par **position** (champ, cellule), jamais par l'allure du contenu ; une forme dérivée (slug) suit la transformation réelle de la source, mesurée sur de vraies paires | HFR 39 |
| L25 | général | Un motif sur des valeurs entre guillemets tient compte du type de guillemet : un `'` dans une valeur entre `"` arrêtait deux regex « indépendantes » au même endroit | HFR 34 |
| L26 | général | Avant de commencer un lot, vérifier que **toutes** ses entrées existent (données capturées **et** sortie de référence) ; les unes sans les autres ne suffisent pas | HFR 35 |
| L27 | général | Un état non capturé est un manque à renvoyer à qui capture, jamais un prétexte pour fabriquer la donnée à la main | HFR 36 |
| L28 | général | Lire la vraie donnée avant de concevoir les états : la checklist supposait des résultats, la page montrait un formulaire | HFR 38 |
| L29 | général | Un oracle calculé avec un seul jeu de réglages cache ce que ce réglage change : écarter ces cas explicitement **et** les compter des deux côtés, jamais en silence | HFR 51 |
| L30 | général | Des faits que la référence ne calculait pas : tester en différentiel le sous-ensemble dérivable, vérifier le reste sur des captures, sans attendre un nouvel exporteur | HFR 52 |
| L31 | général | Une URL extraite d'une réponse puis suivie avec une session authentifiée se vérifie en schéma **et** hôte (`http://hôte:80/` passe un contrôle d'hôte seul) ; seuls les liens de sa propre origine se suivent avec la session | HFR 37, 43 |
| L32 | général | « Introuvable » reste distinct de « illisible » : une page dont toutes les lignes échouent ou un mur de connexion lève une erreur au lieu de rendre une liste vide | HFR 44 |
| L33 | général | Un contrôle de nom d'en-tête (code et tests) coupe les espaces et met en minuscules, sinon `" Cookie"` passe | HFR 32 |
| L34 | général | Les nombres JSON d'autres clients se gardent tels qu'écrits (lexème ou Decimal), jamais via `Double` : une donnée préservée fait l'aller-retour à l'octet près | HFR 31 |
| L35 | général | Une valeur lue dans une réponse et réécrite dans un état partagé (jeton, cookie) est un compare-and-set contre ce que l'état tenait au départ de la requête, en un seul tour d'acteur | HFR 55 |
| L36 | général | Un test de risque réseau (hôte, cookie) échoue sans aucun accès réseau : il affirme la politique elle-même, jamais un refus local que la mutation testée retire (une mutation a envoyé une vraie requête) | HFR 56 |
| L37 | général | Une marque locale posée par l'utilisateur (lu, supprimé, masqué) n'est effacée que par un chargement **parti après** elle ; un rechargement déjà en vol ramène l'état d'avant | HFR 57 |
| L38 | général | Le travail de fond (autosave, sondage, sauvegarde hors ligne) passe par le chemin de code normal et ne tombe jamais au milieu d'une interaction | HFR 48 |
| L39 | ios | Le code qui tourne à chaque rendu (`body` SwiftUI, gestionnaires de défilement ou de changement) saute le travail par élément sur une entrée vide ; la vue montre quand même son état vide, de chargement ou d'erreur | HFR 49 |
| L40 | général | Une suppression de fichiers ne suit jamais un lien symbolique : valider chaque composant du chemin depuis la racine | HFR 29 |
| L41 | docs | Des lots parallèles qui ajoutent à la **même section** d'un doc partagé se conflictent à chaque merge : créer d'abord le titre commun, chaque lot n'ajoute que sa sous-section, l'orchestrateur garde toutes les sous-sections | HFR 42 |
| L42 | général | Des PR empilées qui partagent un fichier généré se mergent dans l'ordre, en merge commit, jamais rebasées ni forcées | HFR 40 |
| L43 | général | Avant un changement structurel : `git fetch --all --prune`, lister les branches non mergées dans la branche d'intégration et décider du sort de chacune (deux sessions avaient écrit chacune un ADR 0010) | HFR §11 2026-10-27 |
| L44 | général | Une CI verte ne suffit pas pour merger : une PR « UI d'abord » compilait, mais perdait des réglages et cassait l'existant. Exiger spec, tests, base à jour et revue par un autre que l'auteur | HFR 45 ; HFR ADR 0011 |
| L45 | général | Cycle de revue de bots sur une PR riche en docs : grouper les correctifs, répondre à **chaque** fil et le résoudre, merger quand les contrôles requis sont verts et que la politique de merge le permet | HFR 41 |
| L46 | général | Un bot de revue peut sauter une revue ou s'arrêter sur une branche : vérifier qu'il a relu la nouvelle tête. Depuis une session cloud, les `@mentions` postées sont altérées : l'opérateur poste `@coderabbitai review`, `@dependabot rebase` | HFR REVIEW-ROUNDS ; HFR §11 2026-10-24 |
| L47 | ci | Un contrôle qui échoue en quelques secondes sans journal (jeton absent, service indisponible, runner jamais acquis) est de l'infrastructure, pas « CI rouge ». « Instable » n'est pas une cause : une relance au plus, puis enquête | HFR REVIEW-ROUNDS ; HFR EXTERNAL-AGENTS §10 |
| L48 | ci | Une minute macOS compte pour 10, chaque job est arrondi à la minute : pushes fréquents sur un brouillon où rien de coûteux ne tourne, CI complète au passage « Ready » ou sur label, un commit par cycle de revue, jobs Linux regroupés, build macOS seulement si l'app change et après le job Linux vert | terrain ; HFR §11 2026-11-05 (#477) |
| L49 | ci | Une détection de changements en échec lance quand même les jobs qu'elle conditionne : un détecteur cassé ne doit jamais laisser passer une PR | terrain ; HFR `ci.yml` |
| L50 | ci | `issues`, `schedule`, `workflow_dispatch`, `pull_request_target`, formulaires d'issue et config Dependabot ne fonctionnent que depuis la **branche par défaut** : un workflow posé sur une autre branche est inerte | HFR §11 2026-10-26 ; HFR ADR 0010 |
| L51 | ci | Une image de runner en préversion (ex. `xcode-27`) n'existe que par son label : la déclarer à actionlint (`.github/actionlint.yaml`) et choisir le simulateur dynamiquement (un runtime peut refuser un modèle d'appareil) | HFR §11 2026-10-24, 2026-10-26 ; terrain |
| L52 | ci | Sur un dépôt privé, CodeQL, le secret scanning et la Dependency Review exigent GitHub Advanced Security : les remplacer par Semgrep, Trivy, gitleaks, zizmor, actionlint. Un dépôt public ne consomme aucune minute | terrain |
| L53 | ci | Actions épinglées par SHA complet (tag en commentaire), `permissions` minimales, `persist-credentials: false`, jamais de `pull_request_target` qui extrait le code de la PR, aucun secret exposé aux forks | HFR ADR 0005 ; HFR `.coderabbit.yaml` |
| L54 | ci | Les hooks pre-commit ne reformatent jamais les données de test (octet près) ; ShellCheck couvre tous les scripts, un constat se corrige ou se tait en ligne avec sa raison | HFR CONTRIBUTING §4 |
| L55 | linux-cloud | Les journaux de jobs CI se lisent depuis une session cloud par l'outil MCP GitHub `get_job_logs` (`gh api …/logs` est bloqué : autre hôte) ; les annotations restent le signal le plus rapide | HFR §11 2026-10-25 |
| L56 | linux-cloud | Une session cloud ne change pas les réglages du dépôt (403) : les réglages vivent dans un fichier versionné (`.github/repo-settings.json`), modifié par PR et appliqué au merge par la CI avec un jeton d'administration (ADOPTION §Réglages du dépôt) | HFR §11 2026-10-24 |
| L57 | linux-cloud | Les apps GitHub (Claude, CodeRabbit) d'un dépôt personnel ne s'installent que par son propriétaire, quels que soient les droits du collaborateur | HFR §11 2026-10-26 |
| L58 | linux-cloud | L'app (SwiftUI, Charts, StoreKit…) ne compile pas sous Linux : relire son code avec une rigueur de compilateur (types, `@MainActor`, `Sendable` en mode complet, exhaustivité des `switch`, API réelles de la version d'OS) ; seul le Mac ou la CI macOS tranche | terrain |
| L59 | linux-cloud | Installer **la même version** de la chaîne d'outils que la CI Linux (script, signature vérifiée) et lancer les tests du moteur avant tout push qui le touche | terrain ; HFR `cloud-setup.sh` |
| L60 | linux-cloud | Le linter de la CI n'est pas forcément dans le conteneur : l'installer (binaire Linux à la version de la CI, empreinte vérifiée) plutôt que dépenser un tour de CI ; sinon vérifier à la main ses règles bloquantes (longueur de ligne, complexité, longueur de type, identifiants) | HFR 21, 27 |
| L61 | linux-cloud | Après des modifications tardives, vérifier `git status` sur les fichiers **suivis**, pas seulement les non suivis, avant de pousser | HFR 23 |
| L62 | swift | Sous Linux, `Date.description` plante sur une date non finie : aucun test ne doit en imprimer | HFR 22 |
| L63 | swift | swift-corelibs-foundation ignore `timeoutInterval` et les délégués de redirection par tâche, `URLProtocol` ne sait pas rediriger : imposer ses délais soi-même, tester les redirections contre un serveur local | HFR 24 |
| L64 | swift | `URL.cachesDirectory` n'existe pas sous Linux et `FileManager.replaceItemAt` y échoue : chemins explicites et `rename(2)` pour une écriture atomique | HFR 28 |
| L65 | swift | Sous Linux, `URLSession` reporte sur une redirection suivie les cookies qu'il a posés, quel que soit le nouvel hôte : refuser les redirections hors des hôtes permis | HFR 30 |
| L66 | swift | Un serveur de test (socket) se ferme dans le thread qui le possède, sinon son descripteur peut être réutilisé par un autre | HFR 25 |
| L67 | swift | Un test Swift Testing qui annule sa propre tâche est « annulé », ni réussi ni échoué : piloter l'annulation par une `Task` enfant dont on attend la valeur | HFR 50 |
| L68 | swift | Un `@Test(arguments:)` de littéraux joints par `+` peut dépasser la limite du vérificateur de types et faire échouer toute la cible : écrire les littéraux en entier | HFR 53 |
| L69 | swift | Les closures et blocs `do` à throws typés infèrent `any Error` sans annotation (`() async throws(E) -> T in`, `do throws(E)`) | HFR §11 2026-10-27 (LOT-082) |
| L70 | swift | Une fonction statique dont un argument par défaut lit une valeur `@MainActor` devient `@MainActor` : garder la règle pure `nonisolated` et testable, la lecture dans une surcharge fine | HFR §11 2026-10-28 (LOT-119) |
| L71 | swift | Les API récursives sur arbre plantent sur une imbrication profonde (pile de 512 Ko) : parcourir avec une pile explicite, construire les arbres profonds de bas en haut | HFR §11 2026-10-27, 2026-10-28 (LOT-032, LOT-034) |
| L72 | ios | Un test d'app qui échoue fait lancer `simctl diagnose` par `xcodebuild test` pendant jusqu'à 10 min ; filtrer avec le nom complet Swift Testing (`Suite/test()`, sans `()` rien ne tourne) et vérifier que des tests ont tourné | HFR 54 |
| L73 | ios | `confirmationDialog` efface son état de présentation avant l'action : passer à l'action l'élément montré. Un gestionnaire qui capture fortement son modèle le fait fuir : capture faible | HFR §11 2026-11-05 (LOT-087) |
| L74 | ios | Connaître la stratégie du fichier de projet : groupes synchronisés (ajouter un fichier sans toucher au pbxproj) ou XcodeGen **et** pbxproj versionnés (tout ajout, renommage, suppression, réglage se reporte dans les deux) | HFR ADR 0012 ; terrain |
| L75 | ios | Agents et CI compilent sans signature (`CODE_SIGNING_ALLOWED=NO`), jamais `-allowProvisioningUpdates` ; un build signé sur appareil demande le compte d'équipe dans l'Xcode du mainteneur | HFR §11 2026-10-27 (LOT-080) |
| L76 | ios | Mise en page par size classes, jamais par idiom ni `UIScreen` ; cibles de 44 pt, labels VoiceOver, texte dynamique | terrain |
| L77 | général | Une affirmation de sécurité se teste sur le composant réel (vue web hébergée, client réseau), pas seulement sur la chaîne produite | HFR §11 2026-10-27 (LOT-083) |
| L78 | général | Lire les données capturées en **octets** : une lecture en mode texte change les CRLF en LF | HFR §11 2026-10-27 (LOT-036) |
| L79 | général | Une écriture n'est un succès qu'avec la confirmation propre du serveur ; une écriture dont la requête a pu partir est « non confirmée », jamais rejouée | HFR §11 2026-10-27, 2026-10-28 (LOT-037, LOT-048, #314) |
| L80 | général | Persistance : une sauvegarde écrite par une version publiée reste lisible par toutes les suivantes (champ nouveau optionnel ou par défaut, décodage tolérant, migration à la lecture) | terrain |
| L81 | général | Juste avant d'ouvrir une PR, chercher les PR ouvertes qui touchent les mêmes fichiers ou le même sujet : se coordonner plutôt que découvrir le conflit au merge | HFR AGENTS §8 |
| L82 | général | Une affirmation « X est appelé au lancement » se vérifie en cherchant l'appelant (`grep`) : la fonction n'avait aucun appelant | HFR §11 2026-10-28 (LOT-119) |
