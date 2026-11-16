# Retours de l'équipe et nouvelles idées : actions GitHub et questionnaire

Date : 7 novembre 2026. Sources :
- les réactions de François sur la page « Évolutions UX de HFRnow » ;
- trois idées nouvelles du PO.

Publié le 7 novembre 2026 avec l'accord du PO : nouvelles issues #624 (Alertes Qualitay dans le lecteur), #625 (réponse en bas du sujet), #626 (deux onglets pour les messages privés), #627 (Filtrer les posts) ; commentaires sur #509, #256, #422, #233, #234, #242, #418, #244, #150 et #243. Les textes destinés à GitHub sont en anglais, comme les issues du dépôt. Ils suivent ses conventions : titre `[SwiftHFR] M5: …`, section `### Summary` en tête, un label par axe.

**Recueil clos le 7 novembre 2026** : François est le seul autre développeur de l'équipe ; la page de réactions est fermée.

## 1. Synthèse

### 1.1 Retours de François

Aucun désaccord sur les 39 propositions : 31 « d'accord », 7 « à discuter », un commentaire sans réaction.

**Points à discuter.** Deux viennent de libellés mal compris : les modes du bouton + et le multi-fenêtre iPad. Les cinq autres n'ont pas de commentaire et demandent son avis :
- colonnes iPad et Duo ;
- vérification par l'app Raccourcis ;
- gestes identiques dans les listes ;
- teinte des lignes par drapeau ;
- actions rapides sur l'icône.

**Informations utiles :**
- précisions sur les notifications MP (#509) ;
- issue de parité avec Redface 2 pour les images (#513) ;
- thèmes saisonniers déjà en cours, avec des graphismes générés et un bêta-test proposé : LOT-166, #256, rangé en M4 et non en M5 ;
- MP à plusieurs destinataires faisable avant M5 ;
- « À suivre » activable et désactivable ;
- aperçu avant envoi utile seulement pour les gros messages ;
- repère « Nouveau » discret ;
- « On t'a cité » jugé peu utile.

### 1.2 Trois idées du PO

| Idée | Existant | Nature |
|---|---|---|
| **Alertes Qualitay visibles dans le sujet** : en lecture, un message signalé en Alerte Qualitay a un rendu propre qui l'identifie d'un coup d'œil | Le moteur sait vérifier les alertes d'un sujet (LOT-055) ; le lecteur propose déjà l'action « AQ » sur un message (LOT-134) ; aucun rendu dans le lecteur | Nouvelle fonction |
| **Réponse directe en bas du sujet**, comme dans Signal ou WhatsApp | La réponse rapide du bouton + existe et a été gardée fonctionnelle pour cela ; FEAT-006 et LOT-153 associent la barre de réponse et le plateau de citations | On sépare FEAT-006 : le plateau de citations reste Non, la barre de réponse redevient une piste |
| **Deux onglets au lieu de « Messages »** : un pour les MP à un seul destinataire, un pour les MP à plusieurs, qui sont de vrais sujets de collaboration privés | LOT-171, livré : réglage « Tout en un » ou « Deux listes », avec un sélecteur dans l'onglet Messages, « Tout en un » par défaut | Évolution de la barre d'onglets |

**Deux tensions à garder en tête :**
- La barre de réponse ajoute un élément au lecteur, ce qui va contre la ligne « place au contenu ». La piste à creuser est une barre qui n'apparaît qu'à la demande, ou en fin de page.
- Les deux onglets touchent la barre d'onglets, protégée par le principe « préserver ce qui marche » de `FEATURES.md`. Ce principe exige le soutien de la communauté, consigné sur l'issue : c'est un sujet pour le questionnaire.

## 2. Commentaires à ajouter sur les issues existantes

### #509 — Notifications MP fines

> Input from the team review (François, 2026-11-07), to fold into the acceptance criteria:
> - global on / off;
> - on / off for group MPs;
> - on / off per conversation (mute);
> - notify only on the **first** new message of a conversation, not on every unread one; the conversation re-arms once it has been read.
>
> Related product idea (PO, 2026-11-07): group MPs could get their own tab, see the new issue "Messages split into two tabs".

### #256 — LOT-166, thèmes saisonniers

> Team review (2026-11-07): the PO wants seasonal themes extended (one per season, optional automatic switch). François already has generated artwork and proposes an internal beta test to check it matches the PO's idea. Note: this lot is in M4 in `docs/FEATURES.md`, not M5.

### #422 — LOT-182, MP à plusieurs destinataires

> Team review (2026-11-07): PO decision is **yes, but not necessarily from a profile**. François says the Swift version could support several recipients before M5. To decide: move the "several recipients" part earlier and leave the "from a profile" entry out of scope.

### #233 et #234 — LOT-143 et LOT-144, « À suivre »

> PO decision (2026-11-07): **not on iPhone** (the iPhone layout is settled), **yes on iPad** where the space adds real value. François agrees and asks for an explicit opt-in / opt-out. Scope to update: iPad and unfolded iPhone Duo only, behind a setting.

### #242 — LOT-152, aperçu avant envoi

> PO decision (2026-11-07): not on iPhone, possibly on iPad. François sees little value in general ("editing after posting is easy") except for long messages such as a topic's first post. Proposed scope: iPad, and offered for long messages or the first post only.

### #418 — LOT-178, bannière « Nouveau »

> PO decision (2026-11-07): improve the first-unread marker, **without** a large banner. François: flags already land on the right message, so a discreet marker is enough. Proposed scope: a more visible separator, not a banner.

### #244 — LOT-154, « On t'a cité »

> PO decision (2026-11-07): hard to do, since HFR does not expose the information. François finds it of little use. Counter-proposal tracked in the new issue "Filter posts: easier to find and trigger". Proposed: close this lot as not planned once that issue exists.

### #150 et #243 — FEAT-006 et LOT-153

> PO decision (2026-11-07): the **quote tray** is out (quoting was reworked after 4.0 and the topic is closed). The **quick-reply bar** is kept as a separate idea, see the new issue "Reply at the bottom of a topic, messaging-app style". Proposed: narrow FEAT-006 to the bar, close LOT-153 as not planned for its tray part.

## 3. Nouvelles issues

### 3.1 Alertes Qualitay visibles dans le sujet

**Titre** : `[SwiftHFR] M5: Reader, highlight posts that carry a quality alert (AQ)`

**Labels** : `type: feature`, `area: app`, `priority: medium`, `difficulty: medium`, `status: on-hold`

```markdown
### Summary
As a reader, I want posts that carry a quality alert (Alerte Qualitaÿ) to stand out in the topic, so that I spot them at a glance while reading.

### Context
- The AQ client can check a topic for alerts (LOT-055, #81).
- The message menu already offers "AQ" on a post (LOT-134, #224).
- Nothing in the reader shows that a post was alerted.

### Proposal
- When a topic page is shown, mark each post that has an AQ: a distinct visual treatment (accent edge, badge or tint, to be designed), readable in light, dark and OLED themes, and announced by VoiceOver.
- Optional: tap the marker to see the alert's title and comment.
- A setting to turn the marker off.

### Open questions
- Does the per-topic AQ check give the alerted post ids for a whole page in one request? If not, what is the polite request budget per page?
- Treatment that respects the "room for content" guideline: a marker, not a block.

### Acceptance criteria (draft)
- [ ] Posts with an AQ are marked; others are not (tests on captured pages, no live call in tests).
- [ ] No extra request when the setting is off.
- [ ] Light, dark, OLED and Dynamic Type XL checked; VoiceOver label on the marker.
```

### 3.2 Réponse directe en bas du sujet

**Titre** : `[SwiftHFR] M5: Reply at the bottom of a topic, messaging-app style`

**Labels** : `type: feature`, `area: app`, `priority: medium`, `difficulty: medium`, `status: on-hold`

```markdown
### Summary
As a member reading a topic, I want to type a short reply at the bottom of the page, like in a messaging app, so that I answer without leaving the conversation.

### Context
- The quick reply behind the "+" button exists and was kept working for this purpose (legacy 4.0.1, `specifications.md`).
- FEAT-006 (#150) bundled this bar with a quote tray; the tray is out (PO, 2026-11-07), the bar is kept as this issue.

### Proposal
- A compact reply field at the bottom of the reader, using the quick-reply draft of the topic.
- To respect the "room for content" guideline: the field appears on demand (end of page, or a tap), not as a permanent bar; it grows into the full composer for long messages.
- Sends through the existing posting flow; same draft rules as the composer.

### Open questions
- On demand or always visible on iPad?
- Interaction with the page swipe and the bottom page controls.
- Subject of the user survey (reaction card).

### Acceptance criteria (draft)
- [ ] A reply typed in the field is posted to the current topic and the page shows it.
- [ ] The draft survives leaving and reopening the topic.
- [ ] Never resends automatically when the outcome of a send is unknown.
```

### 3.3 Deux onglets pour les messages privés

**Titre** : `[SwiftHFR] M5: Messages split into two tabs, one-to-one MPs and group MPs`

**Labels** : `type: feature`, `area: app`, `priority: low`, `difficulty: medium`, `status: needs-triage`

```markdown
### Summary
As a member who works with others in group MPs, I want group MPs in their own tab, so that these private collaboration topics are not mixed with one-to-one messages.

### Context
- LOT-171 (#297, done) offers a setting "Tout en un" (default) / "Deux listes" with a switch inside the Messages tab.
- Group MPs are read and answered like topics (LOT-171, LOT-130): they work as private topics hidden from the public forum.
- The tab bar Catégories / Favoris / Messages / Plus is protected by the "Preserve what works" principle (`docs/FEATURES.md`): a change needs the operator's approval and the community's support recorded here.

### Proposal
- Optional fifth tab, or a setting that replaces "Messages" by "MP" and "MP multiples".
- Each tab with its own unread badge.
- Default unchanged.

### Open questions
- Fifth tab or replacement? Behaviour on iPad sidebar.
- Community support: to be measured by the user survey before any work.

### Acceptance criteria (draft)
- [ ] Default layout unchanged for everyone who does not opt in.
- [ ] Badges per tab match the existing per-segment counts of LOT-171.
```

### 3.4 Filtrer les posts plus facile à trouver et à déclencher

Contre-proposition du PO à « On t'a cité », déjà actée dans le tri.

**Titre** : `[SwiftHFR] M5: Filter posts, easier to find and trigger`

**Labels** : `type: feature`, `area: app`, `priority: medium`, `difficulty: easy`, `status: on-hold`

```markdown
### Summary
As a reader of a long topic, I want to find the most quoted posts, or the posts of my whitelisted members, in one gesture, so that I catch up without reading every page.

### Context
- The filtered-posts flow and view exist (LOT-093 #185, LOT-114 #205).
- Counter-proposal to "On t'a cité" (LOT-154, #244), which HFR cannot support.

### Proposal
- A visible entry in the topic (not only in a menu), and a clearer result view.
- Keep the request budget and throttling of LOT-093.

### Acceptance criteria (draft)
- [ ] The filter is reachable in one tap from a topic.
- [ ] Same results as today on captured pages.
```

## 4. Ajouts au questionnaire UX

Modifications de `docs/ux/tri-m5-decisions.md` §4 :

1. **Deux cartes de réaction en plus**, soit dix au total :
   - **Alertes Qualitay dans le sujet** : « Repérer d'un coup d'œil, en lisant un sujet, les messages signalés en Alerte Qualitay. »
   - **Répondre en bas du sujet** : « Écrire une réponse courte directement en bas du sujet, comme dans une messagerie, sans ouvrir l'éditeur. »
2. **Une question dédiée aux messages privés**, après les cartes, parce qu'elle touche la barre d'onglets et que le principe « préserver ce qui marche » demande le soutien de la communauté :
   - « Comment préférez-vous retrouver vos messages privés ? »
   - Réponses : « Un seul onglet, comme aujourd'hui » · « Deux listes dans l'onglet Messages, déjà possible en réglage » · « Deux onglets : MP et MP à plusieurs » · « Je n'utilise pas les MP à plusieurs ».
3. **Clarification** : la barre de réponse relance seulement la moitié « réponse » de FEAT-006. Le plateau de citations reste classé Non et n'apparaît pas dans le questionnaire.

Volume : environ 21 interactions, toujours sous 7 minutes.

## 5. Ordre de publication proposé

1. Fait : quatre nouvelles issues créées, #624 à #627.
2. Fait : commentaires publiés sur les dix issues existantes, avec renvoi vers les numéros créés.
3. Répondre à François sur ses points « à discuter », comme prévu.
4. Mettre à jour le questionnaire (§4).

Toutes ces publications sont faites par le PO, ou par une session à qui il le demande explicitement.
