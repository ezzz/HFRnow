# Vérification de l'image Docker du formulaire (UX-11, partie préparatoire)

Lot UX-11 ([#635](https://github.com/ezzz/HFRnow/issues/635)), avant la revue de sécurité. Vérifié le 15 novembre 2026 sur
le Mac de l'opérateur (Docker Desktop 29.1.2, arm64) avec `tooling/ux-survey/` au commit `e71acade` plus les corrections de
cette PR. Un fichier `.env` de test, hors dépôt et jamais affiché, avec des valeurs fictives ; adresses de test en
`198.51.100.x` et `203.0.113.x` (plages de documentation). **Rien n'a été fait sur le VPS** : ce document dit ce qui est
prouvé en local et ce qui reste à prouver sur l'hôte.

## Résultat en bref

- Le parcours complet du §11 (étape 3) et du §12 passe sur 127.0.0.1, à travers `deploy/compose.yaml`.
- Un défaut corrigé : **l'image n'avait aucun contrôle de santé** (voir « Écarts »).
- Le workflow `ux-survey.yml` testait le code mais pas l'image : il construit et démarre maintenant l'image (job `image`) et
  lance `go test -race`.
- La revue de sécurité de Fable (15 novembre) a demandé des corrections, toutes faites : voir « Corrections après la revue de sécurité ». Les points à vérifier sur l'hôte sont dans la liste du PO, en fin de document.

## Image

```bash
cd tooling/ux-survey
docker build -f deploy/Dockerfile -t ux-survey:local .
docker image inspect ux-survey:local --format 'user={{.Config.User}} entrypoint={{.Config.Entrypoint}} cmd={{.Config.Cmd}}'
docker image inspect ux-survey:local --format '{{.Size}}'
```

| Contrôle | Résultat |
|---|---|
| Construction à froid | 1 min 37 s (version avant correction) ; `golang:1.27.4` puis `gcr.io/distroless/static:nonroot` |
| Taille | 14,1 Mo (le binaire seul pèse 11,7 Mo) ; le CI exige moins de 30 Mo |
| Utilisateur | `65532:65532` (image et processus : `docker top` montre 65532) |
| Shell, curl | aucun (`docker run --entrypoint /bin/sh` échoue : `/bin/sh` n'existe pas) |
| Architecture | celle de l'hôte (`TARGETARCH`) : arm64 ici ; à reconstruire sur le VPS, pas d'image exportée |
| Contexte de construction | `.dockerignore` est une **liste d'autorisation** (`go.mod`, `go.sum`, `embed.go`, `cmd`, `internal`, `web`, `contenu`) : ni base, ni `.env`, ni export laissé dans le dossier ne peut entrer dans le contexte ni dans le cache de construction. (La première version de ce document affirmait que l'ancienne liste d'exclusion suffisait ; la revue de sécurité a montré que `deploy/donnees/`, `deploy/.env` et `deploy/autre.env` y entraient : corrigé.) |
| Images de base | `golang:1.27.4` et `gcr.io/distroless/static:nonroot` épinglées par condensat sha256 (index multi-architecture) |

## Conteneur lancé par Compose

```bash
cd tooling/ux-survey/deploy
docker compose --env-file <env de test hors dépôt> up -d --build --wait
docker inspect ux-survey-ux-survey-1 --format 'ro={{.HostConfig.ReadonlyRootfs}} capdrop={{.HostConfig.CapDrop}} secopt={{.HostConfig.SecurityOpt}} ports={{json .NetworkSettings.Ports}}'
```

| Contrôle | Résultat |
|---|---|
| Système de fichiers | lecture seule (`ReadonlyRootfs=true`) ; l'écriture se fait dans `/donnees` seulement, et tout le parcours (dont `VACUUM INTO` et les exports) fonctionne ainsi |
| Volume | `/donnees` monté en lecture-écriture, dossier 0700 ; fichiers créés en 0600 (umask 077) : `reponses.db`, `-wal`, `-shm`, `cle-ip`, exports, sauvegarde |
| Droits | `cap_drop: [ALL]`, `no-new-privileges:true` |
| Port | `127.0.0.1:18080->8080/tcp` seulement |
| Contrôle de santé | `healthy` en moins de 10 s (après correction) ; sonde = `ux-survey sante` |
| Redémarrage | `docker compose restart` : même total (11), mêmes statistiques, `-wal` vide ; aucune perte |

## En-têtes HTTP (§9)

```bash
curl -sI http://127.0.0.1:18080/
curl -sI http://127.0.0.1:18080/api/etat
curl -si http://127.0.0.1:18080/nope
```

Présents sur `/`, sur `/api/etat` et sur la 404 : `Content-Security-Policy` (la valeur exacte du §9),
`X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Permissions-Policy`,
`Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Resource-Policy: same-origin`. `Cache-Control: no-store` sur
`/api/` (et `/donnees`). Aucun cookie. Avec `UX_ORIGINE=https://…`, `Strict-Transport-Security: max-age=31536000` est
présent (contrôlé par le job CI) ; avec `http://`, il est absent, comme prévu.

## Parcours sur 127.0.0.1 (§11 étape 3, §12)

Chaque envoi est un `POST /api/reponses` avec `Origin: http://127.0.0.1:18080` et un en-tête `X-Forwarded-For` de test.

| Cas | Attendu | Observé |
|---|---|---|
| Envoi valide | 201, statistiques sous le seuil | 201 `{"stats":{"disponible":false,"seuil":10}}` |
| Même jeton | 409 `deja_recu` | 409 `{"deja_recu":true,"stats":{…}}` |
| Envoi vide (`reponses: {}`) | 400, rien d'enregistré | 400 « aucune réponse à enregistrer » ; aucun envoi vide dans le total |
| Mauvaise origine | 403 | 403 |
| Champ piège `site_web` | 201, rien stocké | 201, journal `refus: honeypot`, total inchangé |
| Limite par adresse (3) | 4e envoi de la même adresse : 429 ; autre adresse : 201 | 429 « trop d'envois depuis cette adresse » ; une autre adresse a reçu 201 |
| Limite de débit | 11e POST de l'heure : 429 avec `Retry-After` | 429, `Retry-After: 3600` ; `/api/stats` : 429 au 61e appel de la minute |
| Écran de fin sous le seuil | `{"disponible":false,"seuil":10}` sans total | oui jusqu'à 9 réponses ; à 11 réponses `disponible:true`, effectif de `P1` publié |
| `export analyse`, `agregats`, `pseudos`, `sauvegarder` | fichiers 0600, `cle-ip` hors sauvegarde | CSV avec BOM et colonnes du §12, JSON, `agregats` à 11 ; fichiers en 0600 ; la sauvegarde s'écrit sans `cle-ip` |
| Droits R7/R13 | `--chercher`, `--limiter`, `--lever-limite`, `--effacer` | tous répondent comme la spec ; la recherche après `--effacer` donne 0 réponse |
| `fermer` / `effacer` avant `UX_FERMETURE` | refusés | refusés (« le formulaire accepte encore des réponses ») |
| Fermeture (`UX_FERMETURE` avancée au jour même, redémarrage) | 410 sur les envois, `cle-ip` supprimée, `-wal` vide | 410 « Questionnaire fermé » ; `cle-ip` supprimée ; `-wal` à 0 octet |
| `effacer` (deux fois) | `agregats.json` écrit une fois, tables vides, idempotent | « effacement terminé » deux fois ; `agregats.json` identique à l'export `agregats` ; `reponses`, `pseudos`, `jetons`, `empreintes_ip` à 0 ligne |
| Statistiques après effacement | servies depuis `agregats.json`, mêmes seuils | `{"disponible":true,"total":11,…}` ; la page `/` reste servie |

Remarque : `ux-survey pseudo --limiter` s'exécute dans un autre processus que le service ; les statistiques en ligne ne
changent qu'au prochain recalcul du cache (au plus une minute, §8). Constaté, conforme à la spec.

## Journaux : aucune IP

Avec les cinq refus (doublon, limite par adresse, origine, champ piège, envoi accepté) provoqués avec un `User-Agent` et un
`Referer` reconnaissables, un texte libre et un jeton, `docker logs` ne contient que `time`, `level`, `msg`, `methode`,
`chemin`, `statut`, `duree_ms`, `taille` et `refus` (`doublon-jeton`, `limite-ip`, `origine`, `honeypot`). Le grep des adresses de
test, de la passerelle, de l'agent, du référent, du texte libre et du jeton ne trouve rien. Le seul nombre pointé du démarrage
est l'adresse d'écoute `0.0.0.0:8080` ; le job CI l'exclut explicitement.

## Contrôle de CI `ux-survey.yml`

Lu avant correction :

- il lançait `go vet`, `go test ./...` (sans `-race`) et `node --test` : fidèle à son commentaire, mais **il ne construisait
  jamais l'image** : une erreur de `Dockerfile` ou de `compose.yaml` n'apparaissait qu'au déploiement ;
- la liste de chemins du déclencheur `pull_request` couvre `tooling/ux-survey/**` (donc `deploy/`), les trois documents lus
  par le test de concordance, les visuels et le workflow lui-même : correcte ;
- le déclencheur `push` sur `dev-swift` est plus large (`docs/ux/questionnaire/**`) : sans conséquence.

Corrigé : `go test -race ./...`, et un job `image` qui, avec `compose.yaml` lui-même (donc la même image, le même
utilisateur, les mêmes protections que le déploiement), construit, démarre avec `--wait` (échoue si l'image ne devient pas
`healthy`) puis contrôle : santé, utilisateur 65532, lecture seule, `cap_drop ALL`, port sur 127.0.0.1 seulement, quatre
en-têtes dont HSTS, taille de l'image sous 30 Mo, aucune IP dans les journaux. Les étapes `run` du job ont été exécutées
telles quelles en local, avec succès ; le job lui-même ne s'exécutera qu'à l'ouverture de la PR (pas de runner ici).
`markdownlint` n'est pas dans ce workflow : il tourne dans son propre contrôle du dépôt.

## Écarts trouvés

Corrigés dans cette PR :

1. **Pas de contrôle de santé.** Ni `HEALTHCHECK` dans le `Dockerfile`, ni `healthcheck` dans `compose.yaml` : `docker ps`
   n'indiquait jamais si le service répondait, et `compose up --wait` n'avait rien à attendre. L'image n'ayant ni shell ni
   curl, une sonde classique est impossible. Ajout de la commande `ux-survey sante` (`GET /healthz` sur `UX_ADRESSE`,
   `0.0.0.0` ramené à `127.0.0.1`, délai 3 s, ne lit que `UX_ADRESSE` : ni configuration complète, ni base), du
   `HEALTHCHECK` du `Dockerfile` et du `healthcheck` de `compose.yaml` (30 s, 3 essais). Tests :
   `cmd/ux-survey/sante_test.go` (service sain, adresse joker, statut 500, service arrêté, sans variables obligatoires).
2. **Le CI ne vérifiait pas l'image** ni `-race` : voir ci-dessus.

À décider par le PO ou à vérifier sur l'hôte (non corrigés) :

3. **Adresse du client derrière Tailscale Funnel** (déjà au §13 de la spec) : voir la section suivante.
4. *(corrigé ensuite, voir plus bas)* **Images de base non épinglées par condensat** (`golang:1.27.3`, `gcr.io/distroless/static:nonroot`) : le tag `nonroot` de
   distroless se déplace. Épingler par `@sha256:` rend la construction reproductible mais demande de le tenir à jour : décision du
   PO, non faite ici.
5. **Droits des fichiers sur le VPS.** Les exports et sauvegardes, écrits par l'utilisateur 65532 en 0600 dans un dossier 0700,
   ne sont lisibles sur l'hôte que par `root` ou 65532 (`sudo`). Sur le Mac de test, Docker Desktop masque ce comportement
   (les fichiers apparaissent au nom de l'utilisateur du Mac) : **le 0700 / 65532 n'a donc pas pu être éprouvé ici**, et le
   README dit déjà de créer le dossier avec `install -d -m 0700 -o 65532 -g 65532`.
6. **Pas d'essai sous Linux.** Docker Desktop fait passer les connexions par une machine virtuelle ; la passerelle 172.31.250.1
   y a bien été vue comme proxy de confiance (les `X-Forwarded-For` de test ont donné des compteurs distincts), mais sur
   Ubuntu avec `userland-proxy` ou DNAT la source vue par le conteneur peut différer : c'est précisément l'étape 3 du §11.

## IP du client derrière Tailscale Funnel : ce que le code attend

- Le service lit **la dernière adresse** de `X-Forwarded-For`, et **seulement** si la connexion vient de
  `UX_PROXY_DE_CONFIANCE` ; sinon il prend l'adresse de la connexion (`internal/web/ip.go`, spec §6).
- `compose.yaml` fixe `UX_PROXY_DE_CONFIANCE` à la passerelle du réseau du projet (`172.31.250.1`, modifiable par
  `UX_SOUS_RESEAU_PASSERELLE`) : un client de l'hôte qui se connecte à `127.0.0.1:<port>`, ce que fait `tailscaled` pour
  Funnel, arrive depuis cette adresse. Vérifié ici avec un client de l'hôte, pas avec Funnel.
- **Non prouvé et à ne pas supposer** : que Funnel ajoute `X-Forwarded-For` avec l'adresse publique du client, et dans quel
  ordre. Je n'ai pas cherché la réponse dans une source tierce (règle « ne pas deviner »). Si Funnel n'envoie pas cet en-tête,
  tous les répondants partagent l'adresse de la passerelle : le 4e envoi reçoit 429 et la limite de débit les compte comme un
  seul. Le service n'a pas de variable `UX_EN_TETE_CLIENT` (spec §11) : elle serait à ajouter par #634 si Funnel utilise un
  autre en-tête.
- **À faire au déploiement** (étape 3 du §11, sans rien écrire dans le dépôt de réel) : envoyer des réponses depuis deux
  adresses publiques distinctes et vérifier qu'elles ont des compteurs séparés ; sinon ne pas ouvrir (§13). Vérifier aussi que
  le journal de `tailscaled` n'écrit pas d'IP de répondants pour ce port (R1) et que les sauvegardes du VPS excluent `cle-ip`.

## Reproduire

```bash
cd tooling/ux-survey
go vet ./... && go test -race ./... && node --test web/logique.test.mjs
cd deploy
docker compose --env-file <env de test> up -d --build --wait
```

Puis les requêtes du tableau « Parcours » avec `curl`, et `docker compose exec ux-survey /ux-survey <commande>` pour les exports,
les droits, `fermer` et `effacer`. Pour tester la fermeture sans attendre, avancer `UX_FERMETURE` (jamais repousser) et
redémarrer.

## Corrections après la revue de sécurité (Fable, 15 novembre)

Le PO a validé le 17 novembre de tout corriger. Les repères E1 à F5 sont ceux du rapport de revue (local, non publié).

| Repère | Correction | Où |
|---|---|---|
| E1 | `logging` json-file 10 Mo × 3 dans `compose.yaml` ; un chemin qui n'est ni une route ni un fichier embarqué est journalisé `(inconnu)` ; tout `/static/` limité à 600 par minute (404 compris) | `deploy/compose.yaml`, `internal/web/middleware.go` |
| E2 | Documenté seulement : mode proxy HTTP obligatoire et essai anti-usurpation (liste du PO, 3 et 4) | spec §11 et §13, ce document |
| M1 | Compteur d'envois par /56, débit par /64 ; plafond global `UX_PLAFOND_HORAIRE` (300 par heure, 503 au-delà, une ligne d'avertissement par fenêtre) | `internal/web/ip.go`, `plafond.go`, spec §6 |
| M2 | L'effacement supprime `sauvegardes/` et tout `exports/` sauf `agregats-*` | `internal/stockage/cycle.go` |
| M3 | `sauvegarder` vide `jetons` et `empreintes_ip` de la copie, puis la compacte | `internal/stockage/cycle.go` |
| M4 | `reponses` et `pseudos` en `WITHOUT ROWID` ; une base d'un ancien schéma est refusée au démarrage | `internal/stockage/base.go` |
| M5 | `.dockerignore` en liste d'autorisation ; `UX_DOSSIER_DONNEES` obligatoire | `deploy/` |
| F1 | À la fermeture exécutée (ou à l'effacement), l'instant de fermeture est mémorisé en UTC ; toute `UX_FERMETURE` plus tardive est refusée, quel que soit le décalage (cas `-12:00` testé) | `internal/stockage/ecriture.go` |
| F2 | `GET /api/stats` vient du cache d'une minute ; seul le 201 montre des chiffres frais (le 409 et le champ piège utilisent le cache) | `internal/web/api.go` |
| F3 | 10 essais de code d'accès faux par adresse et par dix minutes, puis 429 même avec le bon code ; code aléatoire de 20 caractères au moins documenté | `internal/web/middleware.go`, `ux-survey.env.exemple` |
| F4 | Images épinglées ; `govulncheck` dans le CI ; commentaire de `base.go` corrigé ; voir plus bas | `Dockerfile`, workflow |
| F5 | `mem_limit: 256m`, `pids_limit: 128`, `cpus: 1.0` | `deploy/compose.yaml` |
| Relecture Opus | Contrôle des journaux en CI réécrit avec `if … then exit 1; fi`, après un vrai `POST` d'envoi (agent, référent, texte libre et pseudo reconnaissables) et une requête sur un chemin inconnu ; il échoue aussi s'il ne trouve aucune ligne d'envoi | workflow |

**`govulncheck` (F4)** a trouvé, au premier passage, deux vulnérabilités atteignables : `net/http` de Go 1.27.3 (corrigée en 1.27.4) et `golang.org/x/text` v0.28.0, appelé par la normalisation NFC (corrigée en v0.39.0). Corrigé : `go 1.27.4` dans `go.mod`, `golang:1.27.4` dans le `Dockerfile`, `golang.org/x/text v0.39.0`. Résultat : « No vulnerabilities found » ; un module requis non appelé reste signalé sans effet. C'est une montée de version d'une dépendance existante, pas une nouvelle dépendance ; l'outil est épinglé dans le CI (`@v1.9.0`) et absent de `go.mod`.

**Rejeu après corrections** (image reconstruite avec les images épinglées) : démarrage `healthy` ; limites du conteneur appliquées (`Memory` 268 435 456, `PidsLimit` 128, 1 CPU, `json-file` 10m × 3) ; 11 envois acceptés, statistiques publiées ; export `pseudos` et `agregats`, sauvegarde (copie à 0 jeton et 0 empreinte, 11 réponses) ; redémarrage sans perte ; `fermer` puis `effacer` : il ne reste dans le dossier de données que `agregats.json`, les `agregats-*` de `exports/` et la base vidée (le `pseudos-*` et la sauvegarde ont disparu) ; `UX_FERMETURE` repoussée avec un décalage `-12:00` après la fermeture : le service refuse de démarrer.

## Journaux de CI et essai anti-usurpation

Le job `image` reste un contrôle de non-régression sur la forme (utilisateur, en-têtes, journaux) ; il ne remplace pas l'essai sur l'hôte, qui seul passe par Funnel.

**Essai anti-usurpation (E2)** : voir le point 3 de la liste ci-dessous. Sur la machine de développement, avec `127.0.0.1` pour seul client, le service croit un `X-Forwarded-For` forgé (c'est son rôle quand la connexion vient de la passerelle). Sur le VPS, le résultat attendu est inverse : Funnel doit réécrire l'en-tête, donc les adresses inventées ne doivent pas produire de compteurs distincts.

## Liste du PO : vérifications au déploiement

Aucune de ces vérifications n'a pu être faite ici (pas de VPS, pas de Funnel). Les chemins sont ceux du README ; `<url-funnel>` et les adresses sont à remplacer sur place et ne vont jamais dans le dépôt.

1. **Mode de Funnel.** `tailscale funnel status` montre `proxy http://127.0.0.1:18080`, jamais `tcp://`.
2. **Écoute et passerelle.** `ss -ltnp | grep 18080` : `127.0.0.1` seulement. `docker network inspect ux-survey_ux` : passerelle `172.31.250.1`, identique à `UX_PROXY_DE_CONFIANCE` (visible par `docker inspect` du conteneur).
3. **Anti-usurpation**, depuis une machine A (le limiteur passant avant l'authentification, cela marche aussi avec le code d'accès) :

   ```bash
   for i in $(seq 1 130); do
     curl -s -o /dev/null -w '%{http_code}\n' \
       -H "X-Forwarded-For: 198.51.100.$((RANDOM % 250 + 1))" https://<url-funnel>/api/etat
   done | sort | uniq -c
   ```

   Attendu : environ 120 réponses 200 (ou 401), puis des 429. **Aucun 429 : l'en-tête forgé est cru, ne pas ouvrir.**
4. **Adresses distinctes**, tout de suite après, depuis un téléphone B en 4G (Wi-Fi coupé) : `/api/etat` répond 200 ou 401. **Un 429 veut dire que tout le monde partage la passerelle : ne pas ouvrir** (spec §13). Puis l'étape 3 du §11 de la spec (quatre envois depuis deux adresses).
5. **Journaux de `tailscaled` (R1).** Après les essais : `journalctl -u tailscaled --since '-15 min' | grep -F '<IP publique de A>'` doit être vide. Décider de couper l'envoi des journaux à Tailscale (`--no-logs-no-support`).
6. **Rotation des journaux Docker** en place : `docker inspect -f '{{json .HostConfig.LogConfig}}' <conteneur>` donne `json-file`, `max-size` 10m, `max-file` 3.
7. **Dossier de données** hors du dépôt : `stat -c '%a %U:%G' /srv/ux-survey/donnees` donne `700` et 65532 ; fichiers en 600 ; `exports/` et `sauvegardes/` en 700.
8. **`ux-survey.env`** en 600, hors git ; `UX_CODE_ACCES` aléatoire, 20 caractères au moins.
9. **Sauvegardes du VPS** : dossier de données exclu (au minimum `cle-ip`). `docker builder prune` après chaque construction.
10. **Autre application de l'hôte** : tout processus local peut joindre `127.0.0.1:18080` et forger l'en-tête. Vérifier qu'elle ne relaie pas de requêtes vers la boucle locale.
11. **Après le test à cinq** : supprimer la base, `-wal`, `-shm`, `cle-ip`, `agregats.json`, `exports/` et `sauvegardes/`.
12. **À l'ouverture** : retirer `UX_CODE_ACCES`, fixer `UX_FERMETURE`, contrôler `curl -I` (HSTS présent) et les dates affichées sur `/donnees`.
13. **À la fermeture** : ligne « fermeture faite » dans le journal, `cle-ip` absente, sauvegardes antérieures supprimées.
14. **À la date d'effacement** : le service doit encore tourner (sinon lancer `effacer` à la main) ; ligne « effacement terminé » ; `exports/` (hors agrégats) et `sauvegardes/` absents ; supprimer les copies d'analyse, purger le cache Docker et les sauvegardes du VPS.
