# Cloud Linux et Mac : qui fait quoi, comment passer la main

Sources : `docs/agents/MAC-SESSIONS.md`, `scripts/cloud-setup.sh`, `AGENTS.md` §10 de HFRnow ; pratique éprouvée sur
d'autres projets (règle « conteneur Linux : moteur oui, app non », script d'installation, script de reprise sur Mac).

## 1. Partage des rôles

| Environnement | Peut | Ne peut pas |
|---|---|---|
| **Session cloud** (conteneur Linux) | Code et docs ; tests du moteur (`swift test` sur le paquet sans UI) ; lint ; scripts ; issues et PR | Compiler l'app (SwiftUI, Charts, StoreKit, UIKit), simulateur, appareil, signature, réglages du dépôt |
| **Mac** (agent de code en CLI ou humain) | Xcode, simulateur, appareil, captures réelles, smoke tests, build signé | — (mais c'est le goulot : il ne fait que ce qui exige un Mac) |
| **CI** | Arbitre : ce qui n'est pas vert en CI n'est pas fini | — |

Conséquences :
- Garder le moteur **sans dépendance UI** (Foundation seulement) pour qu'il se teste partout.
- En cloud, relire le code de l'app **avec une rigueur de compilateur** : types, `@MainActor`, `Sendable` (Swift 6,
  concurrence stricte), exhaustivité des `switch`, API réelles de la version d'OS visée. Ne jamais écrire « compile »
  sans l'avoir vu ; écrire « non compilé ici, à vérifier sur Mac » dans « Points de vigilance » de la PR.
- Les issues qui demandent le Mac portent `hôte: mac` ; les sessions cloud n'y touchent pas.
- **Découpler** : ce que découvre le Mac et qui se code ailleurs (moteur, docs) devient une issue **sans** `hôte: mac`,
  pour qu'une session cloud la prenne. Pas d'aller-retour Mac ↔ cloud pour un petit correctif d'app (< ~30 lignes) : le
  Mac le fait.

## 2. Préparer le conteneur cloud
Un script d'installation (collé dans le « setup script » de l'environnement cloud, ou lancé à la main) installe **la même
version** de la chaîne d'outils que la CI Linux : archive officielle, **signature vérifiée** (clés publiées du projet,
import bloc par bloc si gpg refuse le fichier entier), puis le linter à la version de la CI avec empreinte vérifiée.
Les hôtes nécessaires (ex. `download.swift.org`, `github.com`, `release-assets.githubusercontent.com`) vont dans les
domaines autorisés de l'environnement. Exemple public : `scripts/cloud-setup.sh` de HFRnow (Swift 6.2.x + SwiftLint) ;
installer dans un dossier fixe (ex. `/opt/swift`) à la version épinglée par la CI.

## 3. Passer la main au Mac : le script de reprise
Modèle à écrire dans le projet (ex. `scripts/mac-handoff.sh`). Lancé sur le Mac, sans interaction, il :
1. synchronise la branche à tester (refuse un arbre sale ou une branche locale divergente : la tête locale doit égaler
   `origin/<branche>`) ;
2. rejoue la CI locale sans le build app (`local-check.sh --no-app`) ;
3. compile l'app pour un simulateur choisi dynamiquement, comme le job CI (mêmes conditions de compilation selon la
   version d'Xcode), `CODE_SIGNING_ALLOWED=NO` ;
4. **seulement si le build réussit** (et sauf `--no-smoke`) : installe, lance, tourne l'appareil, vérifie qu'elle ne
   plante pas, récupère les journaux de plantage, prend des captures ;
5. écrit `build/handoff/REPORT.md` : en-tête (branche @ SHA, date, macOS, Xcode), résultats 🟢 / 🟠 / 🔴, erreurs de
   compilation (extrait), début du journal de plantage, puis la **liste de vérifications à la main** de la release ;
   le copie dans le presse-papiers.

L'opérateur colle `REPORT.md` dans la session cloud, qui corrige et repousse. Règle : un seul aller-retour par lot quand
c'est possible (tout corriger d'un coup).

## 4. Sessions Mac autonomes
Quand le Mac travaille sans surveillance (captures, vérifications à la main, lots Mac), son prompt commence par un
**contrat d'autonomie** (modèle : `MAC-SESSIONS.md` de HFRnow) :
- l'opérateur ne regarde pas : **ne jamais s'arrêter pour poser une question** ; une décision nécessaire = un court
  commentaire sur l'issue concernée, finissant par « Décision attendue (opérateur) », puis l'élément suivant ; tous les
  éléments sautés vont dans le rapport final ;
- pré-autorisations explicites et bornées (ex. écritures permises seulement entre les comptes de test de l'opérateur) ;
  tout le reste est sauté et listé ;
- les règles du dépôt l'emportent sur le prompt en cas de conflit (le dire dans le rapport) ;
- jetons comptés : lire seulement les fichiers utiles, filtrer les journaux de build aux erreurs et au statut final ;
- **conditions d'arrêt** : file vide ou seulement des éléments bloqués ; durée maximale (ex. 6 h) ; CI rouge sur la
  branche d'intégration pour une raison extérieure (le signaler, ne pas corriger) ; réponse anormale d'un service
  externe (403, captcha) → tout trafic arrêté ;
- parallélisme borné par le budget CI (au plus 2 lots Mac à la fois, chacun dans son worktree et son sous-agent) ;
- chien de garde des sous-agents (30 min sans commit ni commentaire, ou 3 fois la même commande en échec → arrêt) ;
- ménage : worktrees, DerivedData, clones de simulateur supprimés ; checkout principal propre sur la branche
  d'intégration ;
- **rapport final** : un commentaire sur l'issue de suivi de l'orchestrateur (fait → PR → mergé ou non, faits appris,
  issues ouvertes, lots débloqués, éléments sautés et décisions attendues, par quoi commence la session suivante), et le
  même rapport dans le terminal.

## 5. Vérifier ce que le cloud a mergé sans Mac
Quand des merges ont été acceptés sans vérification Mac pour aller vite : un build unique à la tête de la branche
d'intégration, toutes les vérifications à la suite, groupées par écran. Une vérification qui échoue à la tête est
reproduite au SHA du merge qu'elle couvre avant de blâmer qui que ce soit (sinon `git bisect` entre les deux). Grave
(plantage, perte de données, fuite) → PR de revert immédiate en `P1 🔴`, signalée en tête du rapport.
