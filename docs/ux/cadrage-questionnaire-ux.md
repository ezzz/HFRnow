# Cadrage : questionnaire UX HFRnow (SuperHFR+)

> **Remplacé** le 6 novembre 2026 par `docs/ux/tri-m5-decisions.md`, qui fait foi pour la sélection du questionnaire. Ce document reste comme historique : certaines pistes citées ici ont été classées Non par le PO, comme la couleur d'accent unique ou Spotlight.

Date : 4 novembre 2026. Base : version 4.0.4 (37), backlog issu du topic HFR p.495-499, PR #3 à #6 de moust4ki (inventoriées dans `docs/review-pr-master-3-4-5-6.md`).

## 1. Pourquoi

L'app est à un carrefour : le design 4.0 a reçu des retours partagés (densité, thème sombre, « revenir à l'ancien design »), une direction alternative existe dans les PR #3-#6 (« Natif calme », barre latérale custom, couleur unique), et iOS 26 pousse ses propres conventions (Liquid Glass, barre d'onglets adaptative, onglet Recherche, sous-titres de navigation).

Le questionnaire doit servir à **trancher des décisions**, pas à collecter des souhaits. Règle de conception : chaque question est rattachée à une décision de la liste ci-dessous. Une question qui n'éclaire aucune décision est supprimée.

## 2. Décisions à éclairer

| # | Décision | Options en jeu | Source des idées |
|---|---|---|---|
| D1 | Lecture d'un sujet : pagination ou scroll infini | Pages ‹ › (actuel) · scroll infini pur · hybride (scroll + repère de page) | Demande utilisateur |
| D2 | iPad en paysage : 2 ou 3 panneaux | Barre latérale + liste + sujet (HFR-006 livré) · liste + sujet seulement · barre latérale escamotable | Backlog HFR-006, PR #6 |
| D3 | Composition de la barre d'onglets / des pages | Onglets fixes (Catégories, Favoris, Messages, Plus) · onglets personnalisables · onglet Recherche dédié (iOS 26) · ordre choisi par l'utilisateur | Demande utilisateur, HIG iOS 26, PR #6 |
| D4 | Densité et mode compact | Dense par défaut · aéré par défaut avec option compacte visible · deux presets (« forum » / « mobile ») | Backlog HFR-012/013/024 |
| D5 | Thèmes : sombre, OLED, accent | Sombre plus contrasté · thème OLED noir pur · couleur d'accent unique (7 choix) vs teinte libre · Liquid Glass tel quel | Backlog HFR-014/023, PR #5-#6 |
| D6 | Lignes de sujets : repères de lecture | Fond coloré par drapeau (actuel) · pastille/icône façon Mail · séparateur anciens/nouveaux posts · indicateur de position dans le sujet | Backlog HFR-015/016/021, PR #5 |
| D7 | Catégories : liste plate ou familles | Liste plate (actuel) · groupées en 4 familles avec pictogrammes | PR #5 |
| D8 | Navigation dans un sujet | Menu de pages depuis le titre · feuille « Aller à la page » avec curseur · glisser « Dernière page » · numéro honnête « Page N » quand le total est inconnu | PR #3, #5, #6 |
| D9 | Répondre : flux rapide ou flux forum | Bouton + configurable (actuel) · un seul flux · brouillons mis en avant | `specifications.md` |
| D10 | Fonctions nouvelles à prioriser | Widget favoris non lus · notifications MP · filtrage par drapeau · création de sujet / sondage · mode lecture (texte seul) · icônes d'app · raccourcis Siri / Spotlight | Backlog P4, idées |

Non négociable, donc pas soumis au vote : conformité HIG et App Review, Dynamic Type, accessibilité, pas de barre système remplacée par une barre custom sans raison forte (PR #6 contredit ce point ; le questionnaire mesure l'envie de « barre latérale dépliable », pas l'implémentation).

## 3. Travail préliminaire (2 à 3 semaines, avant d'écrire une ligne de formulaire)

### 3.1 Trier les idées des PR #3-#6 (2 jours)

Ne garder que les idées qui changent l'usage, reformulées comme des propositions à l'utilisateur et non comme des choix d'implémentation. Sélection proposée :

1. Pagination honnête (« Page N » sans faux total) et « Aller à la page » avec curseur.
2. Barre latérale dépliable (Messages, Catégories) sur iPad / Duo.
3. Couleur d'accent unique appliquée partout.
4. Lignes de sujets façon Mail (pastille non-lu, auteur · date, « p. N / M ») sans fond coloré.
5. Catégories groupées par famille.
6. Thème OLED.
7. Menu de pages depuis le titre du sujet, glisser « Dernière page ».
8. Corps de texte 17 pt par défaut (contre 15 pt actuel) : à tester en « ça ou ça ».

Laisser de côté : états vides avec lien Safari, carte Plus réorganisée, refonte du profil, styles de sondage. Ce sont des finitions, pas des orientations.

### 3.2 Construire les visuels de comparaison (1 semaine)

Un questionnaire ludique repose sur des images, pas sur des phrases. Pour chaque décision D1-D8, produire deux ou trois captures **à état identique** (même sujet, même thème, même appareil) :

- captures réelles de l'app 4.0.4 pour l'état actuel ;
- variantes via SwiftUI Previews (`RenderPreview`) ou Claude Design pour les propositions, en reprenant le même contenu ;
- un montage iPad pour D2 avec les trois dispositions ;
- un court GIF pour D1 (pagination vs scroll infini), le seul cas où l'image fixe ne suffit pas.

Livrable : dossier `docs/ux/questionnaire/visuals/` avec un nommage `D1-a.png`, `D1-b.png`, etc.

### 3.3 Définir les segments (1 jour)

Trois questions de profil en ouverture, posées comme un choix de « personnage » :

- appareil principal : iPhone · iPad · iPhone Duo · plusieurs ;
- usage : je lis surtout · je lis et je réponds · je poste beaucoup (plusieurs messages par jour) ;
- ancienneté : utilisateur de la v3 (ancien design) · arrivé avec la 4.0 · utilisateur TestFlight.

Toute analyse se fait par segment. Le signal « revenir à l'ancien design » (HFR-030) n'a de sens que croisé avec le segment v3.

### 3.4 Écrire la banque de questions (3 jours)

Formats retenus, du plus ludique au plus classique :

| Format | Usage | Décisions |
|---|---|---|
| « Ça ou ça » : deux captures côte à côte, un tap | Orientations visuelles | D4, D5, D6, D7, D8 |
| Cartes à glisser (gauche = non, droite = oui, haut = « j'adore ») | Idées innovantes, réaction rapide | D10 |
| Budget de 10 jetons à répartir entre 6 fonctions | Priorisation forcée | D10 |
| Classement par glisser-déposer de 4 à 5 items | Ordre des onglets | D3 |
| Échelle emoji 1 à 5 sur des irritants concrets | Points durs | D1, D4, D9 |
| Un champ libre unique en fin, 280 caractères | Signal faible, verbatims | tous |

Contraintes : 20 à 25 questions, moins de 7 minutes, chaque question sautable, jamais de « voulez-vous X ? » sans contrepartie (tout le monde dit oui). Toujours une option « garder comme aujourd'hui ».

### 3.5 Choisir l'hébergement et la stack (1 jour)

Objectif : un seul service sur le VPS, zéro dépendance lourde.

- Front : une page statique (HTML + CSS + JS vanilla ou Preact), captures en WebP, fonctionne sur mobile en priorité (les répondants viendront du topic HFR sur iPhone).
- Back : un micro-service (Node/Hono ou Python/FastAPI) avec SQLite, deux routes : `POST /answers`, `GET /stats` (agrégats anonymes pour l'écran de fin).
- Nginx devant, HTTPS, limitation de débit par IP, honeypot anti-bot, un identifiant aléatoire en `localStorage` pour limiter les doublons sans compte.
- Export CSV / JSON pour l'analyse, page admin protégée par mot de passe.
- Aucune donnée personnelle : pseudo HFR facultatif en fin, mention explicite de l'anonymat. Pas de cookie tiers.

Alternative si le temps manque : Tally ou Typeform, mais on perd l'écran « vous vs la communauté » et les formats glisser-déposer, qui font l'intérêt ludique.

### 3.6 Préparer la diffusion (1 jour)

- Message sur le topic HFR de l'app avec le lien, 2 captures du questionnaire et la promesse de publier les résultats.
- Note TestFlight « Ce qu'il faut tester » avec le lien.
- Bannière dans l'app (onglet Plus ou écran « Nouveautés ») vers le lien, retirée à la version suivante.
- Sondage natif HFR dans le topic en teaser (« Scroll infini ou pages ? ») pour amorcer la discussion.

## 4. Objectif à atteindre

### 4.1 Livrables

1. Questionnaire en ligne sur un sous-domaine du VPS, 20 à 25 questions, visuels pour chaque décision, écran de fin « vos réponses vs la communauté » en direct.
2. Banque de questions versionnée dans `docs/ux/questionnaire/questions.md`, chaque question annotée de sa décision D1-D10.
3. Jeu de visuels de comparaison réutilisable ensuite dans le changelog et sur le topic.
4. Rapport de synthèse `docs/ux/questionnaire/resultats.md` : une ligne par décision avec le verdict, la répartition par segment et la suite donnée.
5. Feuille de route 4.1 / 5.0 révisée à partir du rapport, publiée sur le topic (« vous avez voté, voici ce qui arrive »).

### 4.2 Critères de succès

| Critère | Cible |
|---|---|
| Réponses complètes | 100 au minimum, 200 visé |
| Taux de complétion (arrivé à la fin / a commencé) | > 70 % |
| Durée médiane | < 7 minutes |
| Décisions tranchées | chaque D1-D9 avec une majorité nette (> 60 %) ou un clivage par segment identifié |
| Répartition des segments | au moins 20 répondants iPad, 20 « gros posteurs » |

### 4.3 Calendrier indicatif

| Semaine | Étape |
|---|---|
| S1 | Tri des idées, segments, banque de questions v1 |
| S2 | Visuels de comparaison, relecture de la banque |
| S3 | Développement du formulaire, test avec 5 bêta-testeurs, corrections |
| S4-S5 | Diffusion, questionnaire ouvert 2 semaines, relance à mi-parcours |
| S6 | Analyse, rapport, publication des résultats et de la feuille de route |

## 5. Risques et parades

- **Biais d'échantillon** : les répondants sont les plus engagés du topic. Parade : segmenter, pondérer les verbatims, ne pas lire un 55/45 comme une décision.
- **Nostalgie de la v3** : réponse globale « avant c'était mieux ». Parade : ne jamais proposer « ancien design » comme réponse, décomposer en irritants concrets (densité, couleurs de drapeaux, taille de texte).
- **Vote contre les guidelines Apple** : par exemple plébiscite d'une barre custom. Parade : liste des non-négociables fixée avant (section 2), et questions formulées sur l'intention, pas la mise en œuvre.
- **Doublons et trolls** : topic public. Parade : limitation de débit, honeypot, identifiant local, champ libre borné, modération manuelle des verbatims.
- **Dérive du périmètre** : envie d'ajouter des questions. Parade : la règle « une question, une décision » et le plafond de 25.
- **Réponses sans suite** : perte de confiance de la communauté. Parade : date de publication des résultats annoncée dès le lancement.

## 6. Points à trancher avant de démarrer

1. Sous-domaine et stack du VPS (Node ou Python, selon ce qui tourne déjà).
2. Afficher les statistiques en direct en fin de questionnaire, ou seulement à la clôture (le direct est plus ludique mais influence les derniers répondants).
3. Pseudo HFR facultatif en fin, ou strictement anonyme.
4. Inclure D9 (flux de réponse) et D10 (fonctions nouvelles) dans ce questionnaire, ou les réserver à une deuxième vague plus courte pour tenir les 7 minutes.
