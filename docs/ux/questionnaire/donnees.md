# Mention sur les données personnelles du questionnaire

Date : 8 novembre 2026. Livrable de l'issue #630 (UX-06). Statut : **proposition, à valider par le PO**.

Ce document contient les deux textes affichés aux répondants :
- le **texte court** placé au-dessus du champ pseudo facultatif (`I1`, à la fin du questionnaire, décision D2) ;
- la **page détaillée**, ouverte depuis l'accueil (`E0`) et depuis le texte court.

Il suit les contraintes de `cadrage-construction.md` §4. Les éléments entre accolades, par exemple `{date_fermeture}`, sont des valeurs de configuration du formulaire : la réalisation (#634) les remplit à partir de la même configuration que la date de fermeture, pour que la mention et le formulaire ne divergent jamais. Les points qui attendent le PO sont regroupés à la fin, section « Points à valider par le PO ».

## 1. Texte court, au-dessus du champ pseudo

> **Votre pseudo HFR (facultatif)**
>
> Si vous le laissez, seul Bruno, qui mène ce questionnaire, le verra, pour pouvoir vous écrire en MP sur HFR si une réponse mérite d'être précisée. Il n'est jamais affiché ni publié, et il sera effacé le {date_suppression_pseudos}. Sans pseudo, vos réponses restent anonymes.
>
> Vos données et vos droits (lien vers la page détaillée)

Libellé du champ : « Pseudo HFR ». Texte d'aide sous le champ : « Indiquez seulement votre propre pseudo. »

Le lien ouvre la page détaillée ci-dessous sans quitter le questionnaire ni perdre les réponses (brouillon conservé, §4 du cadrage).

Lien sur l'écran d'accueil `E0`, à reprendre par la rédaction (#629) : « Vos données : ce qui est gardé et pourquoi ».

## 2. Page détaillée

Le texte ci-dessous est celui de la page, tel qu'il sera affiché.

---

### Vos données dans ce questionnaire

Ce questionnaire sert à orienter la nouvelle version de l'app HFR pour iPhone et iPad. Cette page explique ce qui est enregistré, pourquoi, combien de temps, et comment le faire effacer.

#### Qui est responsable

Bruno Arene, développeur de l'app, responsable du questionnaire et de ses données.
Contact : [ezzz75@gmail.com](mailto:ezzz75@gmail.com).

Le questionnaire est un projet personnel, sans but commercial. Il n'est pas lié à une entreprise ni à la régie du forum.

#### À quoi servent vos réponses

- Comprendre comment vous utilisez l'app et quelles idées vous paraissent utiles, pour choisir les évolutions de la nouvelle version.
- Vous montrer, à la fin, comment vos réponses se situent par rapport à celles des autres répondants.

Elles ne servent à rien d'autre : pas de publicité, pas de revente, pas de profil.

#### Ce qui est enregistré

| Donnée | Quand | Pourquoi |
|---|---|---|
| Vos réponses aux questions | À l'envoi, en une seule fois | Le but du questionnaire. Rien n'est enregistré sur le serveur avant que vous cliquiez sur « Envoyer » |
| Vos textes libres (idée, champ libre, « ce qui vous manquerait ») | À l'envoi | Lire vos idées avec vos propres mots |
| Votre pseudo HFR, si vous le donnez | À l'envoi | Pouvoir vous écrire en MP sur HFR pour préciser une réponse. C'est la seule donnée qui vous identifie, et elle est facultative |
| Un jeton aléatoire | À l'ouverture du questionnaire | Éviter qu'une même personne réponde plusieurs fois. Il est tiré au hasard et ne dit rien de vous |
| Une empreinte de votre adresse IP | À l'envoi | Même raison. L'adresse est transformée par un calcul à sens unique avec une clé secrète ; l'adresse elle-même n'est pas enregistrée avec vos réponses |
| La date et l'heure d'envoi | À l'envoi | Suivre la participation et repérer les envois en rafale |

Toutes les questions sont facultatives. Si vous ne répondez pas à une question, rien n'est enregistré pour elle.

#### Ce qui reste dans votre navigateur

Deux choses sont gardées dans le stockage local de votre navigateur, sur votre appareil :
- le **brouillon** de vos réponses, pour qu'un rechargement de la page ne les perde pas ; il est effacé après l'envoi ;
- le **jeton aléatoire**, pour que le questionnaire sache que vous avez déjà répondu.

Ce ne sont pas des cookies et rien n'est partagé avec un autre site. Vous pouvez les effacer à tout moment en supprimant les données du site dans les réglages de votre navigateur.

#### Ce qui n'est pas collecté

- **Pas d'adresse IP conservée au-delà de l'anti-abus** : seule l'empreinte décrite plus haut est gardée, et elle est effacée à la fermeture du questionnaire, le {date_fermeture}.
- **Pas de cookie**, ni du questionnaire ni d'un tiers.
- **Pas de mesure d'audience** : aucun outil de statistiques de visite, aucun pixel, aucun bouton de réseau social.
- **Aucune requête vers un autre site** : la page, ses images et ses polices viennent toutes du même serveur.
- **Pas de compte** : vous ne vous connectez pas, et le questionnaire n'a aucun lien avec votre compte HFR. Il ne vérifie pas le pseudo que vous tapez.
- **Pas d'adresse e-mail**, sauf si vous écrivez vous-même pour exercer vos droits.

#### Qui voit quoi

- **Bruno** est le seul à accéder aux réponses complètes, pseudos compris.
- **L'écran de fin** montre, après {seuil_statistiques} réponses, la répartition des réponses aux questions à choix, en pourcentages arrondis. Il ne montre jamais un texte libre ni un pseudo.
- **Les résultats publiés** dans le dépôt public du projet ne contiennent que des chiffres d'ensemble et, éventuellement, de courts extraits de textes libres, relus pour qu'ils ne contiennent ni pseudo ni détail qui permette de reconnaître quelqu'un.
- **Pour l'analyse**, Bruno peut se faire aider d'un assistant d'intelligence artificielle. Il ne lui transmet que des réponses sans pseudo.
- Personne d'autre : rien n'est vendu, prêté ni transmis.

#### Où sont les données

Sur un serveur loué par Bruno chez {hebergeur}, situé {pays_hebergement}. Les exports utilisés pour l'analyse restent sur l'ordinateur de Bruno ; ils ne sont jamais déposés dans le dépôt public du projet.

#### Combien de temps

| Donnée | Effacée le |
|---|---|
| Empreinte d'adresse IP | {date_fermeture}, à la fermeture du questionnaire |
| Pseudos | {date_suppression_pseudos}, deux mois après la fermeture |
| Réponses sans pseudo, textes libres compris | {date_suppression_reponses}, un an après la fermeture. Seuls les résultats d'ensemble publiés restent après cette date |
| Brouillon dans votre navigateur | Après l'envoi, ou quand vous effacez les données du site |
| Jeton dans votre navigateur | Quand vous effacez les données du site |

Une fois le pseudo effacé, plus rien ne relie vos réponses à vous.

#### Vos droits

Vous pouvez à tout moment demander :
- à **voir** ce qui est enregistré avec votre pseudo ;
- à **corriger** ou **effacer** votre pseudo, ou vos réponses avec ;
- à **retirer** votre pseudo plus tôt que prévu.

Écrivez à [ezzz75@gmail.com](mailto:ezzz75@gmail.com) en indiquant votre pseudo. Comme le questionnaire ne vérifie pas les pseudos, Bruno peut vous demander de confirmer la demande par MP sur HFR depuis ce compte : c'est la seule façon de s'assurer qu'elle vient bien de vous. Il répond dans un délai d'un mois au plus.

Si vous avez répondu **sans pseudo**, vos réponses ne sont reliées à rien qui vous identifie : il est donc impossible de les retrouver pour les montrer ou les effacer.

Si vous estimez que vos données ne sont pas traitées correctement, écrivez d'abord à Bruno. Vous pouvez aussi vous adresser à la CNIL, l'autorité française de protection des données ([cnil.fr](https://www.cnil.fr)).

#### Pourquoi c'est permis

Pour le pseudo, parce que vous choisissez de le donner : vous pouvez le retirer quand vous voulez, comme indiqué plus haut. Pour le reste, parce que l'intérêt du projet est d'améliorer l'app, et que les données gardées sont réduites au strict nécessaire.

#### Si cette page change

Toute modification est datée ici. Elle ne s'applique pas aux réponses déjà envoyées si elle réduit vos droits.

Dernière mise à jour : {date_mise_a_jour}.

---

## 3. Cohérence avec le cadrage

| Engagement de la mention | Garanti par `cadrage-construction.md` §4 |
|---|---|
| Rien n'est stocké avant l'envoi | Oui : « Envoi en une fois à la fin » |
| Jeton aléatoire et empreinte IP salée, effacée à la fermeture | Oui : « Anti-doublon sans compte » |
| Aucune requête vers un autre site, donc pas de cookie tiers ni de mesure d'audience | Oui : « Front statique, sans CDN tiers ni police distante » |
| Brouillon gardé dans le navigateur | Oui : « Brouillon conservé dans le navigateur » |
| Écran de fin : questions fermées, pourcentages arrondis, jamais de texte libre ni de pseudo, après le seuil | Oui : « Écran de fin », seuil de 20 réponses (D3) |
| Pseudos effacés à la date annoncée | Oui : « Procédure de retrait » |

Les engagements suivants ne sont pas garantis par §4. Ils deviennent des **exigences pour la spécification #633**, sans modifier le cadrage :

| # | Exigence | Pourquoi la mention en a besoin |
|---|---|---|
| R1 | Les journaux du serveur et du proxy n'enregistrent pas l'adresse IP en clair, ou l'effacent au bout de 7 jours au plus | « Pas d'adresse IP conservée au-delà de l'anti-abus ». Si un journal la garde plus longtemps, la mention doit le dire |
| R2 | Le formulaire ne pose aucun cookie : jeton et brouillon sont dans le stockage local | « Pas de cookie », et pas de bandeau de consentement à prévoir |
| R3 | Le brouillon est effacé du navigateur après un envoi réussi | « Il est effacé après l'envoi » |
| R4 | L'empreinte IP n'est jamais exportée et la clé de salage est détruite à la fermeture, avec les empreintes | « Effacée à la fermeture ». Sans la clé, les empreintes restantes dans une sauvegarde ne permettent plus de retrouver une adresse |
| R5 | Trois dates configurables à côté de la date de fermeture : suppression des pseudos, suppression des réponses, mise à jour de la mention ; la page détaillée les affiche depuis cette configuration | Les dates annoncées et les dates appliquées restent les mêmes |
| R6 | La suppression des pseudos et des réponses à leur date est une commande ou une tâche documentée, qui couvre aussi les sauvegardes du serveur et les exports | « Effacé le » doit être vrai partout, sauvegardes comprises |
| R7 | Une commande permet de retrouver, corriger ou effacer les réponses d'un pseudo donné | Exercer les droits de la section « Vos droits » |
| R8 | La page détaillée est servie par le formulaire lui-même et s'ouvre sans perdre le brouillon | Le répondant la lit au moment où il décide de donner son pseudo |

Pour la revue de sécurité et de vie privée (#635) : vérifier chacun de ces points sur le service en ligne, et que les exports restent hors du dépôt public.

## 4. Points à valider par le PO

| # | Point | Proposition |
|---|---|---|
| V1 | À quoi sert le pseudo | Vous écrire en MP pour préciser une réponse, rien d'autre. Si le pseudo doit aussi servir, par exemple, à inviter à un test ou à pondérer les réponses des habitués, la mention doit le dire |
| V2 | Durée de conservation des pseudos | Effacés deux mois après la fermeture : assez pour relire les réponses et écrire les MP, sans garder les pseudos plus longtemps que l'analyse |
| V3 | Durée de conservation des réponses sans pseudo | Un an après la fermeture, puis effacement ; seuls les résultats publiés restent |
| V4 | Assistant d'intelligence artificielle pour l'analyse (UX-14 est prévu avec Opus) | Le dire, et ne lui transmettre que des réponses sans pseudo. Sinon, retirer la phrase et faire l'analyse sans assistant |
| V5 | Extraits de textes libres dans `resultats.md`, dépôt public | Autorisés, courts et relus. Sinon, ne publier que des chiffres et des thèmes |
| V6 | Hébergeur et pays du VPS (lié à D4) | À fournir pour remplir `{hebergeur}` et `{pays_hebergement}`. Si le serveur est hors de l'Union européenne, la mention doit le dire |
| V7 | Délai de réponse aux demandes | Un mois au plus, le délai légal |

---

_Rédigé par Opus 5.5 pour le PO (Bruno), relecture Fable 5.1 attendue._
