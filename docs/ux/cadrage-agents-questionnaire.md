# Cadrage du travail par agents : questionnaire UX et prototype de rendu natif

Date : 6 novembre 2026, mis à jour le 7 novembre. Ce document découpe la préparation du questionnaire (`docs/ux/plan-preparation-questionnaire.md`) en lots confiables à des agents, avec le modèle adapté à chaque lot et le moyen de suivre l'avancement. Rien n'est lancé.

## 1. Principes

**Conventions du dépôt, reprises telles quelles** (`AGENTS.md` et `docs/agents/ORCHESTRATION.md` sur `dev-swift`) :
- une issue par lot, qui commence par `### Summary`, avec un label par axe ;
- un claim avant d'écrire du code ;
- une PR par lot qui cite `Closes #N` et `Claim:` ;
- une revue adversariale par un autre modèle que l'auteur.

**Routage des modèles** (`AGENTS.md` §6) :

| Modèle | Usage |
|---|---|
| Fable 5.1 | Décisions structurantes, ADR sur problèmes durs |
| Opus 5.5 | Conception, flux sensibles, revue du travail de Sonnet |
| Sonnet 5.5 | Réalisation de lots bien spécifiés |
| Haiku 5.5 | Travail mécanique |

Règle : le relecteur n'est jamais le modèle auteur. Opus est relu par Fable ; Sonnet et Haiku par Opus ; Fable par Opus.

**Hôte** :
- `host: mac` pour tout ce qui demande Xcode, le simulateur ou le forum en direct ;
- le cloud pour le reste.

**Ce qui reste au PO** : validation des textes et des visuels, décisions de la section 6, et toute action publique (topic HFR, TestFlight, mise en ligne sur le VPS).

## 2. Vue d'ensemble

Quatre pistes, douze lots. **Mise à jour du 7 novembre 2026** : la piste A, prototype de rendu natif, est **différée** ; le PO garde la WebView et en fera une décision technique ultérieure. Les sept lots du questionnaire, UX-05 à UX-11, ont chacun une issue, suivies par une issue parapluie.

| Lot | Piste | Objet | Auteur | Relecteur | Hôte | Dépend de |
|---|---|---|---|---|---|---|
| UX-01 | Prototype (différé) | Capture d'un sujet avec citations sur trois niveaux | Sonnet | Haiku pour l'anonymisation, Opus | mac | — |
| UX-02 | Prototype (différé) | Arbre de contenu produit par le normaliseur | **Fable** | Opus | cloud | — ; UX-01 pour le cas des citations profondes |
| UX-03a | Prototype (différé) | Rendu natif des trois cas et parité | Opus | **Fable** | mac | UX-02 |
| UX-03b | Prototype (différé) | Sélection de texte, préchargement, mesures | Opus | **Fable** | mac | UX-02 |
| UX-04 | Prototype (différé) | Matrice des bénéfices, verdict, projet d'amendement d'ADR | **Fable** | Opus | cloud | UX-03a, UX-03b |
| UX-05 | Contenu | Rédaction finale du questionnaire | Sonnet | Opus | cloud | — |
| UX-06 | Contenu | Mention sur les données personnelles | Opus | Fable | cloud | Décision 3 (faite) |
| UX-07 | Visuels | Captures réelles et vidéos Duo | Sonnet | Opus | mac | — |
| UX-08 | Visuels | Maquettes des scénarios et cartes de la barre latérale | Opus | Fable | mac | UX-07 |
| UX-09 | Formulaire | Spécification technique | Opus | Fable | cloud | — ; le sous-domaine sera choisi plus tard |
| UX-10 | Formulaire | Réalisation front et back | Sonnet | Opus | cloud | UX-09, UX-05, UX-08 |
| UX-11 | Formulaire | Revue sécurité et vie privée, puis mise en ligne restreinte | Fable pour la revue, PO pour la mise en ligne | — | cloud et VPS | UX-10, UX-06 |

**Chemin critique** : UX-07, puis UX-08, puis UX-10 et le test. UX-05, UX-06 et UX-09 avancent en parallèle.

## 3. Briefs par lot

Chaque brief est autonome : il peut être collé tel quel dans une session.

Toute session commence par :
1. lire `AGENTS.md`, `docs/agents/ORCHESTRATION.md` et `docs/agents/LESSONS.md` sur `dev-swift` ;
2. lire le présent document et `docs/ux/tri-m5-decisions.md` sur `dev-swift`, dans `docs/ux/` ;
3. claimer l'issue du lot.

Toute session s'arrête et rend compte si une consigne contredit le plan.

### Piste A — Prototype de rendu natif (différé)

**Différé le 7 novembre 2026** : le PO garde la WebView pour le moment. Les briefs ci-dessous restent prêts pour la décision technique ultérieure ; ils n'ont pas d'issue.

Objectif commun : savoir si le lecteur de SwiftHFR peut afficher un sujet sans WebView, et ce que le rendu natif apporte réellement par rapport au lecteur WebView actuel.

**Relecture par Fable, 6 novembre 2026, vérifiée dans le code.** Plusieurs bénéfices attribués au rendu natif existent déjà dans le lecteur WebView de SwiftHFR, sur `dev-swift` :
- messages de la liste noire repliables (`TopicHTMLBuilder.swift`, balise `details`) ;
- citations repliables (`reader.css`, `quote-blocked`) ;
- séparateur des nouveaux messages (`TopicHTMLBuilder.swift`, `separator1`) ;
- taille de texte dynamique iOS (`reader.css`, `-apple-system-body` et `--text-scale`) ;
- restauration de position à l'atterrissage (`reader.js`).

Le changement de page instantané relève du préchargement, pas du moteur : aujourd'hui le swipe charge la page puis l'affiche (`TopicReaderModel.swift`, `swipe`). Une WebView préchargée hors écran ferait aussi bien.

Ce qui est réellement réservé au natif :
- un swipe entre pages qui suit le doigt ;
- une position restaurée à la ligne près, y compris après une rotation ;
- une sélection de texte sans conflit avec le swipe de page.

Le prototype mesure donc ces trois points et la parité, pas les bénéfices déjà acquis.

Contexte commun :
- **Où construire l'arbre de contenu.** Dans `HFRParsing`, comme second produit du normaliseur qui parcourt déjà l'arbre HTML (`MessageContentNormalizer.swift`), à côté du champ `html` conservé. L'app ne peut pas analyser le HTML elle-même : l'ADR 0002 réserve SwiftSoup à `HFRParsing`.
- **Conséquences de ce choix.** L'ADR 0006 est amendé et non remplacé. Les tests différentiels sur `html` restent l'oracle. Un test aller-retour, arbre vers HTML égal au `html` normalisé, donne un second oracle gratuit.
- **Aperçu avant envoi.** Le même arbre sert sans travail supplémentaire, car l'aperçu passe déjà par le normaliseur (ADR 0014 : rendu BBCode vers HTML, puis normalisation).
- **Redface 2** (Android, GPL-3.0) rend nativement à partir d'un arbre sémantique commun au lecteur et à l'aperçu. Source : son ADR-011. Licence : idées seulement, aucune ligne de code ni fixture reprise (`docs/research/redface2-comparison.md` §5.1). À inscrire dans l'ADR.

Les trois cas de test :

| Cas | Contenu | Captures |
|---|---|---|
| 1 | Citations imbriquées avec smileys standards et personnels, couleurs, souligné, liste à puces | `R20-topic-p1-anon`, `R22a-topic-middle-page-anon`, `R28-topic-images-videos-anon` et `R32a-topic-poll-anon` pour deux niveaux |
| 2 | Spoilers, images et vidéos ; citation d'un extrait sélectionné | `R27-topic-spoilers-anon`, `R28-topic-images-videos-anon` |
| 3 | Bloc de code et bloc à chasse fixe | `R27b-topic-code-blocks-anon`, qui contient deux blocs de code et un bloc à chasse fixe |

HFR n'a pas de balise de tableau. Les seuls tableaux du HTML sont la structure des citations, spoilers et blocs de code : le tableau est donc retiré des cas. Aucune capture n'a de citation imbriquée au-delà de deux niveaux : c'est l'objet d'UX-01.

Comportements du lecteur actuel à faire survivre, que le rendu natif doit couvrir ou marquer « non fait » :
- **Structure des messages** : reprise du message précédent, messages supprimés, signatures, classes de visibilité des citations (`VisibilityPolicy.swift`).
- **Images** : politique de chargement sans cookie, avec espaces réservés, consentement au toucher et 15 Mo maximum (`ReaderImageFetcher.swift`). Galerie d'images.
- **Vidéos** : lecture au toucher.
- **Liens** : routage des liens HFR dans l'app (`ReaderLinkAction.swift`).
- **Actions** : bouton de menu par message.
- **Accessibilité et thèmes** : libellés d'accessibilité, thèmes.
- **Position** : maintien de la position à l'atterrissage pendant le chargement des images (`reader.js`).
- **Pages longues** : R20 pèse 138 Ko et compte 205 images.

#### UX-01 — Capture d'un sujet avec citations profondes

- **Summary** : comme équipe du prototype, nous voulons une page de sujet réelle avec des citations sur trois niveaux ou plus, pour tester le cas le plus difficile du rendu natif.
- **Faire** : trouver un sujet public qui contient des citations sur au moins trois niveaux, idéalement avec une liste à puces, des couleurs et du souligné. Le capturer avec `tooling/fixtures/capture.py`, puis l'anonymiser selon `docs/FIXTURES.md`.
- **Ne pas faire** : aucune page construite à la main ; aucune requête authentifiée qui déplacerait un drapeau.
- **Livrable** : la capture et sa fiche.
- **Durée maximale** : une demi-journée.
- **Modèle** : Sonnet sur le Mac ; Haiku pour vérifier l'anonymisation ; relecture Opus.
- **Labels** : `type: chore`, `area: parsing`, `host: mac`, `difficulty: easy`, `priority: high`.

#### UX-02 — Arbre de contenu dans HFRParsing

- **Summary** : comme lecteur natif, nous voulons un arbre de contenu typé produit par le normaliseur à côté du HTML, pour afficher un message sans WebView.
- **Faire** :
  - proposer les types de l'arbre : blocs et éléments en ligne, au minimum texte stylé, lien, smiley, image, vidéo, citation récursive avec auteur et numéro de message, spoiler, code, chasse fixe, liste, saut de ligne ;
  - produire l'arbre comme second produit du normaliseur, sans retirer `html` ;
  - lister ce que l'arbre ne sait pas représenter et comment il se dégrade : texte brut, jamais de perte silencieuse ;
  - note d'une page sur l'amendement de l'ADR 0006 et le lien avec l'ADR 0014.
- **Contraintes** :
  - code testable sous Linux ;
  - aucun changement au contrat public de `MessageContent` sans le signaler ;
  - prototype sur une branche `spike/`, sans PR vers `dev-swift` tant que le verdict n'est pas rendu.
- **Critères de réussite** :
  - 100 % des messages de R20, R27, R27b, R28 et de la capture d'UX-01 convertis ;
  - aller-retour de l'arbre vers le HTML égal au `html` normalisé ;
  - aucune perte silencieuse.
- **Livrable** : branche `spike/native-reader-ast`, tests verts sous Linux, note de conception.
- **Durée maximale** : deux jours.
- **Modèle** : Fable ; relecture Opus.
- **Labels** : `type: chore`, `area: parsing`, `difficulty: difficult`, `priority: high`.

#### UX-03a — Rendu natif et parité

- **Summary** : comme équipe produit, nous voulons voir les trois cas rendus nativement à côté du lecteur WebView, pour juger l'écart.
- **Faire** :
  - écran de lecture prototype en SwiftUI, avec TextKit 2 là où SwiftUI ne suffit pas, qui rend une page complète à partir de l'arbre d'UX-02 ;
  - thèmes, taille de texte dynamique, liste noire, reprise du message précédent, images selon la politique de chargement ;
  - la liste des comportements à faire survivre, chacun coché « rendu », « ébauche » ou « absent ».
- **Critères de réussite** : au plus trois écarts visibles non triviaux par cas.
- **Livrable** : branche `spike/native-reader-render`, captures natif et WebView côte à côte.
- **Durée maximale** : deux jours.
- **Modèle** : Opus sur le Mac ; relecture Fable.
- **Labels** : `type: chore`, `area: app`, `host: mac`, `difficulty: difficult`, `priority: high`.

#### UX-03b — Sélection de texte, préchargement et mesures

Lot séparé parce que la sélection est le risque principal : il ne doit pas attendre les thèmes et la taille de texte.

- **Summary** : comme posteur, je veux sélectionner un passage et le citer comme aujourd'hui, et comme lecteur je veux des pages qui s'enchaînent sans attente.
- **Faire** :
  - **« Citer extrait »** : le lecteur actuel envoie le texte brut de la sélection et le message porteur, puis le moteur réduit le texte prérempli par HFR (`reader.js`, `QuoteSelectionFormatter`). Le natif doit fournir la chaîne sélectionnée, l'attribution à un seul message et un menu d'édition personnalisé (`QuoteMenuWebView.swift`).
  - Tester une sélection qui traverse du gras et un smiley : le smiley ne doit pas devenir un caractère de remplacement, il faut retrouver son code.
  - Tester une sélection qui déborde sur deux messages.
  - Tester qu'il n'y a aucun conflit entre la sélection et le swipe de page.
  - Préchargement de la page suivante et swipe qui suit le doigt.
  - Mesures sur un iPhone de 3 à 4 Go simulé et sur un iPad, comparées au lecteur WebView sur les mêmes pages.
- **Critères de réussite** :

| Mesure | Seuil |
|---|---|
| Sélection traversant gras et smiley | Texte cité attendu dans les trois cas |
| Premier affichage de R20 | Au plus 50 % du temps de la WebView |
| Défilement | 60 images par seconde, ou au moins 95 % des images sans saccade |
| Mémoire sur R28 | Au plus 1,5 fois celle de la WebView |
| Position après rotation | Restaurée à une ligne près |

- **Livrable** : tableau de mesures et vidéo de la sélection.
- **Durée maximale** : un jour et demi.
- **Modèle** : Opus sur le Mac ; relecture Fable.
- **Labels** : `type: chore`, `area: app`, `host: mac`, `difficulty: difficult`, `priority: high`.

#### UX-04 — Verdict et projet d'amendement de l'ADR 0006

- **Summary** : comme PO, je veux un verdict fondé sur des mesures et le coût réel du passage en production.
- **Faire** :
  - matrice par bénéfice : déjà là, possible en WebView, natif seulement ;
  - verdict parmi trois : faisable, faisable avec réserves nommées, ou non faisable à ce stade, justifié par les mesures et non par l'intention ;
  - estimation des lots de parité après le prototype, de l'ordre de 8 à 12 selon la relecture ;
  - risques à inscrire dans l'ADR : dépendance à UIKit et TextKit 2, mémoire des images décodées, saccades de défilement avec des hauteurs variables, licence ;
  - projet d'amendement de l'ADR 0006 si le verdict est positif.
- **Livrable** : le verdict dans l'issue, le projet d'ADR en PR brouillon.
- **Durée maximale** : un jour.
- **Modèle** : Fable ; relecture Opus. La décision finale revient au PO.
- **Labels** : `type: docs`, `area: docs`, `difficulty: difficult`, `priority: high`.

Durée totale de la piste : environ sept jours agent. Chemin : UX-02, UX-03a, UX-03b, UX-04 ; UX-01 en parallèle.

### Piste B — Contenu du questionnaire

#### UX-05 — Rédaction finale

- **Summary** : comme utilisateur de l'app, je veux des questions claires, courtes et honnêtes, pour donner un avis utile en moins de sept minutes.
- **Entrée** : `docs/ux/tri-m5-decisions.md` §4.
- **Faire** :
  - libellé définitif de chaque question et réponse ;
  - texte des huit cartes ;
  - introduction de trois lignes ;
  - message de fin ;
  - annonce pour le topic HFR et note TestFlight ;
  - chaque question rattachée à sa section du tri.
- **Règles** :
  - point de vue de l'utilisateur, aucun jargon, aucune promesse ;
  - une réponse « comme aujourd'hui » partout où c'est pertinent ;
  - aucune proposition classée Non.
- **Thème 1** : n'y présenter que les améliorations possibles avec la WebView (`docs/ux/tri-m5-decisions.md` §4.3).
- **Livrable** : `docs/ux/questionnaire/questions.md`.
- **Modèle** : Sonnet ; relecture Opus ; validation PO.
- **Labels** : `type: docs`, `area: docs`, `difficulty: easy`, `priority: high`.

#### UX-06 — Mention sur les données personnelles

- **Summary** : comme répondant qui laisse son pseudo, je veux savoir ce qui est gardé, pourquoi et combien de temps, et comment le faire supprimer.
- **Faire** :
  - texte court affiché avant le champ pseudo ;
  - page détaillée : responsable, finalité, données collectées, durée de conservation, droit de suppression et contact ;
  - responsable et contact : Bruno Arene, ezzz75@gmail.com ;
  - liste de ce que le formulaire ne collecte pas : pas d'adresse IP conservée au-delà de l'anti-abus, pas de cookie tiers, pas de mesure d'audience.
- **Livrable** : `docs/ux/questionnaire/donnees.md`.
- **Modèle** : Opus ; relecture Fable ; validation PO.
- **Labels** : `type: docs`, `area: docs`, `difficulty: easy`, `priority: medium`.

### Piste C — Visuels

#### UX-07 — Captures réelles et vidéos Duo

- **Summary** : comme répondant, je veux voir l'app actuelle à côté des propositions, pour comparer sur pièce.
- **Faire** :
  - captures de l'app actuelle, version 4.0.4 sur `master` : lecture d'un sujet sur iPhone, barre latérale et disposition actuelle sur iPad, écran intérieur et extérieur du Duo ;
  - un même sujet public pour toutes les captures, pseudos masqués ;
  - vidéos de 10 secondes pour le Duo.
- **Règle** : aucune proposition classée Non visible, par exemple aucun scrubber.
- **Livrable** : `docs/ux/questionnaire/visuals/actuel/`.
- **Modèle** : Sonnet sur le Mac ; relecture Opus.
- **Labels** : `type: chore`, `area: docs`, `host: mac`, `difficulty: easy`, `priority: medium`.

#### UX-08 — Maquettes des scénarios

- **Summary** : comme répondant, je veux voir chaque scénario de façon concrète, pour choisir sans deviner.
- **Faire** :
  - thème 1 : maquette « pages améliorées », limitée aux améliorations possibles avec la WebView, et GIF « lecture continue » ;
  - thème 2 : deux dispositions nouvelles sur iPad et Duo déplié, à côté de la capture actuelle ;
  - cartes de la barre latérale pour le tri.
- **Règles** :
  - même sujet, même thème et même appareil que les captures d'UX-07 ;
  - respect des guidelines Apple et de la ligne « place au contenu » ;
  - aucune proposition classée Non visible.
- **Livrable** : `docs/ux/questionnaire/visuals/scenarios/`.
- **Modèle** : Opus ; relecture Fable ; validation PO.
- **Labels** : `type: chore`, `area: docs`, `host: mac`, `difficulty: medium`, `priority: high`.

### Piste D — Formulaire

#### UX-09 — Spécification technique

- **Summary** : comme équipe, nous voulons une spécification courte du formulaire, pour le réaliser sans aller-retour.
- **Faire** :
  - stack choisie selon ce qui tourne déjà sur le VPS ;
  - modèle de données d'une réponse ;
  - branchement du thème 2 selon le profil ;
  - formats : choix, tri de cartes, cartes de réaction, texte libre ;
  - écran de fin avec statistiques en direct ;
  - anti-doublons sans compte, limitation de débit, champ piège ;
  - export CSV et JSON ;
  - procédure de déploiement et de retrait.
- **Livrable** : `docs/ux/questionnaire/formulaire-spec.md`.
- **Modèle** : Opus ; relecture Fable.
- **Labels** : `type: docs`, `area: tooling`, `difficulty: medium`, `priority: medium`.

#### UX-10 — Réalisation

- **Summary** : comme répondant sur iPhone, je veux un formulaire rapide et agréable, pour répondre en quelques minutes.
- **Faire** : réaliser front et back selon UX-09, avec les textes d'UX-05 et UX-06 et les visuels d'UX-08. Mobile d'abord, en français, toutes les questions facultatives. Tests automatisés sur le branchement, l'enregistrement et l'export.
- **Livrable** : code sur `dev-swift`, dans `tooling/ux-survey/`, prêt à déployer.
- **Modèle** : Sonnet ; relecture Opus.
- **Labels** : `type: feature`, `area: tooling`, `difficulty: medium`, `priority: medium`.

#### UX-11 — Revue sécurité et vie privée, mise en ligne restreinte

- **Summary** : comme PO, je veux être sûr que le formulaire ne fuit aucune donnée et résiste aux abus avant de l'ouvrir.
- **Faire** :
  - revue en lecture seule du code et de la configuration : injection, stockage du pseudo, journaux, en-têtes HTTP, anti-abus, conformité avec la mention d'UX-06 ;
  - le PO déploie ensuite sur le VPS en accès restreint pour le test à cinq personnes.
- **Livrable** : rapport de revue avec ses constats ; URL de test.
- **Modèle** : Fable pour la revue, en lecture seule. Le déploiement est fait ou confirmé par le PO.
- **Labels** : `type: security`, `area: tooling`, `difficulty: medium`, `priority: high`.

## 4. Suivi de l'avancement

**Source de vérité : les issues GitHub**, comme pour le reste du projet. Créées le 7 novembre 2026 :

| Lot | Issue |
|---|---|
| Parapluie et tableau de suivi | #628 |
| UX-05 Rédaction finale | #629 |
| UX-06 Mention sur les données | #630 |
| UX-07 Captures et vidéos Duo | #631 |
| UX-08 Maquettes des scénarios | #632 |
| UX-09 Spécification du formulaire | #633 |
| UX-10 Réalisation du formulaire | #634 |
| UX-11 Revue sécurité et mise en ligne restreinte | #635 |

Règles :
1. **Claims et PR** selon les règles du dépôt : `/claim <session-id>` avant de commencer, `Claim:` et `Closes #N` dans la PR.
2. **Mise à jour du tableau de #628** par la session qui ferme un lot, dans le même geste que la fermeture de l'issue.
3. **Point hebdomadaire** pour le PO : ce qui est fait, ce qui bloque, la date d'ouverture estimée du questionnaire.

## 5. Ordre de lancement

| Vague | Lots | Condition |
|---|---|---|
| 1 | UX-05, UX-06, UX-07, UX-09 | Aucune |
| 2 | UX-08 | UX-07 fait |
| 3 | UX-10 | UX-05, UX-06, UX-08 et UX-09 faits |
| 4 | UX-11, puis le test à cinq | UX-10 fait ; sous-domaine choisi |

## 6. Inputs du PO

Réponses du 7 novembre 2026 :

| Sujet | Réponse |
|---|---|
| VPS et sous-domaine | À choisir plus tard ; ne bloque que la mise en ligne |
| Code du formulaire | Sur `dev-swift`, dans le répertoire dédié `tooling/ux-survey/` |
| Documents du questionnaire | Sur `dev-swift`, dans `docs/ux/` |
| Issues | Créer l'issue parapluie et les issues de lots |
| Responsable des données | Bruno Arene, ezzz75@gmail.com |
| Rendu natif | WebView conservée ; décision technique ultérieure |

## 7. Redface 2 : ce qu'on sait, ce qui aiderait

**Déjà lu dans le dépôt public**, idées seulement à cause de la licence GPL-3.0 :
- son ADR-011 sur l'arbre `PostContent` ;
- sa liste de limitations connues ;
- la comparaison existante dans `docs/research/redface2-comparison.md`.

**Ce qu'on en retient pour le prototype :**
- un arbre sémantique, pas une copie du DOM HTML ;
- le même arbre pour le lecteur et pour l'aperçu de l'éditeur, alimenté par deux parseurs, HTML et BBCode, mais jamais en passant de HTML à BBCode ;
- une première tranche de rendu directement sur un sous-ensemble HTML pour apprendre vite, puis le contrat stable ;
- un préchargement non authentifié pour ne pas marquer les sujets comme lus ;
- un arbre stocké en base devient coûteux à faire évoluer, car chaque nouveau type de bloc impose une migration.

**Ce qui aiderait, si vous pouvez l'obtenir de leur auteur :**
1. Comment ils gèrent la sélection de texte et la citation d'un extrait en rendu natif : c'est notre risque principal.
2. Leurs mesures de performance sur les pages lourdes en images et smileys.
3. Les cas HFR qui leur ont posé problème au rendu : tableaux, couleurs, imbrications, smileys personnels.
4. Un accord explicite, par exemple sous licence CC-BY ou CC0, pour s'inspirer de leur spécification des images (`docs/specs/images.md`) et de la liste de leurs nœuds d'arbre.

Tout contact avec eux est une action publique hors du dépôt : elle reste à votre initiative.

## 8. Décision : le questionnaire n'attend pas le prototype

Tranché par le PO le 7 novembre 2026 : le lecteur garde la WebView pour le moment, et le rendu natif sera une décision technique ultérieure. Le questionnaire avance sans le prototype. Le scénario « pages améliorées » ne présente que des améliorations possibles avec la WebView.

La relecture du 6 novembre reste valable comme analyse : la plupart des bénéfices existent déjà dans le lecteur de SwiftHFR ou relèvent du préchargement, et seuls trois sont réservés au natif (swipe qui suit le doigt, position à la ligne près, sélection sans conflit avec le swipe).
