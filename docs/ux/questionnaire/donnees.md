# Mention sur les données personnelles du questionnaire

Date : 8 novembre 2026. Livrable de l'issue #630 (UX-06). Statut : **proposition** ; les décisions du PO du 8 novembre 2026 sont appliquées (V1 à V7, D3 révisée, partage des textes avec `questions.md`) ainsi que la relecture croisée de Fable. Reste la validation finale du texte par le PO.

Ce document fait foi pour **les faits** sur les données. Il contient :
- le **paragraphe** placé au-dessus du champ pseudo facultatif (`I1`, à la fin du questionnaire, décision D2) ;
- la **page détaillée**, ouverte depuis l'accueil (`E0`) et depuis ce paragraphe.

Les textes courts (libellé et aide du champ `I1`, libellé du lien vers cette page) appartiennent à `questions.md` (#629), qui fait foi pour eux ; ils doivent énoncer les mêmes faits que la section 1 ci-dessous (décision du PO du 8 novembre 2026, commentaire sur #628).

Il suit les contraintes de `cadrage-construction.md` §4. Les éléments entre accolades, par exemple `{date_fermeture}`, sont des valeurs de configuration du formulaire : la réalisation (#634) les remplit à partir de la configuration, pour que la mention et le formulaire ne divergent jamais. Les décisions du PO sont consignées à la fin, section 4.

## 1. Paragraphe au-dessus du champ pseudo

> Votre pseudo sert à une seule chose : permettre à Bruno Arene, qui mène ce questionnaire, de vous écrire en MP sur HFR s'il souhaite approfondir un sujet avec vous. Il n'est jamais affiché ni publié. Il est effacé au plus tard le {date_effacement}, deux mois après la fermeture, ou plus tôt si vous le demandez à Bruno Arene, [ezzz75@gmail.com](mailto:ezzz75@gmail.com), qui vous répond dans un délai d'un mois au plus. Sans pseudo, rien dans vos réponses ne permet de vous identifier, sauf ce que vous écririez vous-même dans un texte libre.

Sous le paragraphe, le lien vers la page détaillée, avec le libellé fixé par `questions.md`. Le lien ouvre la page sans quitter le questionnaire ni perdre les réponses (brouillon conservé, §4 du cadrage).

**Faits que les textes courts de `questions.md` doivent énoncer**, sans en ajouter d'autres :
- le pseudo est facultatif ;
- il sert seulement à vous contacter en MP pour approfondir un sujet ;
- il n'est jamais affiché ni publié ;
- il est effacé au plus tard deux mois après la fermeture ;
- on peut en demander la suppression à Bruno Arene, ezzz75@gmail.com, réponse sous un mois au plus ;
- sans pseudo, rien n'identifie le répondant, sauf ce qu'il écrit lui-même dans un texte libre (formulation à préférer à « vos réponses restent anonymes ») ;
- n'indiquer que son propre pseudo (proposition d'aide pour `questions.md`).

## 2. Page détaillée

Le texte ci-dessous est celui de la page, tel qu'il sera affiché.

---

### Vos données dans ce questionnaire

Ce questionnaire sert à orienter la nouvelle version de l'app HFR pour iPhone et iPad. Cette page explique ce qui est enregistré, pourquoi, combien de temps, qui le voit, et comment le faire effacer.

#### Qui est responsable

Bruno Arene, développeur de l'app, responsable du questionnaire et de ses données.
Contact : [ezzz75@gmail.com](mailto:ezzz75@gmail.com).

Le questionnaire est un projet personnel, sans but commercial. Il n'est pas lié à une entreprise ni à la régie du forum.

#### À quoi servent vos réponses

- Comprendre comment vous utilisez l'app et quelles idées vous paraissent utiles, pour choisir les évolutions de la nouvelle version.
- Vous montrer, à la fin, comment vos réponses se situent par rapport à celles des autres répondants.

Elles ne servent à rien d'autre : pas de publicité, pas de revente, pas de profil.

#### Ce qui est enregistré

Rien n'est enregistré sur le serveur avant que vous cliquiez sur « Envoyer ». À l'envoi, le serveur enregistre en une seule fois :

| Donnée | Pourquoi |
|---|---|
| Vos réponses aux questions, et l'ordre dans lequel les cartes d'idées vous ont été montrées | Le but du questionnaire. L'ordre des cartes est tiré au hasard ; il sert à vérifier qu'il n'influence pas les réponses |
| Vos textes libres : ce qui vous agace au quotidien dans l'app, ce qui compte le plus pour vous dans la lecture d'un sujet, une autre idée, le champ libre de la fin | Lire vos idées avec vos propres mots |
| Votre pseudo HFR, si vous le donnez | Pouvoir vous écrire en MP sur HFR pour approfondir un sujet avec vous, et rien d'autre. Il est rangé à part de vos réponses. C'est la seule donnée qui vous identifie directement, et elle est facultative |
| La date d'envoi, sans l'heure | Suivre la participation jour par jour |
| Le temps passé à répondre | Vérifier que le questionnaire tient dans le temps annoncé |
| La version du questionnaire | Savoir quel texte vous avez lu, s'il est corrigé en cours de route |
| Une empreinte du jeton de votre navigateur (voir plus bas) | Éviter qu'un même navigateur réponde plusieurs fois. Le jeton est tiré au hasard et ne dit rien de vous |
| Une empreinte de votre adresse IP | Même raison. L'adresse est transformée par un calcul à sens unique avec une clé secrète ; l'adresse elle-même n'est jamais enregistrée. Pour limiter les abus, cette empreinte est aussi calculée en mémoire à chaque visite, sans être enregistrée |

Toutes les questions sont facultatives. Si vous ne répondez pas à une question, rien n'est enregistré pour elle.

#### Ce qui reste dans votre navigateur

Deux choses sont gardées dans le stockage local de votre navigateur, sur votre appareil :
- le **brouillon** de vos réponses, pour qu'un rechargement de la page ne les perde pas ; il est effacé après l'envoi ;
- le **jeton**, un nombre tiré au hasard à l'ouverture du questionnaire et envoyé avec vos réponses, pour que le questionnaire sache que ce navigateur a déjà répondu.

Ce ne sont pas des cookies et rien n'est partagé avec un autre site. Vous pouvez les effacer à tout moment en supprimant les données du site dans les réglages de votre navigateur.

#### Ce qui n'est pas collecté

- **Pas d'adresse IP conservée au-delà de l'anti-abus** : seule l'empreinte décrite plus haut est gardée, et elle est effacée à la fermeture du questionnaire, le {date_fermeture}. Les journaux techniques du serveur ne contiennent pas votre adresse IP.
- **Pas de cookie**, ni du questionnaire ni d'un tiers.
- **Pas de mesure d'audience** : aucun outil de statistiques de visite, ni dans la page ni sur le serveur, aucun pixel, aucun bouton de réseau social.
- **Aucune requête vers un autre site** : la page et ses images viennent toutes du même serveur, et aucune police n'est téléchargée.
- **Pas de compte** : vous ne vous connectez pas, et le questionnaire n'a aucun lien avec votre compte HFR. Il ne vérifie pas le pseudo que vous tapez.
- **Pas d'adresse e-mail**, sauf si vous écrivez vous-même pour exercer vos droits.

#### Qui voit quoi

- **Bruno Arene** est le seul à voir les pseudos, et le seul à accéder aux réponses telles qu'elles sont enregistrées sur le serveur.
- **Pour l'analyse**, Bruno prépare une copie des réponses sans aucun pseudo :
  - chaque pseudo est remplacé par un identifiant tiré au hasard ;
  - la table qui relie un pseudo à son identifiant reste sur le serveur, et n'est jamais donnée à personne ;
  - les textes libres sont relus, et tout pseudo ou détail qui permettrait de reconnaître quelqu'un en est retiré.

  Tant que cette table existe, Bruno peut relier la copie à un pseudo : vos réponses ne sont donc pas anonymes pour lui, mais elles ne portent plus votre pseudo (on dit qu'elles sont « pseudonymisées »).
- **Seule cette copie sans pseudo** peut être lue par l'autre développeur de l'app, et confiée à un assistant d'intelligence artificielle, un service en ligne d'une société tierce, qui aide Bruno à faire la synthèse. Ni l'un ni l'autre ne reçoit la table de correspondance.
- **L'écran de fin** montre, après {seuil_statistiques} réponses, la répartition des réponses aux questions à choix, en pourcentages arrondis. Il ne montre jamais un texte libre, un pseudo, ni le temps passé.
- **Les résultats publiés** dans le dépôt public du projet ne contiennent que des chiffres d'ensemble sur les questions à choix. Aucun texte libre n'est publié, même en extrait.
- **L'hébergeur du serveur** a un accès technique à la machine, mais n'accède pas aux données dans le cadre normal de son service.
- Personne d'autre : rien n'est vendu, prêté, ni transmis à quelqu'un d'autre que ceux cités ici.

#### Où sont les données

Vos réponses sont stockées en France, dans l'Union européenne, sur un serveur loué par Bruno. La copie d'analyse sans pseudo reste sur l'ordinateur de Bruno et auprès de l'autre développeur ; elle n'est jamais déposée dans le dépôt public du projet.

Seuls des extraits de cette copie, sans pseudo ni détail permettant de vous reconnaître, peuvent être envoyés à l'assistant d'intelligence artificielle, dont le service peut se trouver hors de l'Union européenne.

#### Combien de temps

| Donnée | Effacée le |
|---|---|
| Empreintes d'adresse IP et de jeton, et la clé secrète qui sert à les calculer | {date_fermeture}, à la fermeture du questionnaire |
| Pseudos, et la table qui les relie aux identifiants d'analyse | Au plus tard le {date_effacement}, deux mois après la fermeture |
| Toutes les réponses, textes libres compris, et toutes les copies d'analyse | Au plus tard le {date_effacement}, en même temps que les pseudos |
| Brouillon dans votre navigateur | Après l'envoi, ou quand vous effacez les données du site |
| Jeton dans votre navigateur | Quand vous effacez les données du site |

Après le {date_effacement}, il ne reste plus rien du questionnaire sur le serveur ni dans les copies d'analyse : seuls subsistent les résultats d'ensemble publiés, des chiffres sans aucun texte libre ni pseudo. Ce que votre navigateur garde de son côté, vous seul pouvez l'effacer.

#### Vos droits

Si vous avez laissé votre pseudo, vous pouvez à tout moment demander :
- à **voir** ce qui est enregistré avec votre pseudo, et à en recevoir une copie ;
- à **corriger** ou **effacer** votre pseudo, ou vos réponses avec, y compris dans les copies d'analyse ;
- à **retirer** votre pseudo plus tôt que prévu ;
- à vous **opposer** à l'utilisation de vos réponses, ou à en demander la **limitation**, c'est-à-dire qu'elles soient gardées sans être utilisées.

Écrivez à [ezzz75@gmail.com](mailto:ezzz75@gmail.com) en indiquant votre pseudo. Comme le questionnaire ne vérifie pas les pseudos, Bruno peut vous demander de confirmer la demande par MP sur HFR depuis ce compte : c'est la seule façon de s'assurer qu'elle vient bien de vous. Il répond dans un délai d'un mois au plus.

Si vous avez répondu **sans pseudo**, vos réponses ne sont reliées à rien qui permette de les retrouver : il est donc impossible de les montrer, de les corriger ou de les effacer à la demande. Elles sont effacées comme les autres, au plus tard le {date_effacement}.

Si vous estimez que vos données ne sont pas traitées correctement, écrivez d'abord à Bruno. Vous pouvez aussi vous adresser à la CNIL, l'autorité française de protection des données ([cnil.fr](https://www.cnil.fr)).

#### Pourquoi c'est permis

Pour le pseudo, parce que vous choisissez de le donner : vous pouvez le retirer quand vous voulez, comme indiqué plus haut. Pour le reste, parce que l'intérêt du projet est d'améliorer l'app, que les données gardées sont réduites au strict nécessaire, et que vous pouvez vous y opposer.

#### Si cette page change

Toute modification est datée ici. Elle ne s'applique pas aux réponses déjà envoyées si elle réduit vos droits.

Dernière mise à jour : {date_mise_a_jour}.

---

## 3. Cohérence avec le cadrage

| Engagement de la mention | Garanti par `cadrage-construction.md` §4 |
|---|---|
| Rien n'est stocké avant l'envoi | Oui : « Envoi en une fois à la fin » |
| Jeton aléatoire et empreinte IP salée, effacés à la fermeture | Oui : « Anti-doublon sans compte » |
| Aucune requête vers un autre site, donc pas de cookie tiers ni de police téléchargée | Oui : « Front statique, sans CDN tiers ni police distante » |
| Pas de mesure d'audience | **Non** : l'absence de domaine tiers n'exclut ni une mesure hébergée sur le même serveur, ni des statistiques tirées des journaux. Exigence R12 |
| Brouillon gardé dans le navigateur | Oui : « Brouillon conservé dans le navigateur » |
| Écran de fin : questions fermées, pourcentages arrondis, jamais de texte libre ni de pseudo, après le seuil | Oui : « Écran de fin », seuil de 10 réponses (D3 révisée le 8 novembre 2026) |
| Pseudos effacés à la date annoncée | Oui : « Procédure de retrait » |

Les engagements suivants ne sont pas garantis par §4. Ils deviennent des **exigences pour la spécification #633**, sans modifier le cadrage :

| # | Exigence | Pourquoi la mention en a besoin |
|---|---|---|
| R1 | Les journaux du serveur et du proxy n'enregistrent jamais l'adresse IP, sous aucune forme, ni en clair ni en empreinte | « Les journaux techniques du serveur ne contiennent pas votre adresse IP » |
| R2 | Le formulaire ne pose aucun cookie : jeton et brouillon sont dans le stockage local | « Pas de cookie », et pas de bandeau de consentement à prévoir |
| R3 | Le brouillon est effacé du navigateur après un envoi réussi | « Il est effacé après l'envoi » |
| R4 | Les empreintes d'IP et de jeton ne sont jamais exportées ; la clé de salage est détruite à la fermeture, avec les empreintes ; l'empreinte calculée pour la limitation de débit reste en mémoire ; la clé et les empreintes ne figurent dans aucune sauvegarde (à défaut, les sauvegardes qui les contiennent sont détruites à la fermeture), et une restauration après la fermeture ne peut pas les réintroduire | « Effacées à la fermeture » doit être vrai aussi dans les sauvegardes, qui sinon les garderaient jusqu'à `{date_effacement}` |
| R5 | `{date_effacement}` est calculée à partir de la date de fermeture (deux mois après), sans réglage séparé ; un effacement manuel plus tôt reste possible, d'où « au plus tard » dans la mention ; après la première réponse reçue, la date de fermeture peut être avancée mais jamais repoussée, pour qu'aucune réponse ne soit gardée au-delà de la date déjà annoncée ; `{date_mise_a_jour}` et `{seuil_statistiques}` viennent de la même configuration ; la page détaillée affiche ces valeurs depuis cette configuration | Les dates et le seuil annoncés sont ceux qui s'appliquent |
| R6 | Le service efface automatiquement, au plus tard à `{date_effacement}`, toutes les réponses, les pseudos et la table de correspondance (R9) ; une procédure documentée couvre les sauvegardes du serveur et les copies d'analyse, y compris celle de l'autre développeur ; seuls les résultats d'ensemble de R11 sont gardés | « Effacées le {date_effacement} » doit être vrai partout, sauvegardes comprises |
| R7 | Une commande retrouve, montre, corrige ou efface les réponses d'un pseudo donné, et donne son identifiant d'analyse pour corriger ou effacer les copies d'analyse déjà faites | Exercer les droits, « y compris dans les copies d'analyse » |
| R8 | La page détaillée est servie par le formulaire lui-même et s'ouvre sans perdre le brouillon | Le répondant la lit au moment où il décide de donner son pseudo |
| R9 | La copie d'analyse est pseudonymisée côté serveur, sans identifiant direct côté lecteurs : chaque réponse porte un identifiant tiré au hasard, pas la clé interne de la base ; la table de correspondance pseudo ↔ identifiant reste sur le serveur, n'est dans aucune copie, et elle est effacée avec les pseudos (R6) | « Chaque pseudo est remplacé par un identifiant tiré au hasard » et « la table reste sur le serveur » |
| R10 | Les textes libres de la copie d'analyse peuvent être corrigés avant analyse (retrait des détails identifiants), sans toucher aux réponses enregistrées ; la copie garde la trace des textes relus | « Les textes libres sont relus » avant toute analyse |
| R11 | Un export des résultats d'ensemble, seul destiné à la publication : questions fermées seulement, en chiffres agrégés, sans texte libre, pseudo, identifiant, temps passé ni ordre des cartes ; aucun chiffre publié pour une question ou un groupe de moins de 5 répondants, ni de complément qui permettrait de le retrouver ; il est le seul jeu de données gardé après `{date_effacement}` | « Aucun texte libre n'est publié » et « seuls subsistent les résultats d'ensemble publiés » |
| R12 | Aucune mesure d'audience, ni dans la page ni sur le serveur : pas d'outil de statistiques de visite, et des journaux sans adresse IP, agent utilisateur ni référent | « Pas de mesure d'audience, ni dans la page ni sur le serveur » |
| R13 | Une réponse peut être marquée « limitée » sur demande (limitation ou opposition, sans effacement) : elle reste stockée mais sort des statistiques de l'écran de fin, des copies d'analyse suivantes et de l'export de R11 ; les copies déjà faites sont corrigées grâce à l'identifiant d'analyse donné par R7 | « Qu'elles soient gardées sans être utilisées » et « vous opposer à l'utilisation de vos réponses » |

Pour la revue de sécurité et de vie privée (#635) : vérifier chacun de ces points sur le service en ligne, et que les copies d'analyse restent hors du dépôt public.

## 4. Décisions du PO

Toutes prises le 8 novembre 2026.

| # | Point | Décision |
|---|---|---|
| V1 | À quoi sert le pseudo | Seulement contacter un participant en MP pour approfondir un sujet si besoin |
| V2 | Durée de conservation des pseudos | Courte et fixe : deux mois après la fermeture |
| V3 | Durée de conservation des réponses sans pseudo | Effacées deux mois après la fermeture, comme les pseudos ; seuls les résultats d'ensemble publiés restent |
| V4 | Assistant d'intelligence artificielle pour l'analyse | Réponses pseudonymisées avant toute analyse : pseudo remplacé par un identifiant aléatoire, table de correspondance gardée sur le serveur et jamais transmise, textes libres relus. Exigences R9 et R10 |
| V5 | Extraits de textes libres dans les résultats publics | Refusé : aucun extrait publié ; les textes libres restent internes (Bruno, l'autre développeur et les assistants d'IA, sous forme pseudonymisée) |
| V6 | Pays du serveur | France, dans l'Union européenne, aucun hébergement hors UE. Seuls des extraits pseudonymisés peuvent aller au service de l'assistant d'IA, qui peut les traiter hors UE |
| V7 | Délai de réponse aux demandes | Un mois au plus |
| D3 | Seuil d'affichage des statistiques de l'écran de fin | 10 réponses (révisé, d'abord 20) ; la mention l'affiche par `{seuil_statistiques}` |
| — | Partage des textes du pseudo | `questions.md` possède les textes courts (libellé, aide, lien), `donnees.md` les faits, le paragraphe au-dessus du champ et la page détaillée |

---

_Rédigé par Opus 5.5 pour le PO (Bruno), relu par Fable 5.1._
