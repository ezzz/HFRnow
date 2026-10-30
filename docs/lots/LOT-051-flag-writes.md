# LOT-051 — Topic flags & favourites writes

- **Module:** HFRClient
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** ezzz/HFRnow#77; old francoisgn/ios-app_SwiftHFR#79 (frozen history); audit D7 in [D](../audit/D-posting.md) §2.8
- **Depends on:** LOT-037 (`HopResponseParser`), LOT-042 (`HFRSession`); reads LOT-033 (`TopicPageMetadataParser`) and
  LOT-041 (`HFREndpoint.topicPage`)

Add a topic to the favourites, remove a topic's flag, remove a favourite from the favourites list, and mark a topic read,
each in the selected account's session, reporting success only when HFR confirmed this very write. Parsing the links is
not here: `addflag` comes from LOT-031 (`MessageActions.favoriteURL`); see "Gaps" for `delflag`. Marking a private
message unread (`nonlu.php`, `W18`) is LOT-058.

## Legacy sources

Legacy app: `master` of ezzz/HFRnow (same lines as francoisgn/hfrnow @ `2440d79`).

| Legacy | Replaced by |
|---|---|
| `HFRswift/Wrapped/ParseMessagesOperation.m:301-302` (`addFlagUrl` = first `href` containing `addflag` in a message), `Classes/ObjCMessageActionsBuilder.m:35` (`favoriteURL`) | LOT-031; here the link is checked by parsed path and parameters (`FlagLink`) |
| `HFRswift/Wrapped/MessagesTableViewController.m:2265-2326` (`actionFavoris`: GET of `addFlagUrl` prefixed with the forum URL, toast = `.*<div class="hop">([^<]+)</div>.*`, no success/failure distinction) | `TopicFlagFlow.addFavorite(link:in:)` with LOT-037 and the per-write sentence |
| `MessagesTableViewController.m:1559-1580` (`isFavoritesOrRead` = first `href` containing `delflag` on the topic page) and `:1250-1270` (`markUnread`: GET of it, any answer = done) | `TopicFlagFlow.removeFlag(link:in:)` |
| `Classes/FavoritesTableViewController.m:1836-1858` (swipe delete: POST `manageaction.php`, body in this order, global `hash_check`, answer ignored) and `HFRswift/Swift/Favorites.swift:49-103` (same body, only the HTTP status checked) | `TopicFlagFlow.removeFavoriteFromList(_:in:)` |
| `FavoritesTableViewController.m:1602-1607` (`setTopicViewedWithIndex`: GET of `aURLOfLastPage`, answer ignored), `Favorites.swift:44-47` (`markTopicRead`, `try?`) | `TopicFlagFlow.markRead(_:page:in:)` |

No LOT-004 oracle covers these answers (its `response` kind covers the posted writes `W10`-`W20b`); the classification is
LOT-037's, already tested on `P03a`, `P03b`, `P03d` and `W18`. The legacy oracle of this lot is its code: the request it
sends (URL, method, body order) and its toast text, the `.hop` sentence, which `TopicFlagResult.message` equals.

## Behaviour

All in `Packages/HFRKit/Sources/HFRClient/Flags/`. Every entry point takes the account's `HFRSession`; a request is sent
once (the transport never retries). The only other request is a write's session check just before it (item 7).

1. **Link writes** — `addFavorite(link:in:)` (`addflag.php`) and `removeFlag(link:in:)` (`delflag.php`) are
   state-changing GETs of a link HFR printed. `FlagLink` accepts the link only when it is `https` on `forum.hardware.fr`,
   default port, no user info (the posting rule, `PostingFlow.isForumPage`), its path is **exactly** the write's
   (`/user/addflag.php`, `/user/delflag.php`), and its query has `config=hfr.inc`, one `cat` that is a forum category above 0
   and one positive ASCII `post` (`R21`, `P03a`, `P03d`); a repeated one of those is refused (the server may read either
   copy). Anything else is `invalidLink`, nothing sent. The fragment is dropped; the other parameters (`numreponse`,
   `page`, `ref`, `owntopic`, …) are sent as HFR wrote them. The GET does not follow redirects: HFR answers in place.
2. **List removal** — `removeFavoriteFromList(_:in:)` POSTs to
   `/modo/manageaction.php?config=hfr.inc&cat=0&type_page=forum1f&moderation=0` legacy's body in legacy's order:
   `hash_check, topic1=-1, topic_statusno1=-1, action_reaction=message_forum_delflags, type_page=forum1f, topic0=<post>,
   valuecat0=<cat>, valueforum0=hardwarefr`. The token is the session's own (`HFRSession.hashCheck`, per account,
   LOT-042); none gives `missingToken`, nothing sent. The app records the favourites page's token (`FavoritesPage.hashCheck`,
   LOT-024) in the session it loaded the page with. One topic per call, as legacy. Redirects are not followed.
3. **Read mark** — `markRead(_:page:in:)` GETs `forum2.php?config=hfr.inc&cat=<cat>&post=<post>&page=<page>`
   (`HFREndpoint.topicPage`) with the session, following HFR's redirects to the canonical page: an authenticated topic
   GET moves the account's read flag (HFR-PROTOCOL §7 E25). Pass the last page to mark the whole topic read, as legacy did.
4. **Confirmation of a write** — a 3xx answer is not a confirmation. The page is classified by LOT-037 (`.write`):
   `success` **and** the whole `.hop` sentence equal to the write's own (`addFavorite`: "Favori positionné avec succès",
   `P03a`, `P03b`; `removeFlag`: "Drapeau effacé avec succès", `P03d`) gives `TopicFlagResult` (action, topic from the link,
   sentence, refresh URL). Another write's confirmation (`W18` mark unread, `P03d` for an `addflag`, an edit) is
   `unconfirmed(.unexpectedConfirmation)`. `removeFavoriteFromList` accepts either captured sentence of
   `message_forum_delflags`: "Drapeaux effacés avec succès" (legacy's body, `P03j`) or "Favoris supprimés avec succès"
   (the browser's body, `P03h`, `P03l`); the captures do not show whether `owntopic` or the end marker selects it, both
   removed the topic, and neither confirms another write (#314). `rejected` → `rejected(message:)`, `loggedOut` →
   `notLoggedIn`, anything else → `unconfirmed(.unrecognizedAnswer(message:))`.
5. **Confirmation of a read** — the final URL must be a forum page and `TopicPageMetadataParser` must find the requested
   topic with a non-empty `hash_check` in its answer form (the page of a logged-in account, `R21`); the token is then
   recorded in the session, unless a login was adopted while the page was in flight (#308, LOT-043 edge cases). An anonymous page (`R20`), another topic, a list or an off-forum host is
   `unconfirmed(.unrecognizedAnswer)`. The result says which page HFR served (it redirects past the last page to it, `R24`).
6. **Errors** (`TopicFlagError`) — before the request leaves: `invalidLink`, `invalidTopic` (not a forum topic above 0,
   page below 1), `sessionNotConfirmed` (item 7), `missingToken`, `network` (cancelled task, request that cannot be
   built, failed session check). After: `unconfirmed(.transport)`
   for any transport failure or HTTP error status (the GET or POST may have reached HFR), never retried. No case carries a
   token or a cookie.
7. **Session check before a write** (#314) — `addFavorite`, `removeFlag` and `removeFavoriteFromList` first check the
   inputs (`invalidLink`, `invalidTopic`: nothing is asked), then the account session with LOT-044
   (`SessionRefreshFlow.refresh`, one GET of profile page 1, which also merges the cookies and token HFR sends back).
   Only `valid` lets the write leave; `expired` or `unconfirmed` is `sessionNotConfirmed(health)` and a check that
   fails is `network`, the write not sent either way. Why: HFR answers an `addflag` sent without any cookie with the
   bytes of the logged-in success (`P03q` = `P03a`), and never refuses a `delflag` (`P03o` = `P03n`), so for these GETs
   the sentence says nothing about the session. A success is therefore "the session was confirmed just before, and HFR
   answered this write's sentence"; the session could still end between the two requests, which no answer shows.
   `markRead` needs no check: its page proves the session (item 5).

## Edge cases

- `addflag` is idempotent on HFR (`P03b`, same sentence): retrying an `unconfirmed` add is harmless. Sent without
  cookies it gets the same success page (`P03q`), hence item 7.
- `delflag` never refuses: sent again on a topic without flag it answers the same bytes (`P03o` = `P03n`). A
  `removeFlag` success means "no flag left", not "a flag was removed".
- A `delflag` on a favourite also removes the topic's read flag (`P03f`): the app reloads both lists.
- `delflag` answers "Drapeau effacé avec succès" whatever `owntopic` the link carries (`0`: `P03n`, `1`: `P03p`, `3`:
  `P03d`); `owntopic` only chooses the refresh. The link is sent as printed.
- `R12` (logged-out favourites page) is a `.hop` with a link: `rejected` with its sentence, by LOT-037's shape rule.
- The favourites form puts its end marker (`topic<N>=-1`, `topic_statusno<N>=-1`) after its last row (`P03c`: index 1,
  `R10`: index 2). Legacy always writes index 1, which matches a one-row form exactly; on a longer list `topic1=-1`
  stands where the form has row 1's checkbox (unchecked rows are not sent by a browser). Kept as legacy; see Pending capture.

## Fixtures

Existing captures only, no new file: `P03a`, `P03b`, `P03d`, `P03n`, `P03o`, `P03p` (`addflag` and `delflag` answers),
`P03q` (`addflag` without cookies), `P03h`, `P03j`, `P03l` (`manageaction.php` answers), `R21` (the 40 `addflag` links
and the `delflag` link; read mark), `P03c`, `R10` (the favourites form: action and field names), `W18`, `W15` (other
writes' confirmations), `W20a`, `W17b`, `W17c`, `W01`, `R12`, `R20` (refusals, logged out, anonymous and unrelated pages),
`R55-p1` and `W00` (session check, as in LOT-044). The tests serve `P03d` to `removeFavoriteFromList` to show that a
`delflag` sentence does not confirm it, serve `P03h` and `P03l` (answers to the browser's body) to legacy's body to check
the accepted sentences, and alter a status code or a served URL for redirect and off-host edges; none of it is offered as
a captured state.

Tests: `FlagLinkWriteTests`, `FlagLinkValidationTests`, `FavoriteListAndReadTests`, `FlagSessionGateTests`
(HFRClientTests).

## Intentional differences from legacy

1. **Success only with HFR's confirmation and the write's sentence.** Legacy showed whatever `.hop` text came back (or
   ignored the answer: `delflag`, `manageaction`, read mark), so a flood refusal or a logged-out page looked like a toast.
2. **The link is checked by parsed path and parameters**, on `https://forum.hardware.fr` only. Legacy took the first `href`
   *containing* `addflag`/`delflag` and prefixed it with the forum URL, or followed any absolute host
   (`ObjCMessageActionsBuilder.m:70-78`, audit D §5 item 4).
3. **The list removal uses the session's own token**, not the app-wide `hash_check` that may belong to another account
   (`Favorites.swift:49-56`), and is never reported done on an HTTP status alone.
4. **The read mark is confirmed** by the served page (logged-in topic page of that topic) instead of `try?` and forget.
5. **No redirect is followed** after a flag write.
6. **A write leaves only in a session HFR confirmed just before** (item 7, #314). Legacy sent it with whatever cookies
   it held and showed HFR's sentence, and HFR answers an `addflag` without a session with its success page (`P03q`):
   with an expired session, legacy said "Favori positionné avec succès" and nothing changed.

## Pending capture

Listed for the orchestrator's capture backlog (this lot does not edit `docs/LOTS.md`). None blocks the lot. Captured
since the lot merged: the `manageaction.php` answers (`P03h`, `P03j`, `P03l`), `delflag` with `owntopic=0` and `1`
(`P03n`, `P03p`), a repeated `delflag` (`P03o`), `addflag` without cookies (`P03q`), and the topic page of a favourite
(`P03m`, parsed by #306).
- **Which part of the `manageaction.php` body selects its sentence** (`owntopic` or the end marker), and legacy's body
  on a list of two rows or more (marker at index 1 where the form puts row 1's checkbox).
- **`delflag.php` and `manageaction.php` without a session**, and every write with **stale cookies** (`P03q` sent none):
  their answers. Until then item 7's check is what keeps an expired session from a success.

## Gaps for other lots

- No parser exposes the topic page's `delflag` link (LOT-033 left flag state out, its decision 5). `removeFlag` takes the
  link; the reader needs it from the topic page: #306.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- Legacy's `manageaction.php` body writes the favourites form's end marker at index 1 whatever the list length: the
  captured form puts it after the last row (`P03c` index 1, `R10` index 2).
- HFR answers a cookie-less `addflag` with the logged-in success bytes (`P03q` = `P03a`) and a repeated `delflag` with
  the same success (`P03o` = `P03n`): for these GET writes the sentence proves nothing about the session, so they run
  only after a LOT-044 `valid` (#314).
