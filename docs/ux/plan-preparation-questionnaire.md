# Plan de préparation du questionnaire UX

Date : 6 novembre 2026. Ce document prépare le travail ; rien n'est lancé. Le contenu du questionnaire fait foi dans `docs/ux/tri-m5-decisions.md`, section 4.

## 1. Ce qui est prêt, ce qui manque

### 1.1 Prêt : le contenu

| Élément | Où | État |
|---|---|---|
| Structure en six parties | tri, §4 | Validée par le PO |
| Questions de profil | tri, §4.1 | Rédigées |
| Question d'ouverture | tri, §4.2 | Rédigée |
| Thème 1, deux scénarios | tri, §4.3 | Décrits, libellés à finaliser |
| Thème 2, tri de cartes et trois dispositions | tri, §4.4 | Décrits, libellés à finaliser |
| Dix cartes de réaction et une question sur les messages privés | tri, §4.5 | Libellés proposés |
| Contrôle des propositions classées Non | tri, §4.7 | Fait |
| Lignes directrices du PO | tri, §2 | Validées |

Volume estimé : environ 21 interactions, pour 5 à 7 minutes, après les ajouts du 7 novembre 2026.

### 1.2 Manque : décisions pratiques, visuels, outil

| Manque | Pourquoi c'est bloquant |
|---|---|
| Décisions pratiques (§2) | Tranchées le 6 novembre 2026 |
| Visuels des scénarios | Les thèmes 1 et 2 reposent sur des images ; sans elles, les répondants comparent des phrases |
| Prototype de rendu natif | Plus bloquant : différé le 7 novembre 2026, la WebView est conservée |
| Formulaire en ligne | Rien n'existe encore |
| Textes d'accompagnement | Introduction, mention sur les données, message de fin, annonce sur le topic |

## 2. Décisions du PO

Tranchées le 6 novembre 2026.

| # | Sujet | Décision | Conséquence |
|---|---|---|---|
| 1 | Outil | **Formulaire maison sur le VPS** | Lot E à développer ; tri de cartes, cartes de réaction et écran de fin comparatif possibles |
| 2 | Écran de fin | **Statistiques en direct** | Le répondant voit ses réponses comparées à la communauté ; risque d'influence sur les derniers répondants, accepté |
| 3 | Identité | **Pseudo HFR facultatif** | Mention sur les données obligatoire : finalité, durée de conservation, demande de suppression |
| 4 | Scénario « pages améliorées » | **Ne pas attendre : la WebView est conservée** (révisé le 7 novembre 2026, d'abord « attendre le prototype ») | Le scénario ne présente que les améliorations possibles avec la WebView ; le rendu natif devient une décision technique ultérieure ; le lot D est différé |
| 5 | Duo | **Vidéos seulement** | Pas de bêta TestFlight dédiée ; vidéos de 10 secondes dans le questionnaire |
| 6 | Diffusion | **Topic HFR et note TestFlight** | Pas de bannière dans l'app, donc pas de version à publier avant l'ouverture |
| 7 | Durée | **Deux semaines**, relance à mi-parcours | — |

## 3. Lots de travail

Ordre indicatif. Le lot A est fait (section 2). Les lots B et C avancent en parallèle. Le lot D est différé.

### A. Décisions préalables

- **Entrée** : section 2.
- **Sortie** : les sept décisions consignées en section 2.
- **Qui** : PO.
- **État** : fait le 6 novembre 2026.

### B. Rédaction finale

- **Entrée** : tri, §4 ; décisions 3 et 4.
- **Contenu** :
  - libellés définitifs de chaque question et de chaque réponse ;
  - texte des cartes ;
  - introduction de 3 lignes : but, durée, anonymat ou pseudo facultatif ;
  - mention sur les données : ce qui est collecté, pourquoi, combien de temps, comment demander la suppression si un pseudo est laissé ;
  - message de fin ;
  - annonce pour le topic HFR et note TestFlight.
- **Règle** : libellés du point de vue de l'utilisateur, sans jargon ni promesse ; toujours une réponse « comme aujourd'hui ».
- **Sortie** : `docs/ux/questionnaire/questions.md`, chaque question rattachée à sa section du tri.
- **Durée** : 1 à 2 jours.

### C. Visuels

- **Entrée** : tri, §4.3 et §4.4 ; décision 5.
- **Contenu** :

| Visuel | Thème | Source |
|---|---|---|
| Lecture d'un sujet, app actuelle, iPhone | 1 | Capture réelle |
| Scénario « pages améliorées » : changement de page, message masqué déplié | 1 | Maquette |
| Scénario « lecture continue » : passage d'une page à l'autre | 1 | GIF court |
| Barre latérale actuelle, iPad | 2 | Capture réelle |
| Cartes des sections pour le tri | 2 | Pictogramme et libellé |
| Trois dispositions iPad | 2 | Une capture réelle, deux maquettes |
| Les mêmes sur Duo déplié | 2 | Maquettes, vidéo de 10 secondes |

- **Règle** : même sujet, même thème, même appareil pour tous les visuels d'un thème ; aucune proposition classée Non visible à l'écran, par exemple pas de scrubber.
- **Sortie** : `docs/ux/questionnaire/visuals/`, nommage par thème et scénario.
- **Durée** : 3 à 5 jours.

### D. Prototype de rendu natif (interne)

- **Entrée** : tri, §5.
- **Contenu** : trois cas difficiles tirés des captures existantes : citations imbriquées avec smileys, citation d'extrait, tableau ou bloc de code.
- **Sortie** : verdict sur la faisabilité, et la liste des bénéfices que le scénario « pages améliorées » peut promettre.
- **Durée** : 2 à 3 jours.
- **Différé** (décision 4 révisée le 7 novembre 2026) : la WebView est conservée ; ce lot servira à la décision technique ultérieure et ne conditionne plus le questionnaire.

### E. Formulaire

- **Entrée** : décisions 1 à 3 ; sorties de B et C.
- **Contenu** :
  - page unique, mobile d'abord, en français ;
  - formats : choix simple, tri de cartes, cartes de réaction, texte libre ;
  - branchement : le thème 2 ne s'affiche qu'aux profils iPad, Duo ou plusieurs appareils ;
  - toutes les questions sont facultatives ;
  - stockage des réponses, export CSV ou JSON pour l'analyse ;
  - anti-doublons sans compte, limitation de débit, champ piège contre les robots ;
  - écran de fin selon la décision 2 ;
  - HTTPS, aucun cookie tiers, aucun outil de mesure d'audience.
- **Code** : sur `dev-swift`, dans le répertoire dédié `tooling/ux-survey/`, réutilisable pour de futurs sondages.
- **Sortie** : questionnaire en ligne sur un sous-domaine du VPS, choisi plus tard, en accès restreint pour le test.
- **Durée** : 2 à 3 jours.

### F. Test

- **Entrée** : formulaire en accès restreint.
- **Contenu** : 5 bêta-testeurs, dont au moins un sur iPad. On mesure la durée, on relève les questions mal comprises et on vérifie que les scénarios se distinguent.
- **Sortie** : corrections appliquées, durée médiane sous 7 minutes.
- **Durée** : 2 à 3 jours, attente des testeurs comprise.

### G. Diffusion et analyse (après la préparation)

- Diffusion sur le topic HFR et dans la note TestFlight, ouverture deux semaines, relance à mi-parcours.
- Analyse par profil :
  - appétit de nouveauté selon l'ancienneté ;
  - choix de lecture selon l'usage ;
  - thème 2 sur les seuls profils concernés.
- Sortie : `docs/ux/questionnaire/resultats.md`, puis la feuille de route publiée sur le topic.

## 4. Calendrier indicatif

| Semaine | Lots |
|---|---|
| S1 | B et C en parallèle (A fait) ; E démarre sur la spécification |
| S2 | Fin de B et C ; réalisation de E |
| S3 | F, corrections ; ouverture du questionnaire |
| S4-S5 | Questionnaire ouvert deux semaines, relance à mi-parcours |
| S6 | Analyse et publication |

Le chemin critique passe par les visuels (C) et le formulaire (E). Le sous-domaine sera choisi plus tard : il ne bloque que la mise en ligne.

## 5. Ce qui se fait en parallèle sans attendre les réponses

Le questionnaire ne bloque pas le développement. Ces sujets sont décidés et peuvent avancer pendant la collecte :
- navigateur de pages (LOT-110) ;
- écran « Quoi de neuf » ;
- reprise des fonctions de parité (tri, §3.1) ;
- vérifications de la section 3.3 du tri ;
- fermeture des propositions classées Non côté GitHub.
