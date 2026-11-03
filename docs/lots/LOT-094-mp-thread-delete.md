# LOT-094 — MP thread delete

- **Module:** HFRClient
- **Difficulty / model:** easy (Opus → Fable)
- **Issue:** #186

## Legacy sources

The MP delete is not in `2440d79`; it was added later on `master`. Citations name `03e5e22` (the last commit of `master` touching the file, an ancestor of `master`).

- `HFRswift/Swift/MPListView.swift:114-159` @ 03e5e22, `ForumMPTopicActionService.deleteTopic`: reads the app-wide `hash_check` (`:118-124`), builds `/modo/manageaction.php?config=hfr.inc&cat=prive&type_page=forum1&moderation=0` (`:127-140`), POSTs a form-encoded Swift dictionary (`:145-154`), and reports success on any 2xx status (`:157-158`, `validate(response:)` `:161-168`).
- `MPListView.swift:551-575` @ 03e5e22 (`deleteTopic(_:)` of the list view): the caller; on success it removes the row locally and lowers the unread count.

## Behaviour

`DeletePrivateMessageFlow.delete(_ thread: TopicID, in: HFRSession)`, where `thread` is `TopicID(category: .privateMessages, topic: <post>)`.

1. **Input**: a private-messages topic with a positive `post`; anything else is `invalidThread` and nothing is requested.
2. **Session check** (#314): LOT-044's `SessionRefreshFlow` on the account session (one GET of the profile page). Not `.valid` → `sessionNotConfirmed(health)`; the check fails → `network(error)`. Nothing is sent in either case.
3. **Login fence** (#340, #342, #448): the session's identity, token and `loginGeneration` are read once before the check, in one actor turn (the seed). The POST goes through `PostingSession.send(since:)` (#412): in one turn of the session actor it compares the session's identity and generation with the seed, reads the token and builds the request. A changed identity (another account, a logout) or a moved generation (a login of the same account), at any point from the seed to the POST, gives `sessionChanged` and nothing is sent. A token the refresh recorded (no generation move) is the one posted. No identity before the check → `sessionChanged`; no token → `missingToken`.
4. **Request** (`W64`, `W65`): one POST, redirects not followed, to the MP list form's action (`R95k`), with W64's body byte for byte: `hash_check, topic0=<post>, valuecat0=prive, valueforum0=hardwarefr, topic1=-1, topic_statusno1=-1, action_reaction=valid_eff_prive, type_page=forum1`. Every field but `type_page` and the fixed end marker `topic_statusno1` is a control of the list form (`R95k` puts the marker at the row count, 50).
5. **Answer** (LOT-037, `.write` context):
   - success only with the whole sentence "Action effectuée avec succès" **and** a refresh to `/forum1.php` with exactly one `cat=prive` (`W64`, `W65`) → `MPThreadDeletion(thread, message, refreshURL)`;
   - the bad-token plain text (`W64x`) → `rejected(message:)`; a logged-out `.hop` → `notLoggedIn`;
   - another write's confirmation (`W18`, `P03j`, `P03d`, `W15`) or the sentence with another refresh → `unconfirmed(.unexpectedConfirmation)`;
   - a redirect, another page (`R95j`) → `unconfirmed(.unrecognizedAnswer)`; a failure after sending (timeout, HTTP error) → `unconfirmed(.transport)`; a request refused before leaving (host policy) → `network`.

The delete removes the thread **from the deleting account's list only**: the recipient still lists it (`R95k`) until it deletes it too (`W65`); for the deleter the thread URL then answers "Ce message ne vous est pas destiné, désolé" (`R96c`, `R96d`). The app reloads the MP list after a success or an `unconfirmed`; a list page past the last one is an empty list page, not an error (`R96a`, #114).

## Edge cases

- **Login after the request is built**: `URLSession` attaches the cookies when the task starts, outside the session actor's turn. A login adopted in that window sends this account's token with the new cookies. That pairing is not captured: it is expected to be refused like `W64x` (a wrong token with the same account's cookies), which deleted nothing. The actor hop between the check and the POST is closed (#448).
- **Generic sentence**: "Action effectuée avec succès" names no action, hence the refresh check.
- **Several threads at once**: the list form can check several rows (`topic<i>` per row); legacy sends one, and so does this lot.

## Pending capture

- The delete sent without cookies or with expired cookies (the gate keeps it from leaving; its answer is unknown).
- A thread number the account does not take part in, or already deleted (repeat of `W64`).

## Fixtures

`W64` (owner, success), `W65` (recipient, success), `W64x` (bad token), `R95j`/`R95k` (lists after), `R96c`/`R96d` (thread URL after), `R95k`'s `form1` (fields and action), plus `W17c`, `W18`, `P03d`, `P03j`, `W15` for refusals and other writes' confirmations. Tests: `DeletePrivateMessageFlowTests`.

## Intentional differences from legacy

- Legacy reported success on any 2xx: the bad-token answer `W64x` is a 200, so a refused delete showed as done. Success now needs HFR's sentence and the MP list refresh.
- Legacy posted with the app-wide `hash_check` and `URLSession` default cookies, without checking the session; the delete now runs in the selected account's session, after a LOT-044 check and the login fence.
- Legacy's body order came from a Swift dictionary (random per process); the body now has W64's fixed order.

## Learnings

- A generic confirmation sentence ("Action effectuée avec succès") needs a second proof from the same answer (its refresh target).
