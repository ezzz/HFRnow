# LOT-134 — AQ check and creation from a message

- **Module:** App
- **Difficulty / model:** easy · Sonnet → Opus (author → reviewer, orchestrator's assignment; `docs/LOTS.md` says Opus → Fable)
- **Issue:** [#224](https://github.com/ezzz/HFRnow/issues/224). Depends on [LOT-055](LOT-055-aq-client.md) (AQ client),
  [LOT-087](LOT-087-message-actions.md) (message menu, handler registry), [LOT-071](LOT-071-third-party-services.md) (T2, T3, Q-4, D-071-3).
  Gap row: GAP-069. The first-use notice of the *check* (T2) stays [LOT-183](https://github.com/ezzz/HFRnow/issues/423) (M5).

## Legacy sources
`legacy/duo-inner-cover` @ `87fe0d1c` (`git show 87fe0d1c:<path>`):

| Part | Legacy |
|---|---|
| Menu rule | `ObjCMessageActionsBuilder.m:19` (`canAQ`: public topics only) |
| Check | `HFRswift/Swift/MessagesView.swift:325-340` (`isAQAlreadySignaled`), `:4506-4543` (`askAQPrompt`: no answer, no AQ) |
| Creation | `MessagesView.swift:342-378` (`createAQ`, fixed field order), `:5445-5473` (AQ sheet and result messages) |

## Legacy counterpart (app lots)

| SwiftHFR | Legacy @ `87fe0d1c` |
|---|---|
| `App/SwiftHFR/Reader/Actions/QualityAlertActionModel.swift` | `MessagesView.swift` (`MessagePopupActionSupport`: `isAQAlreadySignaled`, `createAQ`; `askAQPrompt`) |
| `App/SwiftHFR/Reader/Actions/ReaderQualityAlertFlow.swift` | `MessagesView.swift` (`MessagePopupPromptSheet`, the AQ sheet); a typed title is not thrown away without asking (swipe refused, « Annuler » asks « Abandonner cette alerte ? », #1169) |

## UX evolutions (app lots)
- **GAP-069** (`b·operator`, operator decision of 2026-11-07 on #224): a message that **someone else's** AQ already holds offers
  « Plussoyer » (add it to that AQ, `alerte_qualitay_id=<id>`) instead of legacy's refusal; only a message the member reported
  themselves says « Post déjà signalé par vous ».
- First-use notice N1 before the first creation (Q-4, D-071-3, LOT-071 T3): host and operator, what is sent, public alert, IP hash
  and e-mail to the operator. Accepted once per device (`aq_notice_accepted`); declining creates nothing.
- The AQ sheet closes at once and the reader's banner says the outcome (as « Bookmark »).

## Behaviour
- **Offered** (`canReport`): a topic that is not `cat=prive`, a message permalink, an account (the service wants a pseudo). No
  handler without the services (logged out, saved copy, no `AQBaseURL`): the registry then hides « AQ ».
- **Pick** (`start`): one at a time (`isIdle`). `AQClient.alerts(topicID:)` (T2, cookie-less). A failed check says « Création d'AQ
  impossible » and asks nothing (legacy `:4531`). The AQ whose `postIDs` holds the message: initiated by the account (case-insensitive)
  → « déjà signalé par vous »; another member's → addition question; none → title question. The notice comes first when not accepted.
- **Create / add**: nothing is sent before the notice is accepted, on any path (`send` re-checks). Report = title (trimmed, blank
  refused), topic id and title (page title), account pseudo, message number, permalink, comment `post de <author>`.
- **Outcomes**: success → « Alerte Qualitay créée. » / « Message ajouté… ». `invalidReport` → the problem in French, nothing sent.
  `unconfirmed` (the POST may have been recorded; no refusal is captured on the live host, LOT-055): the topic's list is read first;
  the member's report there → success, absent → « n'a pas été enregistrée » (an addition: « vous avez peut-être déjà signalé ce message dans cette alerte »; neither invites a retry: every attempt e-mails the AQ operator and an empty 200 is the anti-flood ban, `T59`/`T67`), list unreadable → « non confirmée… vérifiez » — never an
  automatic retry. An addition is detected by one more occurrence of the message number in the AQ's list (`T56`: `700102,700101`).
- **Test seam**: `AppEnvironment.qualityAlertsSource` (nil by hand, set by `make`): a hosted test no longer fetches the live feed with
  the Info.plist address when a root is built (LOT-133 follow-up).

## Edge cases
- **Limit**: the topic's list only names an AQ's initiator, not who joined it (HFR-PROTOCOL §8). A member who already added a message to another member's AQ is offered « Plussoyer » again; the server refuses the duplicate (`-4`, `T59`), the client reads it as `unconfirmed`, the list shows no new occurrence, and the banner says so without inviting a retry.
- Message numbers repeat in an AQ's list after an addition; the membership test is `contains`, the addition test a count.
- Pseudo comparison ignores case (the service stores the pseudo lower-cased).

## Fixtures
Captured answers only, served by a scripted host through the real `AQClient`: `T52` (no AQ), `T56` (AQ of user3 holding two
messages), `T53`/`T55` (create and add answers), `T54` (list after a create). **Pending captures:** a refusal of the live host
(none is captured: tests make the exchange fail instead, an `unconfirmed`), the live addition answer (`T55` is the local instance).

## Intentional differences from legacy
The addition (above); the check is a typed list, not a substring test; an unconfirmed create is verified, not read as failure;
the notice; no account, no entry.

## Tests
`QualityAlertActionModelTests` (16): notice → title → create with the exact body; decline; no path creates before the notice;
accepted notice not asked again; blank title; join another member's AQ (body names the AQ id); own report refused before any question;
failed check; unconfirmed create found / not found in the list (upper-case account pseudo); unconfirmed addition found / not found (`T54` → `T56`); a second pick waits, also while the check is in flight; a double tap on « Créer » sends one report; an unconfirmed create whose list cannot be read says « non confirmée »; the entry's availability.
Mutations checked to fail (model compiled on Linux in a scratch package): no gate in `send`, no own-report check, an unconfirmed create
found in the list reported as not recorded, an addition always reported recorded, a case-sensitive pseudo compare, no `isIdle` guard in `start` (the in-flight test then hangs), no `isWorking` guard in `send`. Not run by the author: the SwiftUI flow and wiring (compile check, device checks on #893).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A capture's post id can exceed `int(11)` (`T50`'s 9910000001): the client refuses it as out of range, so a test over that capture
  needs a local-instance pair (`T53`/`T54`).
