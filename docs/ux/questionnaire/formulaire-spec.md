# Spécification technique du formulaire

Date : 8 novembre 2026. Lot UX-09 (#633), suivi sur #628. Ce document dit comment construire le formulaire du questionnaire UX ; la réalisation (UX-10, #634) le suit sans aller-retour, la revue de sécurité (UX-11, #635) le prend comme référence.

Entrées qui font foi, dans cet ordre en cas d'écart : les issues #628 à #635 et les décisions du PO qui y sont commentées, puis `cadrage-construction.md` (identifiants §2, contrats §3, contraintes §4), puis ce document. Les textes viennent de `questions.md` (#629) et `donnees.md` (#630), les visuels de `visuels/` (#632).

Décisions du PO reprises ici :
- D1 : une réponse « comme aujourd'hui » au thème 1, et partout où une évolution est proposée (`O1`, `L1`, `D1`, `D2`, `M1`) ;
- D2 : pseudo `I1` à la fin, juste avant l'envoi ;
- D3, révisée le 8 novembre 2026 : statistiques de l'écran de fin après **10** réponses ;
- carte `C08` retirée le 8 novembre 2026 : **neuf cartes**, `C01` à `C07`, `C09`, `C10` ; `C08` n'est jamais réutilisé ;
- `L1` : chaque réponse a un titre court et au plus trois points de détail ;
- conservation : réponses, pseudos, table de correspondance, exports et sauvegardes effacés **deux mois après la fermeture** ; seuls les résultats d'ensemble restent ;
- question `G1` ajoutée le 8 novembre 2026 : irritants du quotidien, texte libre de 280 caractères, facultatif, sans condition, sur son propre écran juste après `O1` et avant `L1` (cadrage §2, #670) ;
- hébergement en France (UE).

D4 (description du VPS) est tranchée : Ubuntu 24.04 LTS avec Docker Engine et Docker Compose, en France, partagé avec une autre application. L'exposition publique passe par Tailscale Funnel (décision du PO du 9 novembre 2026) ; le proxy inverse avec sous-domaine reste une solution de secours, et la [section 13](#13-points-ouverts-avant-le-déploiement) liste ce qui reste à décider ou à vérifier. Les exigences R1 à R12 de `donnees.md` (#630, #669) sont reprises ; la [section 15](#15-exigences-de-donneesmd) dit où.

## 1. Choix techniques

| Élément | Choix | Raison |
|---|---|---|
| Service | Un binaire **Go**, bibliothèque standard (`net/http`, `embed`, `log/slog`, `crypto/hmac`, `crypto/rand`) | Un seul exécutable, front compris ; aucun interpréteur sur le VPS ; serveur HTTP prévu pour la production ; compile vers Linux x86-64 et arm64 depuis n'importe quel poste |
| Base | **SQLite**, pilote `modernc.org/sqlite` (Go pur, sans cgo) | Un fichier ; c'est la **seule dépendance tierce**, épinglée dans `go.sum`, soumise à la revue de dépendances. Sauvegarde par `ux-survey sauvegarder` seulement (§12), jamais par copie du fichier pendant que le service tourne |
| Front | HTML, CSS et JavaScript sans framework ni étape de build, servis par le binaire | Tient sous 200 Ko ; rien à charger d'un autre domaine ; relisible en revue de sécurité |
| Livraison | Image conteneur, lancée par Docker Compose (D4) | Décrite en [section 11](#11-déploiement) |
| Tests | `go test` pour le service ; `node --test` (exécuteur intégré à Node, sans paquet) pour la logique pure du front | Aucune dépendance de test supplémentaire |

Écartés : Python (le serveur `http.server` n'est pas prévu pour la production, un framework ajoute des dépendances), Node côté serveur (dépendances npm et un runtime à maintenir sur le VPS), un outil de sondage tiers (décision 1 du plan : formulaire maison).

La version de Go est la dernière stable au moment de #634, épinglée dans `go.mod` et dans le `Dockerfile`.

## 2. Arborescence de `tooling/ux-survey/`

```text
tooling/ux-survey/
  README.md                  lancer, configurer, déployer, retirer (reprend §10 à §12)
  go.mod, go.sum
  cmd/ux-survey/main.go      sous-commandes : serve, export, sauvegarder, fermer, effacer, pseudo
  internal/contenu/          chargement, validation et rendu des valeurs de configuration
  internal/reponse/          validation, normalisation, conditions côté serveur
  internal/stockage/         SQLite : schéma, écriture, effacement
  internal/stats/            agrégats de l'écran de fin et de l'export d'ensemble
  internal/exporter/         exports d'analyse et d'ensemble
  internal/web/              routes, en-têtes, limites de débit, journaux
  contenu/questionnaire.json transcription de questions.md (§3)
  web/                       index.html, donnees.html, app.js, logique.js, style.css
  web/visuels/               copie versionnée de docs/ux/questionnaire/visuels/ (#632)
  web/logique.test.mjs       tests node du front
  deploy/Dockerfile
  deploy/compose.yaml
  deploy/ux-survey.env.exemple  variables, sans secret
  deploy/Caddyfile.exemple   seulement pour l'exposition (b) du §11
```

Un fichier par type ou par responsabilité. `web/` est embarqué par `embed`, qui ne lit pas hors du module : les visuels sont donc **copiés et versionnés** dans `web/visuels/`, et le test 2 vérifie qu'ils sont identiques octet pour octet à ceux de `docs/ux/questionnaire/visuels/`.

Une tâche CI dédiée lance `go vet`, `go test` et `node --test`. Elle est filtrée sur `tooling/ux-survey/**`, `docs/ux/questionnaire/questions.md`, `docs/ux/questionnaire/donnees.md` et `docs/ux/questionnaire/visuels/**`, pour qu'une correction de libellé dans le document relance le test de concordance.

## 3. Contenu : `questionnaire.json`

Le fichier transcrit `docs/ux/questionnaire/questions.md` (#629) sans rien inventer : identifiants, codes, libellés, aides, détails et conditions identiques, même ordre. Les codes cités ici viennent de `questions.md` à la date de ce document, mais les libellés des exemples sont fictifs ; en cas d'écart, **`questions.md` fait foi**.

Forme (extrait illustratif) :

```json
{
  "version": "2026-11-v1",
  "ecrans": [
    { "id": "irritants", "questions": ["G1"] },
    { "id": "theme1", "questions": ["L1", "L2"] },
    { "id": "theme2-a", "questions": ["D1"], "condition": { "P1": ["ipad", "duo", "plusieurs"] } }
  ],
  "questions": {
    "L1": { "type": "choix", "libelle": "Pour lire un long sujet, quelle version de l'app préférez-vous ?",
            "reponses": [ { "code": "pages_ameliorees", "libelle": "Des pages améliorées",
                            "details": ["Pas d'écran blanc entre les pages", "…"] } ] },
    "L2": { "type": "texte", "libelle": "…", "max": 280 },
    "D1": { "type": "tri", "libelle": "…",
            "sections": [ { "code": "favoris", "libelle": "Favoris" } ],
            "etats": [ { "code": "garder", "libelle": "Je la veux dans la barre" } ],
            "reponse_seule": { "code": "comme_aujourdhui", "libelle": "Laisser la barre comme aujourd'hui" } },
    "C01": { "type": "reaction", "libelle": "…", "reponses": [ { "code": "adore", "libelle": "J'adore" } ] }
  },
  "cartes": ["C01", "C02", "C03", "C04", "C05", "C06", "C07", "C09", "C10"]
}
```

Types : `texte-seul` (`E0`, `E1`), `choix` (choix simple), `texte` (texte court), `tri` (`D1`), `reaction` (cartes), `pseudo` (`I1`). Les visuels sont référencés par leur nom de fichier, avec le texte alternatif de `visuels/inventaire.md`.

**Test de concordance** (contrat §3.2). Un test Go trouve la racine du dépôt en remontant jusqu'au dossier qui contient `.git` (le `go test` s'exécute dans le dossier du paquet), lit `docs/ux/questionnaire/questions.md` et compare avec `questionnaire.json`. Règles de lecture :
- un bloc commence à un titre `###` dont le texte correspond à `^[A-Z]\d{1,2}$` et va jusqu'au titre suivant ; les autres titres `###` (par exemple « Écran Cartes (note, pas un bloc de question) ») sont ignorés, avec leur contenu ;
- ligne `- Réponses :` d'une question à choix : liste `` `code` Libellé `` séparée par `·` ;
- sous-liste `- Détails :` (`L1`, et `D2` si `questions.md` en donne) : une ligne par code, `` `code` : point · point · point ``, au plus trois points, séparateur « ` : ` » après le code ;
- bloc `D1`, sous-liste de `- Réponses :` à quatre lignes, chacune comparée avec sa règle :
  - `Sections :` neuf `` `code` Libellé `` séparés par `·` ;
  - `États :` `` `garder` `` · `` `deplier` `` · `` `ecarter` `` avec leurs libellés ;
  - `Ordre :` texte seul, rien à comparer ;
  - `Réponse seule :` `` `comme_aujourdhui` Laisser la barre comme aujourd'hui `` ;
- ligne `- Aide :` : « (aucune) » ou « (facultative) » veut dire pas d'aide dans le JSON ; sinon, le texte entre les premiers « » est comparé à l'aide du JSON, et la prose hors guillemets est ignorée ; pour `E0` et `E1` (`texte-seul`), chaque texte entre « » doit figurer dans le JSON ;
- ligne `- Condition :` : « (aucune) », ou `` `P1` vaut `ipad`, `duo` ou `plusieurs` `` : l'identifiant est dans les premiers accents graves, les codes dans les suivants, comparés à la condition de l'écran dans le JSON.

Le test échoue sur tout identifiant, code, libellé ou détail absent, en trop ou différent, sur un ordre différent, sur un bloc `C08` présent dans le JSON (si `questions.md` garde un bloc `C08` marqué retiré, le test l'ignore), et sur un identifiant de `cadrage-construction.md` §2 absent (hors `C08`).

`donnees.html` transcrit la page détaillée de `donnees.md` (#630), et le paragraphe au-dessus de `I1` vient du même document ; `questions.md` garde les libellés courts du champ. Les valeurs entre accolades de `donnees.md` (`{date_fermeture}`, `{date_effacement}`, `{date_mise_a_jour}`, `{seuil_statistiques}`) restent telles quelles dans les fichiers et sont remplacées par le serveur (§10).

## 4. Parcours côté navigateur

- **Une page, un écran par bloc** de `cadrage-construction.md` §2, une barre de progression (`<progress>` avec texte « Étape n sur m »), boutons « Précédent » et « Suivant ». Le changement d'écran met le focus sur le titre de l'écran.
- **Tout est facultatif** : « Suivant » est toujours actif. Chaque question répondue a un bouton « Effacer ma réponse », puisqu'un bouton radio ne se décoche pas.
- **Conditions** :
  - les écrans `D1` et `D2` s'affichent seulement si `P1` vaut `ipad`, `duo` ou `plusieurs` ; `P1` sans réponse les masque ; si `P1` change vers une autre valeur, `D1` et `D2` sont effacés du brouillon ;
  - la barre de progression recalcule le nombre d'étapes.
- **`L1` avec détails** : chaque réponse est un bouton radio dont le libellé est le titre court, suivi d'une liste `<ul>` d'au plus trois points, reliée au bouton par `aria-describedby`. Même rendu pour toute question dont les réponses ont des détails.
- **Cartes** : les neuf cartes de `cartes` sont mélangées une fois par répondant (Fisher-Yates sur `crypto.getRandomValues`), l'ordre est gardé dans le brouillon et envoyé avec la réponse. La mention « pistes à l'étude, pas des engagements » est en tête de l'écran. Chaque carte est un `<fieldset>` avec sa phrase en `<legend>` et trois boutons radio natifs habillés en boutons.
- **Tri `D1`** :
  - en tête, une **case à cocher** « Laisser la barre comme aujourd'hui » (et non un bouton radio, qui ne se décoche pas) ; cochée, elle désactive les cartes. Le bouton « Effacer ma réponse » de `D1` décoche la case et efface le tri ; décocher la case seule ne l'efface pas. Le tri reste dans le brouillon, rendu au décochage, mais la réponse envoyée est alors `{"comme_aujourdhui": true}` seule, sans `sections` ;
  - sinon, une liste ordonnée des neuf sections, dans l'ordre de `questions.md` ; pour chacune, un groupe de trois boutons radio (`garder`, `deplier`, `ecarter`, libellés de `questions.md`) ;
  - les sections gardées ou dépliables ont deux boutons « Monter » et « Descendre » dont le nom accessible contient la section (« Monter Favoris ») ; une section écartée descend sous les sections gardées et perd ses boutons ;
  - après un déplacement, une zone `aria-live="polite"` annonce « Favoris, position 2 sur 5 », et le focus reste sur le bouton utilisé ;
  - le glisser-déposer (Pointer Events) est facultatif et ne remplace jamais les boutons.
- **`G1`** : un écran à lui seul, après `O1` et avant le thème 1, sans condition, toujours affiché. Il vient avant toute proposition, pour que les pistes du questionnaire n'orientent pas la réponse.
- **Textes** : `G1`, `L2`, `C11`, `F1` limités à 280 caractères, `I1` à 40, avec compteur restant annoncé discrètement.
- **Visuels** : images avec `loading="lazy"` et texte alternatif ; vidéos `preload="none"`, `muted`, `playsinline`, image d'attente, jamais en lecture automatique.
- **Mention sur les données** : liens vers `/donnees` dans `E0` et au-dessus de `I1`, ouverts dans un nouvel onglet (`target="_blank" rel="noopener"`) ; le brouillon n'est pas touché (R8).
- **Brouillon** : `localStorage`, clé `ux-survey:<version>:brouillon` (réponses, écran courant, ordre des cartes, heure de début). Écrit à chaque changement, relu au chargement. Effacé après un envoi accepté (201) **et** après un `deja_recu` (409), une fois l'écran de fin rendu (R3). Si `localStorage` est indisponible (navigation privée), le formulaire marche sans brouillon.
- **Jeton** : au premier chargement, un jeton aléatoire de 128 bits (`crypto.getRandomValues`, hexadécimal) est gardé sous `ux-survey:jeton`, **sans version**, pour qu'une correction de contenu ne remette pas l'anti-doublon à zéro. Il part dans le corps de l'envoi ; aucun cookie n'est posé (R2).
- **Envoi unique** : à la fin, après `I1`, un seul bouton « Envoyer », désactivé pendant la requête. Réseau en échec : message et nouvel essai possible avec le même jeton, sans risque de doublon (§6).
- **Affichage** : unités `rem`, aucune taille de police fixe, `prefers-color-scheme` pour le mode sombre (variables CSS), `prefers-reduced-motion` respecté, cibles tactiles de 44 points au moins. Mobile d'abord.
- **Champ piège** : un champ `site_web` hors écran (classe de masquage visuel, `aria-hidden="true"`, `tabindex="-1"`, `autocomplete="off"`), toujours envoyé, vide pour un humain.

**Rendu compatible avec la CSP** (§9) :
- tout texte, du contenu comme des réponses du répondant, est inséré par `textContent` ou `createElement`, jamais par `innerHTML`, `insertAdjacentHTML` ou `document.write` ;
- les largeurs de barres et la progression passent par le CSSOM (`el.style.setProperty('--part', '42%')`, `progress.value = n`), jamais par un attribut `style` ni `setAttribute('style', …)`, que `style-src 'self'` bloque ;
- aucun gestionnaire d'événement en attribut (`onclick`).

La logique sans DOM (conditions, mélange, construction de la réponse, calcul « vous / la communauté ») vit dans `web/logique.js`, module ES testé par `node --test` ; `app.js` ne fait que l'affichage.

## 5. Modèle de données

### 5.1 Une réponse envoyée

```json
{
  "version": "2026-11-v1",
  "jeton": "9f2c…(32 caractères hexadécimaux)",
  "site_web": "",
  "duree_s": 312,
  "reponses": {
    "P1": "ipad", "P2": "lit_surtout", "P3": "avant_4_0",
    "O1": "petites_touches",
    "G1": "texte libre",
    "L1": "pages_ameliorees", "L2": "texte libre",
    "D1": { "comme_aujourdhui": false,
            "sections": [ { "code": "favoris", "etat": "deplier", "rang": 1 },
                          { "code": "mp", "etat": "garder", "rang": 2 },
                          { "code": "reglages", "etat": "ecarter" } ] },
    "D2": "tableau_de_bord",
    "C04": "adore", "C01": "inutile",
    "ordre_cartes": ["C04", "C01", "C09", "C02", "C10", "C03", "C07", "C05", "C06"],
    "C11": "", "M1": "un_onglet", "F1": "", "I1": "pseudo facultatif"
  }
}
```

Une question sans réponse est absente. Une section de `D1` sans état choisi est absente de `sections`. `"D1": {"comme_aujourdhui": true}` est la réponse seule. `duree_s` est l'écart entre l'ouverture de `E0` et l'envoi, ramené dans 0–7200 s'il en sort (jamais de refus pour ce champ), pour vérifier le budget de 7 minutes au test à cinq.

### 5.2 Validation et normalisation côté serveur

Le serveur ne fait pas confiance au front :
- corps JSON de 16 Ko au plus, `Content-Type: application/json` exigé ;
- `version` égale à celle du contenu chargé, sinon 409 avec un message « rechargez la page » ;
- clé inconnue (dont `C08`), code inconnu ou type inattendu : 400, rien n'est stocké ;
- textes (`G1`, `L2`, `C11`, `F1`, `I1`) : normalisés NFC, caractères de contrôle retirés sauf retour à la ligne, espaces de bord retirés, longueur comptée en caractères (280, ou 40 pour `I1`) ; un texte vide devient absent ;
- `D1` :
  - `comme_aujourdhui` vrai avec une liste `sections` non vide : 400 ;
  - chaque code de section au plus une fois, état parmi `garder`, `deplier`, `ecarter` ;
  - les rangs ne couvrent que les sections `garder` et `deplier` : uniques et contigus de 1 à leur nombre (pas de 1 à 9) ; une section `ecarter` n'en a pas ;
  - `comme_aujourdhui` faux sans aucune section : `D1` devient absent ;
- `ordre_cartes` : permutation exacte des neuf cartes, sinon ignoré ;
- **conditions**, appliquées avant stockage même si le front a envoyé les valeurs :
  - `P1` absent ou différent de `ipad`, `duo`, `plusieurs` : `D1` et `D2` retirés. C'est la seule condition ; `L2` et `G1` n'en ont pas.

### 5.3 Schéma SQLite

Les réponses ne contiennent ni IP, ni jeton, ni heure : aucune table ne relie une réponse à une adresse. Toutes les requêtes sont **paramétrées** ; aucune requête SQL n'est construite par concaténation.

| Table | Colonnes | Rôle | Vidée |
|---|---|---|---|
| `reponses` | `identifiant` TEXT PK (16 caractères hexadécimaux tirés de `crypto/rand`, sans lien avec le pseudo ni l'ordre d'arrivée), `recue_le` TEXT (date `AAAA-MM-JJ` seulement, dans le décalage horaire de `UX_FERMETURE`), `version` TEXT, `duree_s` INTEGER, `ordre_cartes` TEXT, `donnees` TEXT (JSON normalisé, sans `I1`) | Les réponses | Par `effacer` (§12) |
| `pseudos` | `identifiant` TEXT PK référence `reponses`, `pseudo` TEXT | Table de correspondance pseudo ↔ identifiant (R9) : elle ne quitte jamais le serveur | Par `effacer`, ou ligne par ligne par `pseudo` (§12) |
| `jetons` | `empreinte` TEXT PK (SHA-256 du jeton) | Anti-doublon par navigateur | À la fermeture |
| `empreintes_ip` | `empreinte` TEXT PK (HMAC-SHA-256 de l'IP), `envois` INTEGER | Anti-doublon par adresse | À la fermeture |

**Clé des empreintes d'IP** : 32 octets aléatoires dans un fichier séparé `cle-ip` du dossier de données (mode 0600), créé au premier démarrage, **hors de la base**, et supprimé à la fermeture (R4). Une sauvegarde de la base ne contient donc jamais la clé avec les empreintes. Ce fichier n'entre dans aucune sauvegarde (§12).

Mode WAL, `busy_timeout` de 5 s, une seule connexion d'écriture. L'écriture d'une réponse (réponse, pseudo, jeton, compteur IP) est une seule transaction. Le service tourne avec `umask 077` : base, `-wal`, `-shm` et `cle-ip` en 0600, dossier de données en 0700, propriété de l'utilisateur du service.

## 6. Anti-doublon, limitation de débit, champ piège

- **Jeton** : un jeton déjà présent dans `jetons` donne 409 `{"deja_recu": true, "stats": …}` ; le front affiche alors l'écran de fin normalement. Cela couvre aussi la double soumission et le nouvel essai après coupure réseau.
- **Adresse** : au plus `UX_MAX_PAR_IP` envois acceptés par empreinte d'IP (3 par défaut, pour les foyers et les réseaux mobiles partagés), sinon 429. L'IP en clair n'est jamais écrite, ni en base ni dans les journaux, et l'empreinte n'est jamais exportée (R4).
- **Limitation de débit**, en mémoire : `POST /api/reponses` 10 par heure, `GET /api/stats` 60 par minute, autres routes hors `/static/` 120 par minute, `/static/` non limité (fichiers embarqués, servis depuis la mémoire) ; au-delà, 429 avec `Retry-After`. Le limiteur est indexé par un HMAC de l'IP avec une **clé aléatoire propre au processus**, tirée au démarrage et jamais écrite, pour qu'il marche encore après l'effacement de `cle-ip`. Plafond de 1 000 entrées suivies, les plus anciennes oubliées d'abord.
- **IP du client** : `UX_PROXY_DE_CONFIANCE` est **obligatoire**. Si la connexion vient de cette adresse ou de ce CIDR, l'IP du client est la **dernière** adresse de `X-Forwarded-For` (celle que le proxy a ajoutée) ; sinon, l'adresse de la connexion. La valeur `aucun` (service exposé sans proxy, ou développement local) fait ignorer l'en-tête. Sans cette variable, le service refuse de démarrer : derrière un proxy, tous les répondants auraient l'adresse du proxy, et le quatrième recevrait 429.
- **Champ piège** : `site_web` non vide donne la même réponse 201 qu'un envoi accepté, sans rien stocker, pour ne pas renseigner le robot.
- **Origine** : un `POST` dont l'en-tête `Origin` diffère de `UX_ORIGINE` est refusé (403). Avec l'absence de cookie et le `Content-Type` JSON exigé, cela suffit contre les envois intersites.

## 7. API

| Méthode et chemin | Réponse |
|---|---|
| `GET /` | `index.html` (pendant le questionnaire comme après la fermeture) |
| `GET /donnees` | `donnees.html`, valeurs de configuration remplacées (R5, R8) |
| `GET /static/…` | CSS, JS, `questionnaire.json`, visuels ; types MIME explicites |
| `GET /api/etat` | `{"ouvert": true, "fermeture": "…", "effacement": "… (calculée)", "mention_maj": "…", "seuil": 10, "version": "…"}` |
| `POST /api/reponses` | 201 `{"stats": …}` ; 400 invalide ; 403 origine ; 409 version, ou `{"deja_recu": true, "stats": …}` ; 410 fermé ; 413 trop gros ; 429 trop d'envois |
| `GET /api/stats` | Agrégats (§8) |
| `GET /healthz` | 200 `ok`, sans accès à la base ni journal |

Toute autre route : 404. Pas de route d'export ni d'administration : ces actions passent par la ligne de commande sur le serveur (§12), donc aucune authentification à défendre en ligne.

**Fermeture** : `ouvert` et le refus 410 comparent l'heure courante à `UX_FERMETURE` à **chaque** requête, pas à un relevé périodique.

**Accès restreint** pour le test à cinq (#635) : si `UX_CODE_ACCES` est défini, toutes les routes sauf `/healthz` exigent une authentification HTTP Basic (utilisateur `test`, comparaison en temps constant). On retire la variable pour l'ouverture publique.

## 8. Écran de fin et statistiques

- Questions fermées seulement : `P1` à `P3`, `O1`, `L1`, `D1`, `D2`, les neuf cartes, `M1`. Jamais `G1`, `L2`, `C11`, `F1`, `I1`, `duree_s` ni `ordre_cartes`.
- Pour chaque question : pourcentage de chaque code parmi ceux qui y ont répondu, entier arrondi au plus proche (la somme peut différer de 100), et effectif.
- Pour `D1` : part de `comme_aujourdhui` parmi les répondants de `D1` ; puis, pour chaque section, part de chaque état et rang médian des sections gardées ou dépliables, calculés sur les répondants qui ont donné un état **à cette section** (son effectif propre, qui suit la règle de seuil par question ci-dessous).
- **Seuil (D3)** : rien n'est publié tant que le total est sous `UX_SEUIL_STATS` (10). Ensuite, une question n'est publiée que si son propre effectif atteint aussi le seuil (utile pour le thème 2, vu par moins de monde).
- Le texte sous le seuil est celui de `E1` dans `questions.md`.
- La comparaison se fait dans le navigateur : le front met ses propres réponses (en mémoire ou dans le brouillon, avant son effacement) en regard des pourcentages. Le serveur ne renvoie jamais une réponse individuelle.
- Affichage : barres horizontales en HTML et CSS (pas de bibliothèque de graphiques), la réponse du répondant signalée par le texte « Votre réponse » et pas seulement par la couleur.
- Agrégats recalculés au plus une fois par minute, mis en cache en mémoire. Après l'effacement (§12), ils viennent de l'instantané `agregats.json`, auquel `/api/stats` applique les mêmes seuils (global et par question ou section, `UX_SEUIL_STATS`) avant de le servir.

Forme de la charge, la même pour `GET /api/stats`, le 201 et le 409 :

```json
{
  "disponible": true, "total": 42, "seuil": 10,
  "questions": {
    "P1": { "effectif": 42, "codes": { "iphone": 62, "ipad": 24, "duo": 5, "plusieurs": 10 } },
    "D1": { "effectif": 12, "comme_aujourdhui": 25,
            "sections": { "favoris": { "garder": 50, "deplier": 33, "ecarter": 17, "rang_median": 2 } } }
  }
}
```

Sous le seuil global : `{"disponible": false, "seuil": 10}`, sans `total` ni autre compte. Une question sous son propre seuil est absente de `questions`.

## 9. En-têtes HTTP, journaux, mesure d'audience

En-têtes posés par le service sur **toutes** les réponses, erreurs comprises :

```text
Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer
Permissions-Policy: camera=(), microphone=(), geolocation=()
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
Cache-Control: no-store            (routes /api/ et /donnees)
```

`Strict-Transport-Security: max-age=31536000` est posé par le service quand `UX_ORIGINE` commence par `https://`, car Tailscale Funnel (§11) ne l'ajoute pas ; derrière Caddy, l'en-tête en double est sans effet. Aucun script ni style en ligne, aucun cookie, aucune ressource d'un autre domaine (polices système seulement). Le §4 dit comment le front reste compatible avec cette CSP.

**Aucune mesure d'audience** (R12) : pas d'outil d'analyse, pas de pixel, pas de bouton de réseau social, ni côté client ni à partir des journaux.

**Journaux** (`log/slog`, JSON sur la sortie standard) : méthode, chemin sans paramètres, statut, durée, taille, et pour un refus sa raison (`honeypot`, `doublon-jeton`, `limite-ip`, `debit`, `origine`). Jamais : IP, empreinte d'IP, jeton, `User-Agent`, `Referer`, corps de requête, pseudo, texte libre. Le proxy inverse suit la même règle pour ce sous-domaine (R1) : journal d'accès coupé, ou sans IP, agent utilisateur ni référent. C'est une condition du déploiement (§13), vérifiée par #635 ; il n'y a pas de repli qui garde l'IP.

## 10. Configuration

Variables d'environnement, aucun secret dans le dépôt :

| Variable | Défaut | Rôle |
|---|---|---|
| `UX_ADRESSE` | `127.0.0.1:8080` | Adresse d'écoute ; `0.0.0.0:8080` dans le conteneur, qui n'est publié que sur la boucle locale de l'hôte (§11) |
| `UX_DONNEES` | `./donnees` | Dossier de la base, de `cle-ip` et de `agregats.json` ; `/donnees` dans le conteneur, monté depuis le dossier de données propre au projet Compose |
| `UX_ORIGINE` | — (obligatoire) | Origine publique, par exemple `https://sondage.exemple.fr` |
| `UX_PROXY_DE_CONFIANCE` | — (obligatoire) | IP ou CIDR du proxy inverse, ou `aucun` (§6) |
| `UX_FERMETURE` | — (obligatoire) | Date et heure de fermeture, RFC 3339 avec décalage horaire |
| `UX_MENTION_MAJ` | — (obligatoire) | Date de dernière mise à jour de la mention |
| `UX_SEUIL_STATS` | `10` | Seuil D3 ; une valeur sous 10 est refusée |
| `UX_MAX_PAR_IP` | `3` | Envois acceptés par empreinte d'IP |
| `UX_CODE_ACCES` | vide | Mot de passe de l'accès restreint, vide en public |

La **date d'effacement** n'est pas une variable : elle vaut toujours `UX_FERMETURE` + 2 mois (même jour du mois, ou dernier jour du mois s'il n'existe pas), comme le dit la mention. `ux-survey effacer` permet d'effacer plus tôt à la main (§12).

Le service refuse de démarrer si une variable obligatoire manque ou est invalide, ou si `questionnaire.json` est invalide.

**Valeurs dans les textes (R5)** : une valeur est un motif `\{[a-z_]+\}` ; les seules connues sont `{date_fermeture}`, `{date_effacement}`, `{date_mise_a_jour}` et `{seuil_statistiques}`, toutes issues de `donnees.md`. Au démarrage, le serveur les remplace dans `donnees.html` et dans `index.html`, qui porte le paragraphe au-dessus de `I1` repris de `donnees.md` §1, puis sert ces deux pages depuis la mémoire. `questionnaire.json` n'est pas traité : `questions.md` ne contient aucune valeur. Les dates sont écrites en français (« 15 décembre 2026 », table des mois dans le code). Les pages marchent donc sans JavaScript, et la mention affiche toujours les dates appliquées. Un motif inconnu, ou qui reste après remplacement, empêche le démarrage.

## 11. Déploiement

**Contrainte** : le VPS est en France (UE) ; le service, la base, les sauvegardes et les exports n'en sortent pas, hors l'export d'analyse anonymisé décrit en §12.

**Hôte** : Ubuntu 24.04 LTS, Docker Engine et Docker Compose. Une autre application tourne déjà sur le même hôte : le questionnaire est un **projet Compose à part** (son propre nom de projet, son propre réseau, son propre dossier de données), sans rien partager avec elle. Aucune variante sans conteneur n'est prévue.

**Conteneur** : `deploy/Dockerfile` en deux étapes, compilation `CGO_ENABLED=0` pour l'architecture de l'hôte, image finale `gcr.io/distroless/static` en utilisateur non root, volume `/donnees` (dossier de l'hôte en 0700, propriété de l'utilisateur du conteneur), système de fichiers en lecture seule, `cap_drop: [ALL]`, `no-new-privileges`. `deploy/compose.yaml` :
- fixe `UX_ADRESSE=0.0.0.0:8080` dans le conteneur et publie le port **seulement sur `127.0.0.1`**, sur un port libre de l'hôte choisi au déploiement (`127.0.0.1:<port>:8080`), jamais sur une interface publique ;
- déclare un réseau à sous-réseau fixe (par exemple `172.31.250.0/24`, à choisir pour ne pas chevaucher celui de l'autre application) ;
- fixe `UX_PROXY_DE_CONFIANCE` à l'adresse de la passerelle de ce réseau : un client de l'hôte qui se connecte à `127.0.0.1:<port>` arrive dans le conteneur depuis cette passerelle, quel que soit ce client (Tailscale Funnel ou Caddy, ci-dessous).

**Exposition publique** : Tailscale Funnel, décision du PO du 9 novembre 2026. Les répondants ouvrent une adresse publique en `https` sans rien installer ; seul le VPS utilise Tailscale, et l'autre application de l'hôte reste privée. Aucun port public n'est ouvert. L'option (b) ne sert qu'en secours, si la vérification du §13 échoue. Les deux options passent par le port de boucle locale, donc la même configuration du service :

| Option | Ce qui est exposé | TLS | URL | `UX_ORIGINE` | Adresse du client |
|---|---|---|---|---|---|
| (a) **Tailscale Funnel**, retenue | Funnel devant `127.0.0.1:<port>`, aucun port à ouvrir | Terminé sur le VPS par `tailscaled` | Publique en `*.ts.net`, pas de sous-domaine | L'URL Funnel | Transmise par Funnel dans un en-tête, **à vérifier** (§13) |
| (b) Proxy inverse, par exemple Caddy, en secours | Ports 80 et 443 ouverts | Caddy (Let's Encrypt) | Sous-domaine | `https://<sous-domaine>` | `X-Forwarded-For` ajouté par Caddy |

Pour (b), `deploy/Caddyfile.exemple` fixe TLS automatique, `X-Forwarded-For` ajouté, corps limité à 32 Ko et journal d'accès coupé. Pour (a), le README donne la commande Funnel vers `127.0.0.1:<port>` et rappelle la vérification du §13. Dans les deux cas, le service ne lit que la dernière adresse de `X-Forwarded-For` (§6) ; si la vérification montre que Funnel transmet l'adresse du client dans un autre en-tête, #634 ajoute une variable `UX_EN_TETE_CLIENT` (nom de l'en-tête, lu seulement depuis le proxy de confiance) plutôt que de deviner.

**Étapes** :
1. Vérifier que `web/visuels/` correspond aux visuels finaux de #632 et que les tests passent.
2. Construire l'image sur l'hôte (`docker compose build`), renseigner les variables, démarrer (`docker compose up -d`), et vérifier que le port n'écoute que sur `127.0.0.1` (`ss -ltn`).
3. Vérifier `/healthz` et les en-têtes (`curl -I`). Envoyer **deux réponses depuis deux adresses publiques différentes** (un ordinateur, puis un téléphone en réseau mobile) : les deux sont acceptées, puis un troisième envoi du même téléphone avec un autre navigateur est accepté aussi (même empreinte, sous la limite), puis un quatrième depuis l'ordinateur, accepté lui aussi : chaque adresse reste sous sa limite de 3, alors qu'un compteur unique pour le proxy aurait refusé ce quatrième envoi (429). Cela prouve que le service voit des adresses de client distinctes, avec l'option d'exposition retenue. Si les quatre envois partagent un compteur, ne pas ouvrir : voir le §13. Puis remettre la base à zéro.
4. Test à cinq avec `UX_CODE_ACCES`, puis base remise à zéro (supprimer la base et `cle-ip`).
5. Ouverture : retirer `UX_CODE_ACCES`, fixer `UX_FERMETURE` à deux semaines (la date d'effacement suit, deux mois après), redémarrer.

## 12. Exports, fermeture et effacement

**Sauvegarde** : `ux-survey sauvegarder <fichier>` écrit une copie cohérente de la base par `VACUUM INTO`, en 0600. C'est la seule sauvegarde prise en charge ; `cle-ip` n'y entre jamais. Si le VPS a ses propres sauvegardes, elles excluent **toujours** `cle-ip` ; si cette exclusion d'un seul fichier n'est pas possible, elles excluent tout le dossier de données. Les sauvegardes du VPS qui contiennent la base sont purgées à la date d'effacement (§13).

**Exports**, lancés sur le serveur par `ux-survey export --format <format> --sortie <fichier>` :

| Format | Contenu | Destinataires | Durée de vie |
|---|---|---|---|
| `analyse` (CSV et JSON) | Export d'analyse anonymisé (R9) : une ligne par réponse, colonnes ci-dessous, textes libres compris, **sans pseudo**, sans empreinte ni jeton. L'`identifiant` est aléatoire, sans lien calculable avec le pseudo ; la table `pseudos` est la correspondance et ne sort jamais du serveur | L'équipe et l'assistant d'analyse, après relecture des textes libres (R10) | Supprimé à la date d'effacement |
| `agregats` (CSV et JSON) | Résultats d'ensemble (R11) : la charge du §8 pour les questions fermées, effectifs et pourcentages ; une question dont l'effectif est sous **5** est omise, et pour `D1`, une section à laquelle moins de 5 répondants ont donné un état est omise (effectif propre à la section, pas le nombre de répondants qui ont trié) ; aucun texte libre, pseudo ni identifiant | Publication | Le seul jeu de données gardé après l'effacement |
| `pseudos` | `identifiant` et pseudo, pour traiter une demande de droits (R7) seulement | Bruno seul, jamais partagé | Supprimé dès la demande traitée |

Colonnes de l'export d'analyse : `identifiant`, `recue_le`, `version`, `duree_s`, puis les identifiants du §2 dans l'ordre (`P1` à `P3`, `O1`, `G1`, `L1`, `L2`, `D1`, `D2`, les neuf cartes, `C11`, `M1`, `F1` ; sans `C08`). Il n'y a pas de colonne `D1` : à sa place viennent `D1_comme_aujourdhui` puis, pour chacune des neuf sections dans l'ordre de `questions.md`, `D1_<code>_etat` et `D1_<code>_rang` (19 colonnes). Viennent ensuite `ordre_cartes` et une colonne `textes_relus`, vide à l'export. CSV en UTF-8 avec BOM, RFC 4180 ; toute cellule qui commence par `=`, `+`, `-`, `@`, tabulation ou retour chariot est préfixée d'une apostrophe (injection de formules). Chaque fichier porte sa date de génération dans son nom.

**Relecture des textes libres (R10)** : le PO relit `G1`, `L2`, `C11` et `F1` dans une copie de l'export d'analyse, retire les détails identifiants, et inscrit `oui` dans `textes_relus` pour chaque ligne relue. Seule cette copie relue est partagée. Les réponses sur le serveur ne sont pas modifiées.

**Droits d'un répondant (R7)**, par `ux-survey pseudo` (comparaison sur `lower(trim(pseudo))`) :
- `--chercher <pseudo>` affiche les identifiants et `recue_le` des réponses de ce pseudo ;
- `--afficher <identifiant>` affiche la réponse ;
- `--corriger <identifiant> --question <ID> --valeur-json <valeur>` remplace une réponse par une valeur JSON (code, texte, ou objet `D1`), avec la validation du §5.2 ;
- `--effacer-question <identifiant> --question <ID>` retire une réponse ;
- `--effacer-pseudo <identifiant>` supprime la ligne de `pseudos` seulement ;
- `--effacer <identifiant>` supprime la réponse et sa ligne de `pseudos`.

L'identité du demandeur est vérifiée par MP sur son compte HFR (`donnees.md`). Une correction ou un effacement avant la date d'effacement est suivi d'un nouvel export d'analyse, et le PO demande aux destinataires de remplacer leur copie ; la demande est notée (date, identifiant, sans pseudo) sur la page de suivi privée du PO.

**À la fermeture**, automatiquement, au premier passage de la tâche horaire après `UX_FERMETURE` (le refus 410 est, lui, immédiat, §7) : le service supprime `cle-ip`, vide `empreintes_ip` et `jetons`, puis lance `VACUUM` et `PRAGMA wal_checkpoint(TRUNCATE)`. Si le point de contrôle répond « occupé », la fermeture n'est pas annoncée comme faite et la tâche horaire la reprend (étapes sans effet si déjà faites) jusqu'à un point de contrôle réussi avec un `-wal` vide. `ux-survey fermer` fait la même chose à la main et sort en erreur dans ce cas. La page affiche « Questionnaire fermé » et les statistiques finales.

**À la date d'effacement** (R6), fermeture + 2 mois, automatiquement par la tâche horaire, ou plus tôt par `ux-survey effacer`, qui **refuse** de s'exécuter avant `UX_FERMETURE` : après cette date, le 410 garantit qu'aucune réponse n'arrive après l'instantané. La procédure est **idempotente** : on peut la relancer après n'importe quelle interruption.
1. si `agregats.json` n'existe pas : écrire l'instantané (même contenu que l'export `agregats`) dans `agregats.json.tmp`, `fsync` du fichier, renommer en `agregats.json`, puis `fsync` du dossier de données, avant l'étape 2 ; s'il existe déjà, ne pas le réécrire (une reprise ne doit jamais le remplacer par des agrégats vides) ;
2. vider `reponses` et `pseudos`, et ce qui reste des tables d'anti-abus (sans effet si elles sont déjà vides) ;
3. `VACUUM`, puis `PRAGMA wal_checkpoint(TRUNCATE)` ; si le point de contrôle répond « occupé », la commande sort en erreur sans annoncer l'effacement, et la tâche horaire reprend à cette étape (les étapes 1 et 2 sont déjà acquises ou sans effet) ;
4. afficher « effacement terminé » seulement quand le point de contrôle a réussi et que le fichier `-wal` est vide.

Liste à cocher du PO le même jour, notée sur #628 avec la date :
- données du serveur effacées (sortie de `effacer`) ;
- fichiers produits par `sauvegarder` supprimés, et sauvegardes du VPS qui contiennent le dossier de données purgées ;
- exports d'analyse et copies relues supprimés sur la machine du PO ;
- exports partagés avec l'équipe et confiés à l'assistant d'analyse supprimés, confirmation demandée aux destinataires ;
- seul l'export `agregats` reste.

**Retrait final**, à la date fixée par le PO : couper Funnel pour ce port (en secours : retirer l'hôte du proxy et l'enregistrement DNS), arrêter le service, supprimer le dossier de données, et noter la date sur #628.

## 13. Points ouverts avant le déploiement

D4 est tranchée (§11). Reste, avant le déploiement (#635), pas avant la réalisation :
- **exposition** : Tailscale Funnel, retenue le 9 novembre 2026 ;
- pour Funnel : **vérifier sur l'hôte**, avant l'ouverture, quel en-tête Funnel transmet avec l'adresse publique du client, et que l'étape 3 du §11 voit des adresses distinctes. Si Funnel ne transmet pas l'adresse du client, le PO choisit entre (b) et un anti-doublon sans limite par adresse (jeton et limitation de débit seulement), à noter sur #628. Vérifier aussi ce que `tailscaled` journalise des connexions Funnel (R1) ; la mention sur les données (#669) dit déjà que les connexions transitent par les relais de Tailscale ;
- seulement si l'on bascule en secours sur (b) : sous-domaine et accès DNS ;
- journal d'accès de l'option retenue pour ce questionnaire coupé, ou sans IP, agent utilisateur ni référent (R1) : c'est une **exigence** du déploiement, pas une option ; si elle ne peut pas être tenue, c'est `donnees.md` (#669) qui doit changer avant l'ouverture ;
- sauvegardes du VPS : `cle-ip` en est exclu (exigence), sinon tout le dossier de données du questionnaire ; et comment purger celles qui contiennent la base à la date d'effacement.

## 14. Tests que UX-10 doit écrire

Chaque test échoue sans le code qu'il couvre (LESSONS 2).

| # | Test | Vérifie |
|---|---|---|
| 1 | Concordance | `questionnaire.json` et `questions.md` : identifiants, codes, libellés, détails, aides, conditions, ordre ; bloc `D1` lu par ses quatre lignes ; `C08` absent du JSON ; identifiants du §2 présents hors `C08` |
| 2 | Contenu | Codes en ASCII minuscules, uniques par question ; neuf cartes ; chaque visuel référencé existe et `web/visuels/` est identique à `docs/ux/questionnaire/visuels/` |
| 3 | Conditions serveur | `P1` vaut `ipad`, `duo`, `plusieurs` : `D1` et `D2` gardés ; `iphone` ou absent : retirés ; `G1` et `L2` gardés quels que soient le profil et la réponse à `L1` |
| 4 | Conditions front (node) | Liste des écrans selon `P1`, avec l'écran `G1` toujours entre `O1` et `L1` ; changement de `P1` qui efface `D1` et `D2` ; `L2` actif sans `L1` |
| 5 | Mélange et `D1` (node) | L'ordre des cartes est une permutation des neuf cartes et reste stable après rechargement du brouillon ; trier `D1` puis cocher « comme aujourd'hui » produit `{"comme_aujourdhui": true}` seul, et le décocher rend le tri |
| 6 | Validation | Clé inconnue (dont `C08`), code ou type inconnu, texte trop long (`G1` à 281 caractères compris), corps trop gros ; `D1` avec `comme_aujourdhui` et des sections, rangs en double ou non contigus, rang sur une section écartée : refus, aucune ligne |
| 7 | Enregistrement | Un envoi valide : une ligne dans `reponses` avec un identifiant aléatoire, le pseudo seulement dans `pseudos`, `recue_le` sans heure |
| 8 | Doublon par jeton | Deuxième envoi du même jeton : 409 `deja_recu`, toujours une seule ligne |
| 9 | Doublon par adresse | Quatrième envoi d'une même IP : 429 ; la base ne contient pas l'IP en clair ; deux clés donnent deux empreintes ; la clé n'est pas dans le fichier SQLite |
| 10 | Proxy | Démarrage refusé sans `UX_PROXY_DE_CONFIANCE` ; `X-Forwarded-For` ignoré avec `aucun` ou d'une connexion hors du proxy ; derrière le proxy, deux clients aux IP différentes ont deux compteurs distincts |
| 11 | Champ piège | `site_web` rempli : 201, aucune ligne |
| 12 | Débit | Au-delà de la limite : 429 avec `Retry-After` ; le limiteur marche encore après la fermeture |
| 13 | Origine | `POST` d'une autre origine : 403 |
| 14 | Statistiques | 9 réponses : `{"disponible": false, "seuil": 10}` sans compte ; 10 : publiées, à la forme du §8 ; question sous le seuil absente ; arrondis ; aucune clé de texte libre (`G1`, `L2`, `C11`, `F1`), de pseudo, de durée ni d'ordre |
| 15 | Fermeture | Une seconde après `UX_FERMETURE` : 410 au `POST`, `ouvert` faux ; après la tâche : `cle-ip` absent, `empreintes_ip` et `jetons` vides |
| 16 | Exports | Format `analyse` : colonnes et ordre, colonne `G1` entre `O1` et `L1`, `D1` aplati, `textes_relus` présente, injection de formule neutralisée, aucun pseudo ni empreinte ; format `agregats` : aucun texte libre, pseudo ni identifiant, une question à 4 répondants absente, et une section de `D1` à laquelle 4 répondants seulement ont donné un état absente même si 10 ont trié |
| 17 | Effacement | Après `effacer` : `reponses` et `pseudos` vides, `-wal` vide, `agregats.json` écrit et servi par `/api/stats` ; `effacer` refusé avant `UX_FERMETURE` ; `effacer` lancé deux fois (et une reprise après un point de contrôle occupé simulé) : `agregats.json` garde les totaux d'avant l'effacement |
| 18 | Droits | `pseudo --chercher` trouve les réponses d'un pseudo sans la casse ni les espaces ; `--corriger` valide la valeur, objet `D1` compris ; `--effacer-question` retire une seule réponse ; `--effacer-pseudo` et `--effacer` touchent la seule réponse visée et laissent les autres |
| 19 | Configuration | `UX_SEUIL_STATS` sous 10 refusé ; date d'effacement = fermeture + 2 mois (dont un 31 décembre qui donne le 28 ou 29 février) ; `/donnees` et `/` affichent les dates et ne contiennent plus rien qui corresponde à `\{[a-z_]+\}` |
| 20 | En-têtes | Les en-têtes du §9 sur une page, une route API, une 404 et une 429 ; HSTS présent avec une `UX_ORIGINE` en `https://`, absent sinon |
| 21 | Journaux | Un envoi avec un pseudo et l'IP `203.0.113.7` : le journal capturé ne contient ni l'un ni l'autre, ni le texte de `G1` ou des autres textes libres, ni l'agent utilisateur |
| 22 | Poids, domaines, CSP | `web/` hors `visuels/` pèse 200 Ko au plus ; aucune URL absolue vers un autre domaine ; aucun `innerHTML`, `insertAdjacentHTML`, attribut `style` ni `on…=` dans `web/` |
| 23 | Accès restreint | Avec `UX_CODE_ACCES` : 401 sans authentification, 200 avec ; `/healthz` toujours ouvert |

À vérifier à la main pendant le test à cinq : parcours complet au lecteur d'écran (VoiceOver sur iPhone), tri de `D1` aux boutons seuls, mode sombre, texte agrandi à 200 %, rechargement en cours de parcours, connexion lente, barres visibles sur l'écran de fin.

## 15. Exigences de `donnees.md`

| Exigence | Où |
|---|---|
| R1 journaux du service et du proxy sans IP | §9, §13 |
| R2 aucun cookie | §4, §9 |
| R3 brouillon effacé après l'envoi | §4 |
| R4 empreinte jamais exportée, clé détruite à la fermeture | §5.3, §6, §12 |
| R5 date d'effacement calculée (fermeture + 2 mois), date de mise à jour configurée, toutes deux affichées | §10 |
| R6 effacement de tout, sauvegardes et exports compris | §12 |
| R7 retrouver, corriger, effacer les réponses d'un pseudo | §12 |
| R8 mention servie par le formulaire, brouillon gardé | §4, §7 |
| R9 export d'analyse anonymisé, correspondance sur le serveur | §5.3, §12 |
| R10 textes libres relus, trace dans l'export | §12 |
| R11 export d'ensemble, seul gardé, groupes de moins de 5 omis | §12 |
| R12 aucune mesure d'audience | §9 |

