# Spécification technique du formulaire

Date : 8 novembre 2026. Lot UX-09 (#633), suivi sur #628. Ce document dit comment construire le formulaire du questionnaire UX ; la réalisation (UX-10, #634) le suit sans aller-retour, la revue de sécurité (UX-11, #635) le prend comme référence.

Entrées qui font foi, dans cet ordre en cas d'écart : les issues #628 à #635, puis `cadrage-construction.md` (identifiants §2, contrats §3, contraintes §4), puis ce document. Les textes viennent de `questions.md` (#629) et `donnees.md` (#630), les visuels de `visuels/` (#632).

Décisions du PO reprises ici : D1 (réponse « comme aujourd'hui » au thème 1), D2 (pseudo à la fin), D3 (statistiques après 20 réponses). D4 (description du VPS) reste ouverte : la spécification est portable, et la [section 13](#13-ce-que-le-po-doit-fournir-d4) liste ce que le PO doit fournir.

## 1. Choix techniques

| Élément | Choix | Raison |
|---|---|---|
| Service | Un binaire **Go**, bibliothèque standard (`net/http`, `embed`, `log/slog`, `crypto/hmac`) | Un seul fichier exécutable, front compris ; aucun interpréteur à installer sur le VPS ; serveur HTTP de la bibliothèque standard prévu pour la production ; compile vers Linux x86-64 et arm64 depuis n'importe quel poste |
| Base | **SQLite**, pilote `modernc.org/sqlite` (Go pur, sans cgo) | Un fichier, sauvegarde par copie ; c'est la **seule dépendance tierce**, épinglée dans `go.sum`, soumise à la revue de dépendances |
| Front | HTML, CSS et un JavaScript sans framework ni étape de build, servis par le binaire | Tient sous 200 Ko ; rien à charger d'un autre domaine ; relisible en revue de sécurité |
| Livraison | Image conteneur **ou** binaire avec unité systemd, au choix du PO (D4) | Les deux sont décrits en [section 11](#11-déploiement) |
| Tests | `go test` pour le service ; `node --test` (exécuteur intégré à Node, sans paquet) pour la logique pure du front | Aucune dépendance de test supplémentaire |

Écartés : Python (le serveur `http.server` n'est pas prévu pour la production, un framework ajoute des dépendances), Node côté serveur (dépendances npm et un runtime à maintenir sur le VPS), un outil de sondage tiers (décision 1 du plan : formulaire maison).

La version de Go est la dernière stable au moment de #634, épinglée dans `go.mod` et dans le `Dockerfile`.

## 2. Arborescence de `tooling/ux-survey/`

```text
tooling/ux-survey/
  README.md                  lancer, configurer, déployer, retirer (reprend §10 à §12)
  go.mod, go.sum
  cmd/ux-survey/main.go      sous-commandes : serve, export, fermer, purger-pseudos
  internal/contenu/          chargement et validation de questionnaire.json
  internal/reponse/          validation, normalisation, branchement côté serveur
  internal/stockage/         SQLite : schéma, écriture, purge
  internal/stats/            agrégats de l'écran de fin
  internal/exporter/         CSV et JSON
  internal/web/              routes, en-têtes, limites de débit, journaux
  contenu/questionnaire.json transcription de questions.md (§3)
  web/                       index.html, donnees.html, app.js, logique.js, style.css
  web/visuels/               copiés depuis docs/ux/questionnaire/visuels/ (#632)
  web/logique.test.mjs       tests node du front
  deploy/Dockerfile
  deploy/compose.yaml
  deploy/ux-survey.service   unité systemd
  deploy/Caddyfile.exemple, deploy/nginx.exemple.conf
```

Un fichier par type ou par responsabilité. Le dossier `web/` est embarqué dans le binaire par `embed`. Une tâche CI dédiée, filtrée sur `tooling/ux-survey/**`, lance `go vet`, `go test` et `node --test`.

## 3. Contenu : `questionnaire.json`

Le fichier transcrit `docs/ux/questionnaire/questions.md` (#629) sans rien inventer : identifiants, codes et libellés identiques, même ordre. Les codes donnés en exemple dans ce document sont indicatifs ; **ceux de `questions.md` font foi**.

Forme (extrait illustratif) :

```json
{
  "version": "2026-11-v1",
  "ecrans": [
    { "id": "profil", "questions": ["P1", "P2", "P3"] },
    { "id": "theme2-a", "questions": ["D1"], "condition": { "P1": ["ipad", "duo", "plusieurs"] } }
  ],
  "questions": {
    "P1": { "type": "choix", "libelle": "Sur quel appareil utilisez-vous surtout l'app ?",
            "reponses": [ { "code": "iphone", "libelle": "iPhone" } ] },
    "L2": { "type": "texte", "libelle": "…", "max": 280 },
    "D1": { "type": "tri", "libelle": "…", "sections": [ { "code": "favoris", "libelle": "Favoris" } ] },
    "C01": { "type": "reaction", "libelle": "…", "reponses": [ { "code": "adore", "libelle": "J'adore" } ] }
  }
}
```

Types : `texte-seul` (`E0`, `E1`), `choix` (choix simple), `texte` (texte court), `tri` (`D1`), `reaction` (`C01` à `C10`), `pseudo` (`I1`). Les visuels sont référencés par leur nom de fichier, avec le texte alternatif de `visuels/inventaire.md`.

**Test de concordance** (contrat §3.2) : un test Go lit `../../docs/ux/questionnaire/questions.md`, découpe les blocs `### <ID>`, extrait la question, les réponses (`` `code` Libellé `` séparés par `·`) et la condition, puis compare avec `questionnaire.json`. Il échoue sur tout identifiant, code ou libellé absent, en trop ou différent, et sur un ordre différent. Il échoue aussi si un identifiant de `cadrage-construction.md` §2 manque.

`donnees.html` transcrit `donnees.md` (#630) ; le texte court au-dessus de `I1` vient du même document.

## 4. Parcours côté navigateur

- **Une page, un écran par bloc** de `cadrage-construction.md` §2, une barre de progression (`<progress>` avec texte « Étape n sur m »), boutons « Précédent » et « Suivant ». Le changement d'écran met le focus sur le titre de l'écran.
- **Tout est facultatif** : « Suivant » est toujours actif. Chaque question répondue a un bouton « Effacer ma réponse », puisqu'un bouton radio ne se décoche pas.
- **Branchement du thème 2** : les écrans `D1` et `D2` s'affichent seulement si `P1` vaut `ipad`, `duo` ou `plusieurs`. `P1` sans réponse les masque. Si le répondant revient changer `P1` vers une autre valeur, les réponses `D1` et `D2` sont effacées du brouillon. La barre de progression recalcule le nombre d'étapes.
- **Ordre des cartes** : `C01` à `C10` sont mélangées une fois par répondant (Fisher-Yates sur `crypto.getRandomValues`), l'ordre est gardé dans le brouillon et envoyé avec la réponse. La mention « pistes à l'étude, pas des engagements » est en tête de l'écran.
- **Cartes de réaction** : chaque carte est un `<fieldset>` avec sa phrase en `<legend>` et trois boutons radio natifs habillés en boutons.
- **Tri de cartes `D1`** : une liste ordonnée des neuf sections ; pour chacune, une case « Garder », une case « Dépliable » (active seulement si gardée), et deux boutons « Monter » et « Descendre » dont le nom accessible contient la section (« Monter Favoris »). Après un déplacement, une zone `aria-live="polite"` annonce « Favoris, position 2 sur 9 » et le focus reste sur le bouton utilisé. Le glisser-déposer (Pointer Events) est facultatif et ne remplace jamais les boutons.
- **Textes** : `L2`, `C11`, `F1` limités à 280 caractères, `I1` à 40, avec compteur restant annoncé discrètement.
- **Visuels** : images avec `loading="lazy"` et texte alternatif ; vidéos `preload="none"`, `muted`, `playsinline`, image d'attente, jamais en lecture automatique.
- **Brouillon** : `localStorage`, clé `ux-survey:<version>:brouillon` (réponses, écran courant, ordre des cartes, heure de début). Écrit à chaque changement, relu au chargement, effacé après un envoi accepté. Si `localStorage` est indisponible (navigation privée), le formulaire marche sans brouillon.
- **Jeton** : au premier chargement, un jeton aléatoire de 128 bits (`crypto.getRandomValues`, hexadécimal) est gardé sous `ux-survey:<version>:jeton`. Il part dans le corps de l'envoi ; aucun cookie n'est posé.
- **Envoi unique** : à la fin, après `I1`, un seul bouton « Envoyer », désactivé pendant la requête. Réseau en échec : message et nouvel essai possible avec le même jeton, sans risque de doublon (§6).
- **Affichage** : unités `rem`, aucune taille de police fixe, `prefers-color-scheme` pour le mode sombre (variables CSS), `prefers-reduced-motion` respecté, cibles tactiles de 44 points au moins. Mobile d'abord.
- **Champ piège** : un champ `site_web` hors écran (classe de masquage visuel, `aria-hidden="true"`, `tabindex="-1"`, `autocomplete="off"`), toujours envoyé, vide pour un humain.

La logique sans DOM (branchement, mélange, construction de la réponse, calcul « vous / la communauté ») vit dans `web/logique.js`, module ES testé par `node --test` ; `app.js` ne fait que l'affichage.

## 5. Modèle de données

### 5.1 Une réponse envoyée

```json
{
  "version": "2026-11-v1",
  "jeton": "9f2c…(32 caractères hexadécimaux)",
  "site_web": "",
  "duree_s": 312,
  "reponses": {
    "P1": "ipad", "P2": "lit", "P3": "avant-4",
    "O1": "petites-touches",
    "L1": "pages-ameliorees", "L2": "texte libre",
    "D1": [ { "section": "favoris", "garde": true, "rang": 1, "depliable": true } ],
    "D2": "a-suivre",
    "C04": "adore", "C01": "inutile",
    "ordre_cartes": ["C04", "C01", "C09", "C02", "C10", "C03", "C07", "C05", "C08", "C06"],
    "C11": "", "M1": "un-onglet", "F1": "", "I1": "pseudo facultatif"
  }
}
```

Une question sans réponse est absente. `duree_s` est l'écart entre l'ouverture de `E0` et l'envoi, borné à 0–7200, pour vérifier le budget de 7 minutes au test à cinq.

### 5.2 Validation et normalisation côté serveur

Le serveur ne fait pas confiance au front :
- corps JSON de 16 Ko au plus, `Content-Type: application/json` exigé ;
- `version` égale à celle du contenu chargé, sinon 409 avec un message « rechargez la page » ;
- clé inconnue, code inconnu ou type inattendu : 400, rien n'est stocké ;
- textes : normalisés NFC, caractères de contrôle retirés sauf retour à la ligne, espaces de bord retirés, longueur comptée en caractères (280, ou 40 pour `I1`) ; un texte vide devient absent ;
- `D1` : chaque section au plus une fois, rangs uniques de 1 à 9 parmi les sections gardées, `depliable` vrai seulement si `garde` vrai ;
- `ordre_cartes` : permutation exacte de `C01` à `C10`, sinon ignoré ;
- **branchement** : si `P1` n'est pas `ipad`, `duo` ou `plusieurs`, `D1` et `D2` sont retirés avant stockage, même si le front les a envoyés.

### 5.3 Schéma SQLite

Cinq tables. Les réponses ne contiennent ni IP, ni jeton, ni heure précise : aucune table ne permet de relier une réponse à une adresse.

| Table | Colonnes | Rôle | Vidée |
|---|---|---|---|
| `reponses` | `id` INTEGER PK, `recue_le` TEXT (date `AAAA-MM-JJ` seulement), `version` TEXT, `duree_s` INTEGER, `ordre_cartes` TEXT, `donnees` TEXT (JSON normalisé, sans `I1`) | Les réponses | Jamais par le service |
| `pseudos` | `reponse_id` INTEGER PK référence `reponses`, `pseudo` TEXT | `I1` à part, pour le purger d'une requête | Par `purger-pseudos` (§12) |
| `jetons` | `empreinte` TEXT PK (SHA-256 du jeton) | Anti-doublon par navigateur | À la fermeture |
| `empreintes_ip` | `empreinte` TEXT PK (HMAC-SHA-256 de l'IP avec le sel), `envois` INTEGER | Anti-doublon par adresse | À la fermeture |
| `sel` | `valeur` BLOB (32 octets aléatoires) | Sel des empreintes d'IP, créé au premier démarrage | À la fermeture |

Mode WAL, `busy_timeout` de 5 s, une seule connexion d'écriture. L'écriture d'une réponse (réponse, pseudo, jeton, compteur IP) est une seule transaction.

## 6. Anti-doublon, limitation de débit, champ piège

- **Jeton** : un jeton déjà présent dans `jetons` donne 409 `{"deja_recu": true}` et les statistiques ; le front affiche alors l'écran de fin normalement. Cela couvre aussi la double soumission et le nouvel essai après coupure réseau.
- **Adresse** : au plus `UX_MAX_PAR_IP` envois acceptés par empreinte d'IP (3 par défaut, pour les foyers et les réseaux mobiles partagés), sinon 429. L'IP en clair n'est jamais écrite, ni en base ni dans les journaux.
- **Limitation de débit**, en mémoire, par empreinte d'IP : `POST /api/reponses` 10 par heure, `GET /api/stats` 60 par minute, autres routes 120 par minute ; au-delà, 429 avec `Retry-After`. Plafond global de 1 000 empreintes suivies, les plus anciennes oubliées d'abord.
- **IP du client** : l'adresse de la connexion, sauf si elle appartient à `UX_PROXY_DE_CONFIANCE` ; alors seulement, la dernière adresse de `X-Forwarded-For`. Sans proxy de confiance configuré, l'en-tête est ignoré.
- **Champ piège** : `site_web` non vide donne la même réponse 201 qu'un envoi accepté, sans rien stocker, pour ne pas renseigner le robot.
- **Origine** : un `POST` dont l'en-tête `Origin` diffère de `UX_ORIGINE` est refusé (403). Avec l'absence de cookie et le `Content-Type` JSON exigé, cela suffit contre les envois intersites.

## 7. API

| Méthode et chemin | Réponse |
|---|---|
| `GET /` | `index.html` (pendant le questionnaire comme après la fermeture) |
| `GET /donnees` | `donnees.html` |
| `GET /static/…` | CSS, JS, `questionnaire.json`, visuels ; types MIME explicites |
| `GET /api/etat` | `{"ouvert": true, "fermeture": "…", "seuil": 20, "version": "…"}` |
| `POST /api/reponses` | 201 `{"stats": …}` ; 400 invalide ; 403 origine ; 409 version ou déjà reçu ; 410 fermé ; 413 trop gros ; 429 trop d'envois |
| `GET /api/stats` | Agrégats (§8), même forme que dans la réponse au `POST` |
| `GET /healthz` | 200 `ok`, sans accès à la base ni journal |

Toute autre route : 404. Pas de route d'export ni d'administration : ces actions passent par la ligne de commande sur le serveur (§12), donc aucune authentification à défendre en ligne.

**Accès restreint** pour le test à cinq (#635) : si `UX_CODE_ACCES` est défini, toutes les routes sauf `/healthz` exigent une authentification HTTP Basic (utilisateur `test`, comparaison en temps constant). On retire la variable pour l'ouverture publique.

## 8. Écran de fin et statistiques

- Questions fermées seulement : `P1` à `P3`, `O1`, `L1`, `D1`, `D2`, `C01` à `C10`, `M1`. Jamais `L2`, `C11`, `F1`, `I1`, `duree_s` ni `ordre_cartes`.
- Pour chaque question : pourcentage de chaque code parmi ceux qui y ont répondu, arrondi à l'entier, et effectif. Pour `D1` : par section, part de « gardée » et de « dépliable », et rang médian.
- **Seuil (D3)** : rien n'est publié tant que le total est sous `UX_SEUIL_STATS` (20). Ensuite, une question n'est publiée que si son propre effectif atteint aussi le seuil (utile pour le thème 2, vu par moins de monde). Sous le seuil, l'API renvoie `{"disponible": false}` sans aucun compte, et l'écran dit « Les résultats s'afficheront quand 20 personnes auront répondu ».
- La comparaison se fait dans le navigateur : le front met ses propres réponses (encore en mémoire ou dans le brouillon, avant effacement) en regard des pourcentages. Le serveur ne renvoie jamais une réponse individuelle.
- Affichage : barres horizontales en HTML et CSS (pas de bibliothèque de graphiques), la réponse du répondant mise en évidence par le texte (« Votre réponse ») et pas seulement par la couleur.
- Agrégats recalculés au plus une fois par minute, mis en cache en mémoire.

## 9. En-têtes HTTP et journaux

En-têtes posés par le service sur **toutes** les réponses, erreurs comprises :

```text
Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer
Permissions-Policy: camera=(), microphone=(), geolocation=()
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
Strict-Transport-Security: max-age=31536000
Cache-Control: no-store            (routes /api/)
```

Aucun script ni style en ligne, aucun cookie, aucune ressource d'un autre domaine (polices système seulement). HSTS est posé par le service quand `UX_ORIGINE` commence par `https://`.

**Journaux** (`log/slog`, JSON sur la sortie standard) : méthode, chemin sans paramètres, statut, durée, taille, et pour un refus sa raison (`honeypot`, `doublon-jeton`, `limite-ip`, `debit`, `origine`). Jamais : IP, empreinte d'IP, jeton, `User-Agent`, `Referer`, corps de requête, pseudo, texte libre. Le proxy inverse doit suivre la même règle pour ce sous-domaine (§13).

## 10. Configuration

Variables d'environnement, aucun secret dans le dépôt :

| Variable | Défaut | Rôle |
|---|---|---|
| `UX_ADRESSE` | `127.0.0.1:8080` | Adresse d'écoute, derrière le proxy |
| `UX_DONNEES` | `./donnees` | Dossier de la base SQLite |
| `UX_ORIGINE` | — (obligatoire) | Origine publique, par exemple `https://sondage.exemple.fr` |
| `UX_FERMETURE` | — (obligatoire) | Date et heure de fermeture, RFC 3339 avec fuseau |
| `UX_SEUIL_STATS` | `20` | Seuil D3 |
| `UX_MAX_PAR_IP` | `3` | Envois acceptés par empreinte d'IP |
| `UX_PROXY_DE_CONFIANCE` | vide | IP ou CIDR du proxy inverse dont on lit `X-Forwarded-For` |
| `UX_CODE_ACCES` | vide | Mot de passe de l'accès restreint, vide en public |

Le service refuse de démarrer si une variable obligatoire manque ou si `questionnaire.json` est invalide.

## 11. Déploiement

**Conteneur** : `deploy/Dockerfile` en deux étapes, compilation `CGO_ENABLED=0`, image finale `gcr.io/distroless/static` en utilisateur non root, volume `/donnees`, système de fichiers en lecture seule. `deploy/compose.yaml` publie le port sur `127.0.0.1` seulement.

**Binaire** : `GOOS=linux GOARCH=<amd64|arm64> go build`, copie dans `/opt/ux-survey/`, unité `deploy/ux-survey.service` avec `DynamicUser=yes`, `StateDirectory=ux-survey`, `ProtectSystem=strict`, `ProtectHome=yes`, `NoNewPrivileges=yes`, `PrivateTmp=yes`, et un fichier d'environnement lisible par root seulement.

**Proxy inverse** : exemples Caddy et nginx fournis, avec TLS, transmission de `X-Forwarded-For`, corps limité à 32 Ko, et journal d'accès désactivé (ou sans IP) pour ce sous-domaine.

**Étapes** :
1. Copier les visuels finaux de #632 dans `web/visuels/` et vérifier le test de concordance (§3).
2. Construire l'image ou le binaire, renseigner les variables, démarrer.
3. Vérifier `/healthz`, les en-têtes (`curl -I`), une réponse complète, puis la supprimer (base remise à zéro avant l'ouverture).
4. Test à cinq avec `UX_CODE_ACCES`, puis base remise à zéro.
5. Ouverture : retirer `UX_CODE_ACCES`, fixer `UX_FERMETURE` à deux semaines, redémarrer.

## 12. Fermeture et retrait

- **À la date de fermeture**, automatiquement (vérifié au démarrage puis toutes les heures) : `POST /api/reponses` répond 410, la page affiche « Questionnaire fermé » et les statistiques finales, et le service efface `sel`, `empreintes_ip` et `jetons` puis lance `VACUUM`. `ux-survey fermer` fait la même chose à la main.
- **Export** : `ux-survey export --format csv|json --sortie <fichier>`, lancé sur le serveur. Une ligne (ou un objet) par réponse ; colonnes `id`, `recue_le`, `version`, `duree_s`, puis les identifiants du §2 (`P1` … `M1`, `F1`), `D1` aplati en `D1_<section>_garde`, `D1_<section>_rang`, `D1_<section>_depliable`, et `ordre_cartes`. CSV en UTF-8 avec BOM, RFC 4180 ; toute cellule qui commence par `=`, `+`, `-`, `@`, tabulation ou retour chariot est préfixée d'une apostrophe (injection de formules). Le pseudo n'est exporté qu'avec `--avec-pseudos`.
- **Purge des pseudos** à la date annoncée par `donnees.md` (#630) : `ux-survey purger-pseudos` vide la table `pseudos` et lance `VACUUM`. Les exports qui contiennent des pseudos sont supprimés le même jour.
- **Retrait final**, à la date fixée par le PO après l'analyse : arrêter le service, retirer l'hôte du proxy et l'enregistrement DNS, supprimer le dossier de données et ses sauvegardes, et noter la date sur #628.

## 13. Ce que le PO doit fournir (D4)

Avant le déploiement (#635), pas avant la réalisation :
- système et architecture du VPS (distribution, version, x86-64 ou arm64) ;
- proxy inverse déjà en place (nginx, Caddy, Traefik, Apache ou aucun) et qui gère TLS (Let's Encrypt par le proxy, ou autre) ;
- Docker et Compose disponibles, ou systemd seulement ;
- sous-domaine choisi et accès DNS ;
- politique de journalisation du proxy : peut-on couper le journal d'accès ou retirer l'IP pour ce sous-domaine ;
- sauvegardes du VPS : le dossier de données y entre-t-il (il faudra alors les purger au retrait) ;
- fuseau horaire de la date de fermeture.

## 14. Tests que UX-10 doit écrire

Chaque test échoue sans le code qu'il couvre (LESSONS 2).

| # | Test | Vérifie |
|---|---|---|
| 1 | Concordance | `questionnaire.json` et `questions.md` : mêmes identifiants, codes, libellés, ordre ; tous les identifiants du §2 présents |
| 2 | Contenu | Codes en ASCII minuscules, uniques par question ; `C01` à `C10` présents ; chaque visuel référencé existe |
| 3 | Branchement serveur | `P1` vaut `ipad`, `duo`, `plusieurs` : `D1` et `D2` gardés ; `iphone` ou absent : retirés avant stockage |
| 4 | Branchement front (node) | Liste des écrans selon `P1` ; changement de `P1` qui efface `D1` et `D2` |
| 5 | Mélange (node) | L'ordre des cartes est une permutation de `C01` à `C10` et reste stable après rechargement du brouillon |
| 6 | Validation | Clé, code ou type inconnu, texte trop long, corps trop gros, `D1` aux rangs en double : refus, aucune ligne |
| 7 | Enregistrement | Un envoi valide : une ligne dans `reponses`, le pseudo seulement dans `pseudos`, `recue_le` sans heure |
| 8 | Doublon par jeton | Deuxième envoi du même jeton : 409, toujours une seule ligne |
| 9 | Doublon par adresse | Quatrième envoi d'une même IP : 429 ; la base ne contient pas l'IP en clair ; deux sels donnent deux empreintes |
| 10 | Proxy | `X-Forwarded-For` ignoré sans proxy de confiance, lu avec |
| 11 | Champ piège | `site_web` rempli : 201, aucune ligne |
| 12 | Débit | Au-delà de la limite : 429 avec `Retry-After` |
| 13 | Origine | `POST` d'une autre origine : 403 |
| 14 | Statistiques | 19 réponses : `disponible` faux, sans compte ; 20 : publiées ; question sous le seuil masquée ; arrondis ; aucune clé de texte libre, de pseudo, de durée ni d'ordre dans la charge |
| 15 | Fermeture | Après `UX_FERMETURE` : 410 au `POST`, `ouvert` faux, `sel`, `empreintes_ip` et `jetons` vides |
| 16 | Export | Colonnes et ordre, `D1` aplati, injection de formule neutralisée, pseudos absents sans `--avec-pseudos` |
| 17 | Purge | `purger-pseudos` vide `pseudos` sans toucher `reponses` |
| 18 | En-têtes | Les en-têtes du §9 sur une page, une route API, une 404 et une 429 |
| 19 | Journaux | Un envoi avec un pseudo et l'IP `203.0.113.7` : le journal capturé ne contient ni l'un ni l'autre, ni le texte libre |
| 20 | Poids et domaines | `web/` hors `visuels/` pèse 200 Ko au plus ; aucune URL absolue vers un autre domaine dans `web/` |
| 21 | Accès restreint | Avec `UX_CODE_ACCES` : 401 sans authentification, 200 avec ; `/healthz` toujours ouvert |

À vérifier à la main pendant le test à cinq : parcours complet au lecteur d'écran (VoiceOver sur iPhone), tri de `D1` aux boutons seuls, mode sombre, texte agrandi à 200 %, rechargement en cours de parcours, connexion lente.
