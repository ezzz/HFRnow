# Cadrage de la construction du questionnaire

Date : 8 novembre 2026. Ce document cadre la construction du questionnaire, du contenu au formulaire en ligne. Il complète les briefs par lot de `docs/ux/cadrage-agents-questionnaire.md` §3 sans les remplacer. En cas d'écart, les issues #628 à #635 font foi.

Il apporte trois choses que les briefs n'ont pas :
- le parcours écran par écran, avec un identifiant stable par question ;
- les contrats entre les lots, pour que le texte, les visuels et le code restent alignés ;
- les décisions et informations encore attendues du PO.

## 1. Verdict : la construction peut démarrer

| Entrée | Où | État |
|---|---|---|
| Contenu du questionnaire | `docs/ux/tri-m5-decisions.md` §4 | Complet : profil, ouverture, deux thèmes, dix cartes, question MP, champ libre |
| Contrôle des propositions classées Non | tri, §4.7 | Fait le 7 novembre 2026 |
| Décisions pratiques | `docs/ux/plan-preparation-questionnaire.md` §2 | Sept décisions tranchées |
| Lots et suivi | Issues #629 à #635, parapluie #628 | Créés, quatre prêts |
| Archive du cadrage | `docs/ux/`, fusionnée le 8 novembre 2026 | Fait |

Rien ne bloque la vague 1. Le sous-domaine ne bloque que la mise en ligne restreinte (#635). Les décisions de la section 6 se prennent pendant la vague 1, avant la fin de la rédaction et de la spécification.

## 2. Le parcours, écran par écran

Un écran par bloc, une barre de progression, toutes les questions facultatives. Budget : 7 minutes au plus pour un profil iPad, 5 minutes pour un profil iPhone qui ne voit pas le thème 2. Les budgets du tableau totalisent 6 min 20 s pour un profil iPad et 4 min 20 s pour un profil iPhone, ce qui laisse une marge pour les visuels et les vidéos.

| Écran | Identifiants | Contenu | Format | Condition | Visuel | Budget |
|---|---|---|---|---|---|---|
| Accueil | `E0` | Introduction de trois lignes, lien vers la mention sur les données | Texte | — | — | 15 s |
| Profil | `P1` `P2` `P3` | Appareil, usage du forum, ancienneté | Choix simple ×3 | — | — | 30 s |
| Ouverture | `O1` | Rester · petites touches · oser | Choix simple | — | — | 10 s |
| Thème 1 | `L1` `L2` | Choix du scénario de lecture, puis « Qu'est-ce qui vous manquerait ? » | Choix simple, texte court | — | Capture actuelle, deux scénarios | 60 s |
| Thème 2, partie A | `D1` | Sections de la barre latérale : garder, ordonner, dépliable | Tri de cartes | `P1` vaut iPad, Duo ou plusieurs | Cartes des neuf sections | 75 s |
| Thème 2, partie B | `D2` | Trois dispositions | Choix simple | Même condition | Capture actuelle, deux maquettes, vidéos Duo | 45 s |
| Cartes | `C01` à `C10` | Dix idées, trois réactions chacune | Cartes de réaction | — | Aucun, une phrase par carte | 80 s |
| Idée | `C11` | « Ces idées vous en inspirent une autre ? » | Texte court | — | — | 15 s |
| Messages privés | `M1` | Quatre réponses de la question MP | Choix simple | — | — | 15 s |
| Champ libre | `F1` | 280 caractères | Texte | — | — | 20 s |
| Pseudo | `I1` | Pseudo HFR facultatif, mention courte au-dessus | Texte | — | — | 15 s |
| Fin | `E1` | Remerciement, réponses du répondant comparées à celles de la communauté | Lecture seule | — | Graphiques simples | — |

Le pseudo est demandé à la fin plutôt qu'au début : le répondant décide après avoir vu ce qu'il a écrit, et l'anonymat par défaut n'influence pas les réponses. C'est la décision D2 de la section 6.

L'ordre des cartes `C01` à `C10` est tiré au hasard pour chaque répondant, afin que la fatigue ne pénalise pas toujours les mêmes idées.

## 3. Contrats entre les lots

### 3.1 Identifiants stables

Les identifiants de la section 2 sont fixés par ce document. Ils servent partout :
- dans `docs/ux/questionnaire/questions.md` (#629) ;
- dans le modèle de données de la spécification (#633) ;
- dans le fichier de contenu et l'export du formulaire (#634) ;
- dans l'analyse des résultats.

Chaque réponse possible porte aussi un code stable, en minuscules ASCII, par exemple `iphone`, `ipad`, `duo`, `plusieurs` pour `P1`. La rédaction choisit les codes, la spécification les reprend. Changer un identifiant ou un code après la vague 1 demande de modifier ce document.

### 3.2 Forme de `questions.md`

Un bloc par identifiant, toujours dans le même ordre :

```markdown
### P1
- Section du tri : §4.1
- Question : Sur quel appareil utilisez-vous surtout l'app ?
- Réponses : `iphone` iPhone · `ipad` iPad · `duo` iPhone Duo · `plusieurs` Plusieurs
- Aide : (facultative)
- Condition : (aucune)
```

La réalisation (#634) transcrit ces blocs dans un fichier de contenu sous `tooling/ux-survey/`. Un test automatisé vérifie que les identifiants, les codes et les libellés des deux fichiers sont identiques. Ainsi, une correction de libellé validée par le PO ne se perd pas entre le document et le code.

### 3.3 Visuels

- **Nommage** : `<identifiant>-<scénario>-<appareil>.<extension>`, par exemple `L1-pages-ameliorees-iphone.png` ou `D2-cote-a-cote-duo.mp4`.
- **Images** : PNG ou WebP, 300 Ko au plus chacune.
- **Vidéos** : MP4 H.264, 10 secondes au plus, sans son, 2 Mo au plus, avec une image d'attente.
- **Inventaire** : un fichier `visuels/inventaire.md` liste chaque visuel avec son texte alternatif, le sujet utilisé et la version de l'app.
- **Contenu** : pseudos masqués, un même sujet public par thème, aucune proposition classée Non visible.

## 4. Contraintes de construction à reprendre dans la spécification

La spécification (#633) choisit la technique. Elle doit respecter ces contraintes, qui découlent des décisions du PO.

**Hébergement**
- Un seul service avec une base SQLite, livré en conteneur ou en binaire, pour rester portable tant que le VPS n'est pas décrit (décision D4).
- Front statique, sans CDN tiers ni police distante : aucune requête vers un autre domaine.
- Page de 200 Ko au plus hors visuels, utilisable sur une connexion mobile faible.

**Accessibilité et confort**
- Le tri de cartes doit avoir une alternative au glisser-déposer : boutons « monter » et « descendre », utilisables au lecteur d'écran.
- Respect de la taille de texte du navigateur et du mode sombre du système.
- Brouillon conservé dans le navigateur, pour qu'un rechargement ne perde pas les réponses.

**Données**
- Envoi en une fois à la fin : aucune réponse partielle n'est stockée.
- Anti-doublon sans compte : jeton aléatoire gardé dans le navigateur, et empreinte d'adresse IP salée, effacée à la fermeture du questionnaire.
- Export CSV et JSON avec les identifiants de la section 2 comme colonnes.

**Écran de fin**
- Chaque réponse du répondant est mise en regard de la répartition de la communauté (décision 2 du plan de préparation).
- Statistiques affichées seulement après un seuil de réponses (décision D3).
- Questions fermées seulement, en pourcentages arrondis.
- Jamais de texte libre ni de pseudo.

**Cycle de vie**
- Date de fermeture configurable. Après cette date, le formulaire affiche « questionnaire fermé » et les statistiques finales.
- Procédure de retrait : export, puis suppression des pseudos à la date annoncée par la mention sur les données (#630).

## 5. Thème 1 : montrer le réel plutôt que des maquettes

Les répondants utilisent l'app 4.0.4. Or plusieurs améliorations du scénario « pages améliorées » existent déjà dans le lecteur de SwiftHFR : messages de la liste noire repliables, séparateur des nouveaux messages, taille de texte iOS, contrôles de page.

Recommandation pour #632 : capturer SwiftHFR dans le simulateur pour chaque amélioration qui existe déjà, et ne dessiner une maquette que pour le reste, en particulier le GIF « lecture continue ». C'est plus rapide, plus honnête, et cela ne promet rien qui ne soit pas faisable avec la WebView. Le lot vérifie d'abord, amélioration par amélioration, ce que SwiftHFR affiche réellement sur le sujet choisi, et garde le même sujet et le même thème que les captures de #631.

## 6. Décisions et informations attendues du PO

| # | Sujet | Recommandation | Nécessaire avant |
|---|---|---|---|
| D1 | Ajouter une réponse « Garder les pages comme aujourd'hui » au thème 1 (`L1`) | Oui : la règle « comme aujourd'hui » s'applique partout, et la réponse se lit avec `O1` | Fin de #629 |
| D2 | Place du pseudo | À la fin, juste avant l'envoi | Fin de #629 |
| D3 | Seuil d'affichage des statistiques | 20 réponses | Fin de #633 |
| D4 | Description du VPS : système, proxy existant, Docker ou non | À fournir ; la spécification reste portable en attendant | Fin de #633 |
| D5 | Duo : appareil réel ou simulateur disponible pour les vidéos | À confirmer | Début de #631 pour la partie Duo |
| D6 | Cinq testeurs, dont au moins un sur iPad | Noms à réunir | Test, après #635 |

## 7. Écarts entre l'archive et les issues

Les agents suivent les issues. Pour mémoire :
- le brief d'UX-05 parle de huit cartes, l'issue #629 de dix, qui fait foi ;
- les briefs écrivent `visuals/`, les issues `visuels/`, qui fait foi ;
- le brief d'UX-10 ne cite pas UX-06 dans ses dépendances, l'issue #634 cite #630 ;
- le brief d'UX-11 porte le label `type: security`, l'issue #635 `type: chore`.

## 8. Après la construction : trois lots sans issue

Le plan de préparation décrit le test, la diffusion et l'analyse (§3, lots F et G), mais aucune issue ne les suit. Proposition, à créer avec l'accord du PO :

| Lot | Objet | Qui | Dépend de |
|---|---|---|---|
| UX-12 | Test à cinq : durée médiane sous 7 minutes, questions mal comprises, corrections | PO et Sonnet pour les corrections | #635, D6 |
| UX-13 | Ouverture deux semaines sur le topic HFR et dans la note TestFlight, relance à mi-parcours | PO, action publique | UX-12 |
| UX-14 | Analyse par profil dans `docs/ux/questionnaire/resultats.md` | Opus, relecture Fable | UX-13 |

## 9. Lancement de la vague 1

Quatre sessions en parallèle, une par issue. Chacune reçoit le même court brief : lire l'issue, la claimer, suivre ses consignes et ce document.

| Issue | Lot | Modèle | Hôte | Point d'attention |
|---|---|---|---|---|
| #629 | Rédaction | Sonnet, relecture Opus | cloud | Forme de la section 3.2, identifiants de la section 2, D1 et D2 |
| #630 | Données | Opus, relecture Fable | cloud | Cohérence avec la section 4 : empreinte IP, durée, retrait |
| #631 | Captures | Sonnet, relecture Opus | mac | Nommage de la section 3.3, D5 pour le Duo |
| #633 | Spécification | Opus, relecture Fable | cloud | Contraintes de la section 4, D3 et D4 |

La vague 2 (#632, maquettes) part dès que #631 est fusionnée, avec la recommandation de la section 5.
