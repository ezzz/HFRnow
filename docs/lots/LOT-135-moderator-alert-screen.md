# LOT-135 — Moderator alert screen

- **Module:** App
- **Difficulty / model:** easy (Opus 5.5 → Fable)
- **Issue:** ezzz/HFRnow#225
- **Depends on:** LOT-050 (#76, `ModeratorAlertFlow`, with #395's reading of the answer), LOT-087 (#179, the message menu and
  its `.alert` entry)

"Alerter" in the message menu: report a message to the moderators with a reason, through HFR's own alert form, and tell the
user what HFR answered. Without an alert link, the legacy mail fallback, only when the build is given the address (Q-10).

## Legacy sources

Legacy reference `legacy/duo-inner-cover` @ `87fe0d1c` (AGENTS.md §2), `HFRswift/Swift/MessagesView.swift` unless noted.

| Legacy @ `87fe0d1c` | What it does | Replaced by |
|---|---|---|
| `:235-241` (`MessagePopupMenuPolicy`) | "Alerter" for another member's message with an alert link, or else with a permalink | LOT-087 `MessageMenuPolicy` (unchanged) and `ModeratorAlertModel.canAlert` |
| `:2232-2254` | the entry calls `onPopupAlertRequest(alertURL)`, or `onPopupAlertMailRequest(permalink)` without an alert link | `ModeratorAlertModel.start` |
| `:4587-4609` (`openModerationAlertComposer`) | one preparation at a time; "already alerted" shown as a toast with HFR's text or "Alerte déjà envoyée."; the form opens the composer sheet; an error opens "Alerte impossible" | `ModeratorAlertModel.prepare` |
| `:5368-5375` | "Chargement de l'alerte..." over the page while preparing | `ReaderAlertFlow` overlay |
| `:5497-5505` | the composer sheet (`.large`), its success text shown as a toast | `ReaderAlertFlow` sheet, `TopicReaderModel.showMenuFeedback` |
| `:5542-5546` | alert "Alerte impossible" with the error | `ReaderAlertFlow` alert |
| `:7415-7524` (`ModerationAlertComposerView`) | title "Alerte Modération"; the warning "Attention : le message que vous écrivez ici sera envoyé directement aux modérateurs via message privé ou e-mail."; a text editor with the placeholder "Décrivez le problème..."; "Annuler" (disabled while sending) and "Envoyer" (disabled for a blank reason or while sending); "Envoi de l'alerte..." while sending; any answer text, or "Alerte envoyée.", is a success that closes the sheet; an error stays in the sheet ("Alerte impossible") | `ModeratorAlertComposerModel`, `ModeratorAlertComposerView` |
| `:4568-4585`, `:5534-5541` | the mail fallback: "Alerter les modérateurs par email ?" / "Un email sera préparé dans votre application Mail." / Non / Oui, then `mailto:<address>?subject=[HardWare.fr] Signalement d'un contenu illicite&body=Message : <permalink>` with `.urlQueryAllowed` encoding | `ModeratorAlertModel.pendingMail`, `ModeratorAlertMail` |
| `ReplyService.swift:1437-1540` (`ForumModerationAlertService`) | prepare and submit | LOT-050 `ModeratorAlertFlow` (engine) |

## Legacy counterpart (app lots)

- `App/SwiftHFR/Reader/Actions/ModeratorAlertModel.swift`: `HFRswift/Swift/MessagesView.swift (openModerationAlertComposer, askAlertMailConfirmation, confirmAlertMailSending)` @ `87fe0d1c`.
- `App/SwiftHFR/Reader/Actions/ModeratorAlertComposerView.swift` (with `ModeratorAlertComposerModel`): `HFRswift/Swift/MessagesView.swift (ModerationAlertComposerView)` @ `87fe0d1c`.
- `App/SwiftHFR/Reader/Actions/ReaderAlertFlow.swift`: the `MessagesView` modifiers `:5368-5375`, `:5497-5505`, `:5534-5546` @ `87fe0d1c`.
- `App/SwiftHFR/Reader/Actions/LiveModeratorAlerter.swift`: `HFRswift/Swift/ReplyService.swift (ForumModerationAlertService)` @ `87fe0d1c`, through LOT-050.

## UX evolutions (app lots)

- **GAP-070** (ported with changes, `b·needed`): an alert HFR did not confirm (`unconfirmed`: the answer is not HFR's
  confirmation, or the exchange failed after the POST left) closes the sheet and says the alert may have reached the
  moderators; it is never offered again from that sheet (AGENTS.md learnings LOT-037/048: an `unconfirmed` write is never
  retried). Legacy kept the sheet open with the reason and "Envoyer" ready.
- **GAP-070** (`b·needed`): the mail fallback is offered only when the build carries the address (`MODERATOR_ALERT_MAIL_ADDRESS`,
  Q-10: a third party's address stays out of source, ADR 0007); without it, a message without an alert link offers no
  "Alerter". The mail's subject and body are legacy's, the query encoded strictly (legacy's `.urlQueryAllowed` left a `&` of
  the permalink unencoded, which cut the body).
- Everything else is legacy's: the menu entry, the progress text, the sheet's title, warning, placeholder and buttons, the
  toasts, the mail confirmation.

## Behaviour

Code in `App/SwiftHFR/Reader/Actions/`, tests in `App/SwiftHFRTests/Reader/Actions/`.

1. **Entry** — LOT-087's policy offers "Alerter" for a message that is not the user's own with an alert link or a permalink.
   `ModeratorAlertModel.canAlert` keeps it when the message has an alert link and an account is current (an alerter exists),
   or when the mail fallback can be built (address configured, permalink known). Otherwise the entry is hidden, never shown
   disabled (LOT-087 rule). A blocked message (LOT-117/118) keeps its menu inside the opened disclosure: "Alerter" works there
   too (issue #225 comment).
2. **Prepare** — with an alert link and an alerter: one preparation at a time ("Chargement de l’alerte…" over the page).
   `ModeratorAlertFlow.prepare` runs through the current account's session:
   - `alreadyAlerted(message:)`: HFR's sentence as the reader's confirmation toast (`R88`: "Votre demande de modération sur ce
     message n'est pas encore traitée."), legacy's "Alerte déjà envoyée." when HFR gave none;
   - `form`: the composer sheet opens;
   - an error: "Alerte impossible" with a French text that says nothing was sent (HFR's own sentence for `formUnavailable`).
3. **Compose and send** — the sheet "Alerte Modération" shows legacy's warning, a text editor with the placeholder "Décrivez
   le problème…", "Annuler" and "Envoyer". "Envoyer" is enabled for a non-blank reason while nothing is being sent; one send
   at a time; "Annuler" and the swipe-down are disabled while sending. `ModeratorAlertFlow.submit` sends the form once:
   - success (`W46`, HFR's sentence "Un message a été envoyé avec succès aux modérateurs"): the sheet closes and the sentence
     is the reader's toast;
   - nothing was sent and the form is still usable (`emptyReason`, `unsupportedCharacters`, `rejected`, `network`): the
     sheet stays open with the reason, "Alerte impossible" says why (HFR's sentence for `rejected`, the refused characters
     listed);
   - `unconfirmed`: the sheet closes, "Alerte non confirmée" says it may have reached the moderators and is not sent again
     (HFR's sentence added when it gave one);
   - the form is no longer usable (`notLoggedIn`, `sessionChanged`, `invalidLink`, `formUnavailable`, `unsupportedForm`): the
     sheet closes, "Alerte impossible" says nothing was sent and what to do.
4. **Mail fallback** — without an alert link (or without an account), with an address in the build's `ModeratorAlertMailAddress`
   (Info.plist, from `MODERATOR_ALERT_MAIL_ADDRESS`) and a permalink: legacy's confirmation "Alerter les modérateurs par email ?"
   / "Un email sera préparé dans votre application Mail." / "Non" / "Oui"; "Oui" opens `mailto:<address>` with legacy's subject
   and body through the system. The address must be one `local@domain` token without spaces or URL delimiters, else the
   fallback is off. Nothing is sent by the app: the user sends the mail.
5. **Session** — the alerter is built from the current account's session (`AppEnvironment`, rebuilt on an account change); a
   logged-out environment has none.

No HFR fact is new here: links, pages, form and answers are LOT-050's (HFR-PROTOCOL §6c LOT-050, captures `R21`, `R46`, `R88`,
`R89`, `W46`, `W47`).

## Edge cases

- A tap on "Alerter" while a preparation runs, or while the sheet is open, does nothing.
- The sheet dismissed by a swipe drops the reason (legacy did too); nothing was sent.
- A send still running when the sheet goes away still reports its outcome to the reader.
- A message with both an alert link and a permalink never offers the mail (legacy `:2232-2254`).
- The address `$(MODERATOR_ALERT_MAIL_ADDRESS)` unexpanded, empty or malformed: no fallback.

## Fixtures

None new: the engine's tests read the captures; the app's tests drive a scripted alerter (no request, no session).

## Tests (`App/SwiftHFRTests/Reader/Actions/`)

- `ModeratorAlertModelTests`: the entry's availability (alert link with and without an alerter, mail configured or not, own
  message); already alerted with HFR's sentence and the legacy fallback; the form opens the sheet; one preparation at a time;
  each prepare error's text; the mail confirmation and its URL (subject, body, a `&` in the permalink encoded); a malformed or
  unexpanded address refused; the reader's menu on an opened blocked message runs "Alerter".
- `ModeratorAlertComposerModelTests`: "Envoyer" enabled only for a non-blank reason and not while sending; success closes with
  HFR's sentence; each refusal keeps the sheet and the reason; `unconfirmed` closes without resending; a second tap while
  sending sends nothing.

## Intentional differences from legacy

1. `unconfirmed` is never resent (see UX evolutions). CHANGELOG-LEGACY row in the PR's ledger.
2. Mail fallback only with a configured address; strict query encoding.
3. Engine differences are LOT-050's (rows 66 and 81).

## Learnings

To copy into AGENTS.md §11 when the lot closes.
