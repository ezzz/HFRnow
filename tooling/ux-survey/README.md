# Questionnaire UX : le formulaire

Service du questionnaire sur la suite de l'app (lot UX-10, #634). Il suit
[`docs/ux/questionnaire/formulaire-spec.md`](../../docs/ux/questionnaire/formulaire-spec.md) ; les textes viennent de
[`questions.md`](../../docs/ux/questionnaire/questions.md) et [`donnees.md`](../../docs/ux/questionnaire/donnees.md).
Un binaire Go (bibliothèque standard, plus deux dépendances tierces épinglées : `modernc.org/sqlite` et `golang.org/x/text` pour la normalisation NFC), un front sans framework ni
étape de build, une base SQLite. Aucun cookie, aucune requête vers un autre domaine, aucune mesure d'audience.

## Tests

```bash
cd tooling/ux-survey
go vet ./... && go test ./...
node --test web/logique.test.mjs
```

Le test de concordance relit `docs/ux/questionnaire/questions.md` : une correction de libellé là-bas fait échouer
`go test` tant que `contenu/questionnaire.json` n'est pas mis à jour.

## Lancer en local

```bash
cd tooling/ux-survey
UX_ORIGINE=http://127.0.0.1:8080 UX_PROXY_DE_CONFIANCE=aucun \
UX_FERMETURE=2026-12-31T23:00:00+01:00 UX_MENTION_MAJ=2026-11-09 \
go run ./cmd/ux-survey serve
```

Puis ouvrir <http://127.0.0.1:8080/>. Les données vont dans `./donnees` (ignoré par git).

## Configuration

| Variable | Défaut | Rôle |
|---|---|---|
| `UX_ADRESSE` | `127.0.0.1:8080` | Adresse d'écoute |
| `UX_DONNEES` | `./donnees` | Base, `cle-ip`, `agregats.json` |
| `UX_ORIGINE` | obligatoire | Origine publique ; un `POST` d'une autre origine est refusé ; HSTS si `https://` |
| `UX_PROXY_DE_CONFIANCE` | obligatoire | IP ou CIDR du proxy (liste séparée par des virgules), ou `aucun` |
| `UX_FERMETURE` | obligatoire | RFC 3339 avec décalage ; la date d'effacement vaut cette date + 2 mois |
| `UX_MENTION_MAJ` | obligatoire | `AAAA-MM-JJ`, date de mise à jour de la mention |
| `UX_SEUIL_STATS` | `10` | Seuil D3 ; moins de 10 est refusé |
| `UX_MAX_PAR_IP` | `3` | Envois acceptés par adresse |
| `UX_CODE_ACCES` | vide | Accès restreint (utilisateur `test`) pour le test à cinq |

Le service refuse de démarrer si une variable obligatoire manque ou si une valeur entre accolades d'une page reste
après remplacement.

## Déploiement (Docker Compose)

Voir la section 11 de la spécification. Le questionnaire est un projet Compose à part, publié seulement sur la boucle locale.

```bash
cd tooling/ux-survey/deploy
cp ux-survey.env.exemple ux-survey.env   # puis adapter ; jamais versionné
install -d -m 0700 -o 65532 -g 65532 /srv/ux-survey/donnees
docker compose --env-file ux-survey.env up -d --build
ss -ltn | grep 18080                      # doit n'écouter que sur 127.0.0.1
curl -I http://127.0.0.1:18080/healthz
```

**Exposition par Tailscale Funnel** (décision du PO, #706) : Funnel devant le port de boucle locale, par exemple

```bash
tailscale funnel --bg 18080
```

`UX_ORIGINE` est alors l'URL `*.ts.net` donnée par Funnel. À vérifier sur l'hôte avant l'ouverture (spec §13) : quel
en-tête Funnel transmet avec l'adresse du client, et que deux clients aux IP différentes ont deux compteurs
(étape 3 du §11). Le service ne lit que la dernière adresse de `X-Forwarded-For` ; si Funnel utilise un autre en-tête, il
faudra ajouter `UX_EN_TETE_CLIENT`. `deploy/Caddyfile.exemple` ne sert qu'en secours.

Le journal d'accès de Tailscale ou du proxy pour ce questionnaire doit être coupé, ou sans IP, agent utilisateur ni
référent (R1).

## Exploitation (sur le serveur)

Les commandes s'exécutent dans le conteneur, qui porte déjà l'environnement :

```bash
docker compose exec ux-survey /ux-survey export --format analyse --sortie /donnees/exports/analyse
docker compose exec ux-survey /ux-survey export --format agregats --sortie /donnees/exports/agregats
docker compose exec ux-survey /ux-survey sauvegarder /donnees/sauvegardes/copie.db
docker compose exec ux-survey /ux-survey fermer
docker compose exec ux-survey /ux-survey effacer
```

- `export --format analyse|agregats|pseudos` écrit `<préfixe>-AAAA-MM-JJ.csv` (et `.json`, sauf `pseudos`) en 0600.
  `analyse` : pseudonymisé, textes libres compris, colonne `textes_relus` vide. `agregats` : seul jeu gardé après
  l'effacement. `pseudos` : pour les demandes de droits seulement. Le dossier de sortie doit exister.
- `sauvegarder` : copie cohérente par `VACUUM INTO`, sans `cle-ip`. Seule sauvegarde prise en charge ; ne jamais copier
  le fichier de base pendant que le service tourne.
- `fermer` et `effacer` refusent de s'exécuter avant `UX_FERMETURE` (pour fermer plus tôt, avancer `UX_FERMETURE` et
  redémarrer). Le service les lance aussi seul : fermeture au premier passage horaire après `UX_FERMETURE`, effacement
  à `UX_FERMETURE` + 2 mois. `effacer` est idempotent et ne réécrit jamais `agregats.json`.
- Droits d'un répondant (R7, R13) : `pseudo --chercher <pseudo>`, `--afficher <id>`, `--limiter <id>`, `--lever-limite <id>`, `--corriger <id> --question L2
  --valeur-json '"texte"'`, `--effacer-question <id> --question L2`, `--effacer-pseudo <id>`, `--effacer <id>`.
- Les exports et sauvegardes écrits dans le dossier de données restent à supprimer à la main à la date d'effacement
  (liste à cocher du §12).

## Visuels provisoires (#632)

Les visuels de #632 n'existent pas encore. `web/visuels/` et `docs/ux/questionnaire/visuels/` contiennent des
**marques de place** (bandeau « VISUEL PROVISOIRE ») aux noms et formats de `cadrage-construction.md` §3.3 ; les `.mp4`
sont des conteneurs vides, la page montre leur image d'attente. Les fichiers réels les remplacent aux mêmes noms, dans
les deux dossiers (un test les veut identiques), et `inventaire.md` est réécrit : aucun changement de code.

## Notes de réalisation

- NFC : `golang.org/x/text/unicode/norm` (version épinglée dans `go.mod`), la bibliothèque standard n'ayant pas de
  normalisation Unicode (décision du PO du 11 novembre 2026).
- `UX_FERMETURE` : mémorisée à la première réponse ; ensuite avançable, jamais repoussable (le service et les
  commandes refusent de démarrer avec une date plus tardive).
- Réponse « limitée » (R13) : `pseudo --limiter <id>` (et `--lever-limite <id>`) l'exclut des statistiques et de tous les exports.
- Le glisser-déposer du tri `D1` (facultatif dans la spec) n'est pas fait : boutons « Monter » et « Descendre » seuls.
- À vérifier à la main pendant le test à cinq : voir le §14 de la spécification.
