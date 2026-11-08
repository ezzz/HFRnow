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

D4 (description du VPS) reste en partie ouverte : la spécification est portable, et la [section 13](#13-ce-que-le-po-doit-fournir-d4) liste ce que le PO doit fournir. Les exigences R1 à R12 de `donnees.md` (#630, #669) sont reprises ; la [section 15](#15-exigences-de-donneesmd) dit où.

## 1. Choix techniques

| Élément | Choix | Raison |
|---|---|---|
| Service | Un binaire **Go**, bibliothèque standard (`net/http`, `embed`, `log/slog`, `crypto/hmac`, `crypto/rand`) | Un seul exécutable, front compris ; aucun interpréteur sur le VPS ; serveur HTTP prévu pour la production ; compile vers Linux x86-64 et arm64 depuis n'importe quel poste |
| Base | **SQLite**, pilote `modernc.org/sqlite` (Go pur, sans cgo) | Un fichier ; c'est la **seule dépendance tierce**, épinglée dans `go.sum`, soumise à la revue de dépendances. Sauvegarde par `ux-survey sauvegarder` seulement (§12), jamais par copie du fichier pendant que le service tourne |
| Front | HTML, CSS et JavaScript sans framework ni étape de build, servis par le binaire | Tient sous 200 Ko ; rien à charger d'un autre domaine ; relisible en revue de sécurité |
| Livraison | Image conteneur **ou** binaire avec unité systemd, au choix du PO (D4) | Les deux sont décrits en [section 11](#11-déploiement) |
| Tests | `go test` pour le service ; `node --test` (exécuteur intégré à Node, sans paquet) pour la logique pure du front | Aucune dépendance de test supplémentaire |

Écartés : Python (le serveur `http.server` n'est pas prévu pour la production, un framework ajoute des dépendances), Node côté serveur (dépendances npm et un runtime à maintenir sur le VPS), un outil de sondage tiers (décision 1 du plan : formulaire maison).

La version de Go est la dernière stable au moment de #634, épinglée dans `go.mod` et dans le `Dockerfile`.

## 2. Arborescence de `tooling/ux-survey/`

```text
tooling/ux-survey/
  README.md                  lancer, configurer, déployer, retirer (reprend §10 à §12), variante nginx
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
  deploy/ux-survey.service   unité systemd, avec ux-survey.env.exemple
  deploy/Caddyfile.exemple   la variante nginx est un paragraphe du README
```

Un fichier par type ou par responsabilité. `web/` est embarqué par `embed`, qui ne lit pas hors du module : les visuels sont donc **copiés et versionnés** dans `web/visuels/`, et le test 2 vérifie qu'ils sont identiques octet pour octet à ceux de `docs/ux/questionnaire/visuels/`.

Une tâche CI dédiée lance `go vet`, `go test` et `node --test`. Elle est filtrée sur `tooling/ux-survey/**`, `docs/ux/questionnaire/questions.md`, `docs/ux/questionnaire/donnees.md` et `docs/ux/questionnaire/visuels/**`, pour qu'une correction de libellé dans le document relance le test de concordance.

## 3. Contenu : `questionnaire.json`

Le fichier transcrit `docs/ux/questionnaire/questions.md` (#629) sans rien inventer : identifiants, codes, libellés, aides, détails et conditions identiques, même ordre. Les codes cités ici viennent de `questions.md` à la date de ce document ; en cas d'écart, **`questions.md` fait foi**.

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
    "L2": { "type": "texte", "libelle": "…", "max": 280, "condition": { "repondue": "L1" } },
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

**Test de concordance** (contrat §3.2). Un test Go trouve la racine du dépôt en remontant jusqu'au dossier qui contient `.git` (le `go test` s'exécute dans le dossier du paquet), lit `docs/ux/questionnaire/questions.md`, découpe les blocs `### <ID>` et compare avec `questionnaire.json` :
- ligne `- Réponses :` d'une question à choix : liste `` `code` Libellé `` séparée par `·` ;
- sous-liste `- Détails :` (`L1`, et `D2` si `questions.md` en donne) : une ligne par code, `` `code` `` puis au plus trois points séparés par `·` ;
- bloc `D1`, sous-liste de `- Réponses :` à quatre lignes, chacune comparée avec sa règle :
  - `Sections :` neuf `` `code` Libellé `` séparés par `·` ;
  - `États :` `` `garder` `` · `` `deplier` `` · `` `ecarter` `` avec leurs libellés ;
  - `Ordre :` texte seul, rien à comparer ;
  - `Réponse seule :` `` `comme_aujourdhui` Laisser la barre comme aujourd'hui `` ;
- lignes `- Aide :` et `- Condition :` comparées au texte et à la condition du JSON.

Le test échoue sur tout identifiant, code, libellé ou détail absent, en trop ou différent, sur un ordre différent, sur un bloc `C08` présent dans le JSON (si `questions.md` garde un bloc `C08` marqué retiré, le test l'ignore), et sur un identifiant de `cadrage-construction.md` §2 absent (hors `C08`).

`donnees.html` transcrit la page détaillée de `donnees.md` (#630), et le paragraphe au-dessus de `I1` vient du même document ; `questions.md` garde les libellés courts du champ. Les valeurs entre accolades de `donnees.md` (`{date_fermeture}`, `{date_effacement}`, `{date_mise_a_jour}`, `{seuil_statistiques}`) restent telles quelles dans les fichiers et sont remplacées par le serveur (§10).

## 4. Parcours côté navigateur

- **Une page, un écran par bloc** de `cadrage-construction.md` §2, une barre de progression (`<progress>` avec texte « Étape n sur m »), boutons « Précédent » et « Suivant ». Le changement d'écran met le focus sur le titre de l'écran.
- **Tout est facultatif** : « Suivant » est toujours actif. Chaque question répondue a un bouton « Effacer ma réponse », puisqu'un bouton radio ne se décoche pas.
- **Conditions** :
  - les écrans `D1` et `D2` s'affichent seulement si `P1` vaut `ipad`, `duo` ou `plusieurs` ; `P1` sans réponse les masque ; si `P1` change vers une autre valeur, `D1` et `D2` sont effacés du brouillon ;
  - `L2` est actif seulement si `L1` a une réponse, et effacé si `L1` est effacé ;
  - la barre de progression recalcule le nombre d'étapes.
- **`L1` avec détails** : chaque réponse est un bouton radio dont le libellé est le titre court, suivi d'une liste `<ul>` d'au plus trois points, reliée au bouton par `aria-describedby`. Même rendu pour toute question dont les réponses ont des détails.
- **Cartes** : les neuf cartes de `cartes` sont mélangées une fois par répondant (Fisher-Yates sur `crypto.getRandomValues`), l'ordre est gardé dans le brouillon et envoyé avec la réponse. La mention « pistes à l'étude, pas des engagements » est en tête de l'écran. Chaque carte est un `<fieldset>` avec sa phrase en `<legend>` et trois boutons radio natifs habillés en boutons.
- **Tri `D1`** :
  - en tête, un bouton radio « Laisser la barre comme aujourd'hui » ; coché, il désactive les cartes (sans effacer ce qui y est saisi, rendu au décochage) ;
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

Une question sans réponse est absente. Une section de `D1` sans état choisi est absente de `sections`. `"D1": {"comme_aujourdhui": true}` est la réponse seule. `duree_s` est l'écart entre l'ouverture de `E0` et l'envoi, borné à 0–7200, pour vérifier le budget de 7 minutes au test à cinq.

### 5.2 Validation et normalisation côté serveur

Le serveur ne fait pas confiance au front :
- corps JSON de 16 Ko au plus, `Content-Type: application/json` exigé ;
- `version` égale à celle du contenu chargé, sinon 409 avec un message « rechargez la page » ;
- clé inconnue (dont `C08`), code inconnu ou type inattendu : 400, rien n'est stocké ;
- textes (`G1`, `L2`, `C11`, `F1`, `I1`) : normalisés NFC, caractères de contrôle retirés sauf retour à la ligne, espaces de bord retirés, longueur comptée en caractères (280, ou 40 pour `I1`) ; un texte vide devient absent ;
- `D1` :
  - `comme_aujourdhui` vrai avec une liste `sections` non vide : 400 ;
  - chaque code de section au plus une fois, état parmi `garder`, `deplier`, `ecarter` ;
  - les sections `garder` et `deplier` ont un `rang`, uniques et contigus de 1 à leur nombre ; une section `ecarter` n'en a pas ;
  - `comme_aujourdhui` faux sans aucune section : `D1` devient absent ;
- `ordre_cartes` : permutation exacte des neuf cartes, sinon ignoré ;
- **conditions**, appliquées avant stockage même si le front a envoyé les valeurs :
  - `P1` absent ou différent de `ipad`, `duo`, `plusieurs` : `D1` et `D2` retirés ;
  - `L1` absent : `L2` retiré.

### 5.3 Schéma SQLite

Les réponses ne contiennent ni IP, ni jeton, ni heure : aucune table ne relie une réponse à une adresse. Toutes les requêtes sont **paramétrées** ; aucune requête SQL n'est construite par concaténation.

| Table | Colonnes | Rôle | Vidée |
|---|---|---|---|
| `reponses` | `identifiant` TEXT PK (16 caractères hexadécimaux tirés de `crypto/rand`, sans lien avec le pseudo ni l'ordre d'arrivée), `recue_le` TEXT (date `AAAA-MM-JJ` seulement), `version` TEXT, `duree_s` INTEGER, `ordre_cartes` TEXT, `donnees` TEXT (JSON normalisé, sans `I1`) | Les réponses | Par `effacer` (§12) |
| `pseudos` | `identifiant` TEXT PK référence `reponses`, `pseudo` TEXT | Table de correspondance pseudo ↔ identifiant (R9) : elle ne quitte jamais le serveur | Par `effacer`, ou ligne par ligne par `pseudo` (§12) |
| `jetons` | `empreinte` TEXT PK (SHA-256 du jeton) | Anti-doublon par navigateur | À la fermeture |
| `empreintes_ip` | `empreinte` TEXT PK (HMAC-SHA-256 de l'IP), `envois` INTEGER | Anti-doublon par adresse | À la fermeture |

**Clé des empreintes d'IP** : 32 octets aléatoires dans un fichier séparé `cle-ip` du dossier de données (mode 0600), créé au premier démarrage, **hors de la base**, et supprimé à la fermeture (R4). Une sauvegarde de la base ne contient donc jamais la clé avec les empreintes. Ce fichier n'entre dans aucune sauvegarde (§12).

Mode WAL, `busy_timeout` de 5 s, une seule connexion d'écriture. L'écriture d'une réponse (réponse, pseudo, jeton, compteur IP) est une seule transaction. Le service tourne avec `umask 077` : base, `-wal`, `-shm` et `cle-ip` en 0600, dossier de données en 0700, propriété de l'utilisateur du service.

## 6. Anti-doublon, limitation de débit, champ piège

- **Jeton** : un jeton déjà présent dans `jetons` donne 409 `{"deja_recu": true, "stats": …}` ; le front affiche alors l'écran de fin normalement. Cela couvre aussi la double soumission et le nouvel essai après coupure réseau.
- **Adresse** : au plus `UX_MAX_PAR_IP` envois acceptés par empreinte d'IP (3 par défaut, pour les foyers et les réseaux mobiles partagés), sinon 429. L'IP en clair n'est jamais écrite, ni en base ni dans les journaux, et l'empreinte n'est jamais exportée (R4).
- **Limitation de débit**, en mémoire : `POST /api/reponses` 10 par heure, `GET /api/stats` 60 par minute, autres routes 120 par minute ; au-delà, 429 avec `Retry-After`. Le limiteur est indexé par un HMAC de l'IP avec une **clé aléatoire propre au processus**, tirée au démarrage et jamais écrite, pour qu'il marche encore après l'effacement de `cle-ip`. Plafond de 1 000 entrées suivies, les plus anciennes oubliées d'abord.
- **IP du client** : `UX_PROXY_DE_CONFIANCE` est **obligatoire**. Si la connexion vient de cette adresse ou de ce CIDR, l'IP du client est la **dernière** adresse de `X-Forwarded-For` (celle que le proxy a ajoutée) ; sinon, l'adresse de la connexion. La valeur `aucun` (service exposé sans proxy, ou développement local) fait ignorer l'en-tête. Sans cette variable, le service refuse de démarrer : derrière un proxy, tous les répondants auraient l'adresse du proxy, et le quatrième recevrait 429.
- **Champ piège** : `site_web` non vide donne la même réponse 201 qu'un envoi accepté, sans rien stocker, pour ne pas renseigner le robot.
- **Origine** : un `POST` dont l'en-tête `Origin` diffère de `UX_ORIGINE` est refusé (403). Avec l'absence de cookie et le `Content-Type` JSON exigé, cela suffit contre les envois intersites.

## 7. API

| Méthode et chemin | Réponse |
|---|---|
| `GET /` | `index.html` (pendant le questionnaire comme après la fermeture) |
| `GET /donnees` | `donnees.html`, valeurs de configuration remplacées (R5, R8) |
| `GET /static/…` | CSS, JS, `questionnaire.json`, visuels ; types MIME explicites |
| `GET /api/etat` | `{"ouvert": true, "fermeture": "…", "effacement": "…", "mention_maj": "…", "seuil": 10, "version": "…"}` |
| `POST /api/reponses` | 201 `{"stats": …}` ; 400 invalide ; 403 origine ; 409 version, ou `{"deja_recu": true, "stats": …}` ; 410 fermé ; 413 trop gros ; 429 trop d'envois |
| `GET /api/stats` | Agrégats (§8) |
| `GET /healthz` | 200 `ok`, sans accès à la base ni journal |

Toute autre route : 404. Pas de route d'export ni d'administration : ces actions passent par la ligne de commande sur le serveur (§12), donc aucune authentification à défendre en ligne.

**Fermeture** : `ouvert` et le refus 410 comparent l'heure courante à `UX_FERMETURE` à **chaque** requête, pas à un relevé périodique.

**Accès restreint** pour le test à cinq (#635) : si `UX_CODE_ACCES` est défini, toutes les routes sauf `/healthz` exigent une authentification HTTP Basic (utilisateur `test`, comparaison en temps constant). On retire la variable pour l'ouverture publique.

## 8. Écran de fin et statistiques

- Questions fermées seulement : `P1` à `P3`, `O1`, `L1`, `D1`, `D2`, les neuf cartes, `M1`. Jamais `G1`, `L2`, `C11`, `F1`, `I1`, `duree_s` ni `ordre_cartes`.
- Pour chaque question : pourcentage de chaque code parmi ceux qui y ont répondu, entier arrondi au plus proche (la somme peut différer de 100), et effectif.
- Pour `D1` : part de `comme_aujourdhui` parmi les répondants de `D1` ; puis, parmi ceux qui ont trié, pour chaque section, part de chaque état et rang médian des sections gardées ou dépliables.
- **Seuil (D3)** : rien n'est publié tant que le total est sous `UX_SEUIL_STATS` (10). Ensuite, une question n'est publiée que si son propre effectif atteint aussi le seuil (utile pour le thème 2, vu par moins de monde).
- Le texte sous le seuil est celui de `E1` dans `questions.md`.
- La comparaison se fait dans le navigateur : le front met ses propres réponses (en mémoire ou dans le brouillon, avant son effacement) en regard des pourcentages. Le serveur ne renvoie jamais une réponse individuelle.
- Affichage : barres horizontales en HTML et CSS (pas de bibliothèque de graphiques), la réponse du répondant signalée par le texte « Votre réponse » et pas seulement par la couleur.
- Agrégats recalculés au plus une fois par minute, mis en cache en mémoire. Après l'effacement (§12), ils viennent de l'instantané `agregats.json`.

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

HSTS est posé par le proxy inverse qui termine TLS, pas par le service. Aucun script ni style en ligne, aucun cookie, aucune ressource d'un autre domaine (polices système seulement). Le §4 dit comment le front reste compatible avec cette CSP.

**Aucune mesure d'audience** (R12) : pas d'outil d'analyse, pas de pixel, pas de bouton de réseau social, ni côté client ni à partir des journaux.

**Journaux** (`log/slog`, JSON sur la sortie standard) : méthode, chemin sans paramètres, statut, durée, taille, et pour un refus sa raison (`honeypot`, `doublon-jeton`, `limite-ip`, `debit`, `origine`). Jamais : IP, empreinte d'IP, jeton, `User-Agent`, `Referer`, corps de requête, pseudo, texte libre. Le proxy inverse suit la même règle pour ce sous-domaine : journal d'accès coupé, ou sans IP ni agent utilisateur ni référent ; à défaut, IP effacée au bout de 7 jours au plus (R1), et la mention le dit.

## 10. Configuration

Variables d'environnement, aucun secret dans le dépôt :

| Variable | Défaut | Rôle |
|---|---|---|
| `UX_ADRESSE` | `127.0.0.1:8080` | Adresse d'écoute ; `0.0.0.0:8080` dans le conteneur (§11) |
| `UX_DONNEES` | `./donnees` | Dossier de la base, de `cle-ip` et de `agregats.json` ; `/var/lib/ux-survey` avec systemd, `/donnees` dans le conteneur |
| `UX_ORIGINE` | — (obligatoire) | Origine publique, par exemple `https://sondage.exemple.fr` |
| `UX_PROXY_DE_CONFIANCE` | — (obligatoire) | IP ou CIDR du proxy inverse, ou `aucun` (§6) |
| `UX_FERMETURE` | — (obligatoire) | Date et heure de fermeture, RFC 3339 avec décalage horaire |
| `UX_EFFACEMENT` | fermeture + 2 mois | Date de l'effacement (§12) ; refusée si postérieure à fermeture + 2 mois |
| `UX_MENTION_MAJ` | — (obligatoire) | Date de dernière mise à jour de la mention |
| `UX_SEUIL_STATS` | `10` | Seuil D3 ; une valeur sous 10 est refusée |
| `UX_MAX_PAR_IP` | `3` | Envois acceptés par empreinte d'IP |
| `UX_CODE_ACCES` | vide | Mot de passe de l'accès restreint, vide en public |

Le service refuse de démarrer si une variable obligatoire manque ou est invalide, ou si `questionnaire.json` est invalide.

**Valeurs dans les textes (R5)** : au démarrage, le serveur remplace `{date_fermeture}`, `{date_effacement}`, `{date_mise_a_jour}` et `{seuil_statistiques}` dans `donnees.html`, `index.html` et `questionnaire.json`, puis les sert depuis la mémoire. Les dates sont écrites en français (« 15 décembre 2026 », table des mois dans le code). Les pages marchent donc sans JavaScript, et la mention affiche toujours les dates appliquées. Une accolade de valeur qui reste après remplacement empêche le démarrage.

## 11. Déploiement

**Contrainte** : le VPS est en France (UE) ; le service, la base, les sauvegardes et les exports n'en sortent pas, hors l'export d'analyse anonymisé décrit en §12.

**Conteneur** : `deploy/Dockerfile` en deux étapes, compilation `CGO_ENABLED=0`, image finale `gcr.io/distroless/static` en utilisateur non root, volume `/donnees`, système de fichiers en lecture seule. `deploy/compose.yaml` fixe `UX_ADRESSE=0.0.0.0:8080` dans le conteneur et publie le port sur `127.0.0.1:8080` seulement ; il déclare un réseau à sous-réseau fixe (par exemple `172.31.250.0/24`) et `UX_PROXY_DE_CONFIANCE` à l'adresse de sa passerelle, par laquelle arrive le proxy de l'hôte.

**Binaire** : `GOOS=linux GOARCH=<amd64|arm64> go build`, copie dans `/opt/ux-survey/`, unité `deploy/ux-survey.service` avec `DynamicUser=yes`, `StateDirectory=ux-survey`, `StateDirectoryMode=0700`, `UMask=0077`, `ProtectSystem=strict`, `ProtectHome=yes`, `NoNewPrivileges=yes`, `PrivateTmp=yes`, et un fichier d'environnement lisible par root seulement, dont l'exemple fixe `UX_DONNEES=/var/lib/ux-survey` et `UX_PROXY_DE_CONFIANCE=127.0.0.1`.

**Proxy inverse** : `deploy/Caddyfile.exemple` (TLS automatique, HSTS, `X-Forwarded-For` ajouté, corps limité à 32 Ko, journal d'accès coupé) ; la variante nginx est un paragraphe du README (`proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for`). Le README ne garde que la variante retenue par D4 si le PO le souhaite.

**Étapes** :
1. Vérifier que `web/visuels/` correspond aux visuels finaux de #632 et que les tests passent.
2. Construire l'image ou le binaire, renseigner les variables, démarrer.
3. Vérifier `/healthz` et les en-têtes (`curl -I`). Envoyer **deux réponses depuis deux adresses publiques différentes** (un ordinateur, puis un téléphone en réseau mobile) : les deux sont acceptées, puis un troisième envoi du même téléphone avec un autre navigateur est accepté aussi (même empreinte, sous la limite). Cela prouve que le proxy de confiance est bien réglé. Puis remettre la base à zéro.
4. Test à cinq avec `UX_CODE_ACCES`, puis base remise à zéro (supprimer la base et `cle-ip`).
5. Ouverture : retirer `UX_CODE_ACCES`, fixer `UX_FERMETURE` à deux semaines, `UX_EFFACEMENT` à deux mois après, redémarrer.

## 12. Exports, fermeture et effacement

**Sauvegarde** : `ux-survey sauvegarder <fichier>` écrit une copie cohérente de la base par `VACUUM INTO`, en 0600. C'est la seule sauvegarde prise en charge ; `cle-ip` n'y entre jamais. Si le VPS a ses propres sauvegardes, elles excluent le dossier de données, ou sont purgées à la date d'effacement (§13).

**Exports**, lancés sur le serveur par `ux-survey export --format <format> --sortie <fichier>` :

| Format | Contenu | Destinataires | Durée de vie |
|---|---|---|---|
| `analyse` (CSV et JSON) | Export d'analyse anonymisé (R9) : une ligne par réponse, colonnes ci-dessous, textes libres compris, **sans pseudo**, sans empreinte ni jeton. L'`identifiant` est aléatoire, sans lien calculable avec le pseudo ; la table `pseudos` est la correspondance et ne sort jamais du serveur | L'équipe et l'assistant d'analyse, après relecture des textes libres (R10) | Supprimé à la date d'effacement |
| `agregats` (CSV et JSON) | Résultats d'ensemble (R11) : la charge du §8 pour toutes les questions fermées, sans seuil par question, effectifs et pourcentages ; aucun texte libre, pseudo ni identifiant | Publication | Le seul jeu de données gardé après l'effacement |
| `pseudos` | `identifiant` et pseudo, pour traiter une demande de droits (R7) seulement | Bruno seul, jamais partagé | Supprimé dès la demande traitée |

Colonnes de l'export d'analyse : `identifiant`, `recue_le`, `version`, `duree_s`, puis les identifiants du §2 dans l'ordre (`P1` à `P3`, `O1`, `G1`, `L1`, `L2`, `D1`, `D2`, les neuf cartes, `C11`, `M1`, `F1` ; sans `C08`), `D1` aplati en `D1_comme_aujourdhui`, `D1_<code>_etat` et `D1_<code>_rang` pour chacune des neuf sections, `ordre_cartes`, et une colonne `textes_relus`, vide à l'export. CSV en UTF-8 avec BOM, RFC 4180 ; toute cellule qui commence par `=`, `+`, `-`, `@`, tabulation ou retour chariot est préfixée d'une apostrophe (injection de formules). Chaque fichier porte sa date de génération dans son nom.

**Relecture des textes libres (R10)** : le PO relit `G1`, `L2`, `C11` et `F1` dans une copie de l'export d'analyse, retire les détails identifiants, et inscrit `oui` dans `textes_relus` pour chaque ligne relue. Seule cette copie relue est partagée. Les réponses sur le serveur ne sont pas modifiées.

**Droits d'un répondant (R7)**, par `ux-survey pseudo` (comparaison sur `lower(trim(pseudo))`) :
- `--chercher <pseudo>` affiche les identifiants et `recue_le` des réponses de ce pseudo ;
- `--afficher <identifiant>` affiche la réponse ;
- `--corriger <identifiant> --question <ID> --valeur <code ou texte>` corrige une réponse, avec la validation du §5.2 ;
- `--effacer-pseudo <identifiant>` supprime la ligne de `pseudos` seulement ;
- `--effacer <identifiant>` supprime la réponse et sa ligne de `pseudos`.

L'identité du demandeur est vérifiée par MP sur son compte HFR (`donnees.md`). Une correction ou un effacement avant la date d'effacement est suivi d'un nouvel export d'analyse, et le PO demande aux destinataires de remplacer leur copie ; la demande est notée (date, identifiant, sans pseudo) sur la page de suivi privée du PO.

**À la fermeture**, automatiquement, au premier passage de la tâche horaire après `UX_FERMETURE` (le refus 410 est, lui, immédiat, §7) : le service supprime `cle-ip`, vide `empreintes_ip` et `jetons`, puis lance `VACUUM` et `PRAGMA wal_checkpoint(TRUNCATE)`. `ux-survey fermer` fait la même chose à la main. La page affiche « Questionnaire fermé » et les statistiques finales.

**À la date d'effacement** (R6), automatiquement par la tâche horaire, ou plus tôt par `ux-survey effacer` :
1. écrire l'instantané `agregats.json` (même contenu que l'export `agregats`), que la page sert ensuite ;
2. vider `reponses` et `pseudos`, et ce qui reste des tables d'anti-abus ;
3. `VACUUM`, puis `PRAGMA wal_checkpoint(TRUNCATE)` ; si le point de contrôle répond « occupé », la commande sort en erreur sans annoncer l'effacement, et la tâche horaire recommence ;
4. afficher « effacement terminé » seulement quand le point de contrôle a réussi et que le fichier `-wal` est vide.

Liste à cocher du PO le même jour, notée sur #628 avec la date :
- données du serveur effacées (sortie de `effacer`) ;
- fichiers produits par `sauvegarder` supprimés, et sauvegardes du VPS qui contiennent le dossier de données purgées ;
- exports d'analyse et copies relues supprimés sur la machine du PO ;
- exports partagés avec l'équipe et confiés à l'assistant d'analyse supprimés, confirmation demandée aux destinataires ;
- seul l'export `agregats` reste.

**Retrait final**, à la date fixée par le PO : arrêter le service, retirer l'hôte du proxy et l'enregistrement DNS, supprimer le dossier de données, et noter la date sur #628.

## 13. Ce que le PO doit fournir (D4)

Déjà tranché : le VPS est en France (UE). Reste à fournir avant le déploiement (#635), pas avant la réalisation :
- système et architecture du VPS (distribution, version, x86-64 ou arm64) ;
- proxy inverse déjà en place (nginx, Caddy, Traefik, Apache ou aucun) et qui gère TLS (Let's Encrypt par le proxy, ou autre) ;
- Docker et Compose disponibles, ou systemd seulement ;
- sous-domaine choisi et accès DNS ;
- politique de journalisation du proxy : peut-on couper le journal d'accès ou en retirer l'IP pour ce sous-domaine (R1) ;
- sauvegardes du VPS : le dossier de données peut-il en être exclu, sinon comment les purger à la date d'effacement.

## 14. Tests que UX-10 doit écrire

Chaque test échoue sans le code qu'il couvre (LESSONS 2).

| # | Test | Vérifie |
|---|---|---|
| 1 | Concordance | `questionnaire.json` et `questions.md` : identifiants, codes, libellés, détails, aides, conditions, ordre ; bloc `D1` lu par ses quatre lignes ; `C08` absent du JSON ; identifiants du §2 présents hors `C08` |
| 2 | Contenu | Codes en ASCII minuscules, uniques par question ; neuf cartes ; chaque visuel référencé existe et `web/visuels/` est identique à `docs/ux/questionnaire/visuels/` |
| 3 | Conditions serveur | `P1` vaut `ipad`, `duo`, `plusieurs` : `D1` et `D2` gardés ; `iphone` ou absent : retirés ; `L1` absent : `L2` retiré ; `G1` gardé quel que soit le profil |
| 4 | Conditions front (node) | Liste des écrans selon `P1`, avec l'écran `G1` toujours entre `O1` et `L1` ; changement de `P1` qui efface `D1` et `D2` ; `L2` inactif sans `L1`, effacé avec lui |
| 5 | Mélange (node) | L'ordre des cartes est une permutation des neuf cartes et reste stable après rechargement du brouillon |
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
| 16 | Exports | Format `analyse` : colonnes et ordre, colonne `G1` entre `O1` et `L1`, `D1` aplati, `textes_relus` présente, injection de formule neutralisée, aucun pseudo ni empreinte ; format `agregats` : aucun texte libre, pseudo ni identifiant |
| 17 | Effacement | Après `effacer` : `reponses` et `pseudos` vides, `-wal` vide, `agregats.json` écrit et servi par `/api/stats` |
| 18 | Droits | `pseudo --chercher` trouve les réponses d'un pseudo sans la casse ni les espaces ; `--corriger` valide la valeur ; `--effacer-pseudo` et `--effacer` touchent la seule réponse visée et laissent les autres |
| 19 | Configuration | `UX_SEUIL_STATS` sous 10 et `UX_EFFACEMENT` après fermeture + 2 mois refusés ; `/donnees` affiche les dates configurées et ne contient plus d'accolade de valeur |
| 20 | En-têtes | Les en-têtes du §9 sur une page, une route API, une 404 et une 429 |
| 21 | Journaux | Un envoi avec un pseudo et l'IP `203.0.113.7` : le journal capturé ne contient ni l'un ni l'autre, ni le texte de `G1` ou des autres textes libres, ni l'agent utilisateur |
| 22 | Poids, domaines, CSP | `web/` hors `visuels/` pèse 200 Ko au plus ; aucune URL absolue vers un autre domaine ; aucun `innerHTML`, `insertAdjacentHTML`, attribut `style` ni `on…=` dans `web/` |
| 23 | Accès restreint | Avec `UX_CODE_ACCES` : 401 sans authentification, 200 avec ; `/healthz` toujours ouvert |

À vérifier à la main pendant le test à cinq : parcours complet au lecteur d'écran (VoiceOver sur iPhone), tri de `D1` aux boutons seuls, mode sombre, texte agrandi à 200 %, rechargement en cours de parcours, connexion lente, barres visibles sur l'écran de fin.

## 15. Exigences de `donnees.md`

| Exigence | Où |
|---|---|
| R1 journaux sans IP, ou effacée sous 7 jours | §9, §13 |
| R2 aucun cookie | §4, §9 |
| R3 brouillon effacé après l'envoi | §4 |
| R4 empreinte jamais exportée, clé détruite à la fermeture | §5.3, §6, §12 |
| R5 dates d'effacement et de mise à jour configurables et affichées | §10 |
| R6 effacement de tout, sauvegardes et exports compris | §12 |
| R7 retrouver, corriger, effacer les réponses d'un pseudo | §12 |
| R8 mention servie par le formulaire, brouillon gardé | §4, §7 |
| R9 export d'analyse anonymisé, correspondance sur le serveur | §5.3, §12 |
| R10 textes libres relus, trace dans l'export | §12 |
| R11 export d'ensemble, seul gardé | §12 |
| R12 aucune mesure d'audience | §9 |

Écart signalé à #669 : la mention dit que « la date et l'heure d'envoi » sont enregistrées ; ce document ne garde que la date (`recue_le`), et les envois en rafale sont repérés par la limitation de débit, sans rien stocker. La mention doit dire « la date d'envoi ».
