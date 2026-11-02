# LOT-054 — Poll vote

- **Module:** HFRClient (classifier context in HFRParsing)
- **Difficulty / model:** medium · Opus (author) → Fable (reviewer)
- **Issue:** #80 (and the poll-vote part of #395)

## Legacy sources
- `HFRswift/Swift/PollData.swift:45-99` @ 2440d79 (`PollVoteSubmitter.submit`, `parseVoteResponse`): posts the poll's hidden fields from a `[String: String]` dictionary (random order, one `hash_check`) plus the chosen `reponse`, without `sondage_submit`, through `URLSession.shared`; any answer whose `.hop` has no `<a`/`<input`, **or with no `.hop` at all**, is a success.
- Poll form parsing: LOT-026 (`PollParser`, `docs/lots/LOT-026-poll-parser.md`).

## Behaviour
`PollVoteFlow.vote(_ choice: Int, in poll: Poll, session: HFRSession) async throws(PollVoteError) -> PollVoteResult`.

1. **Form check, nothing sent**: `poll.kind` must be `.votable` (else `notVotable`). The form must be the captured one (`R32a`, `R32b`, `R83`): hidden inputs exactly `cat, p, page, sondage, owntopic, subcat, numeropost, hash_check`, ASCII-digit values, `cat` and `numeropost` positive, every answer field `reponse`, `maxChoices == 1` (else `unsupportedPoll`: a body would be guessed). `choice` must be an option id (else `invalidChoice`).
2. **Session check**: LOT-044 `SessionRefreshFlow` must say `.valid` (else `sessionNotConfirmed`; a failed check is `network`), as every flag write since #314. It also records a fresh token. The session's identity and login generation are read before the check (#340): a login adopted after it, of another account or the same one, gives `loginChanged` and sends nothing. The comparison, the token read and the hand-off to the transport happen in one actor turn (`PostingSession.send(since:)`), so no login lands in between; cancellation is checked in that turn too.
3. **One POST** to `https://forum.hardware.fr/user/vote.php?config=hfr.inc` (the form action), redirects not followed, body exactly `W42`'s: `hash_check, cat, p, page, sondage, owntopic, subcat, numeropost, hash_check, reponse=<choice>, sondage_submit=Voter`. Both `hash_check` copies are the **session's** token (per-account, HFR-PROTOCOL §5), not the page's, so a poll read in another account's page or a stale page still posts this account's token. No token → `missingToken`, nothing sent.
4. **Answer** (LOT-037 `HopResponseParser`, new `Context.pollVote`):
   - success = link-less `.hop` whose whole text is "Votre vote a bien été pris en compte !" **and** a refresh to an `https` forum URL (`W42`: `/hfr/<cat>/<sub>/sujet_<post>_1.htm`) (with or without the sub-forum directory, as the list links of `R04`/`R27`) whose category slug is the forum `ForumCatalogue` maps to the form's `cat` and whose file name is `sujet_<the form's numeropost>_<page>.htm` (the sentence names no poll: the refresh is HFR's only tie to this vote, and a topic number is one category's) → `PollVoteResult(topic, choice, message, refreshURL)`; the app reloads `refreshURL` to show the results. A confirmation refreshing to another topic is `unconfirmed`.
   - `.hop` + back link "Désolé, vous avez déjà voté !" (`W43` same account, `W44` linked account) → `alreadyVoted`.
   - logged-out sentence → `notLoggedIn`; other link/input `.hop` or `W17b` plain text → `rejected(message)`.
   - a redirect, another write's "avec succès" confirmation, any other page → `unconfirmed(.unrecognizedAnswer)`; transport failure after sending (incl. HTTP status) → `unconfirmed(.transport)`; a request refused before leaving → `network`.

The vote sentence is a success under `.pollVote` only; under `.write` `W42` stays `unrecognized` and the write confirmations are `unrecognized` under `.pollVote` (corpus sweeps in `HopResponseParserTests` and `HopResponsePollVoteTests`).

## Edge cases
- Cancelled task: `network(.cancelled)` before the check and before the POST; nothing sent.
- Results page (closed `R33a`, already voted `R33b`): `notVotable`.
- Multi-choice polls: not captured; refused as `unsupportedPoll` (LOT-026 never produces `maxChoices > 1`).

## Pending capture
- The refresh page after a vote from a form whose `page` is not 1: `W42`'s form had `page=1` and refreshed to page 1; whether HFR echoes the form's page is not known, so the app reloads `refreshURL` as given and never assumes page 1.
- The refresh of a vote on a topic at a category's root: `W42`'s topic has a sub-forum; the shape without one comes from the list links (`R04`, `R27`).
- The category check reads `ForumCatalogue` (exact, case-sensitive, legacy `Forum.m:34-60`): a vote in a forum the table does not know is `unconfirmed` until the table is updated.
- **Guest votes**: `R83` prints "Les invités peuvent voter" and `R32a` shows the form logged out with an empty `hash_check`, so HFR offers guest voting on some polls. A guest vote body was never sent, so the flow does not offer it: without a confirmed account session the vote is `sessionNotConfirmed` (or `missingToken`). Not a bug: a later lot adds it once a capture shows the answer.
- The vote answer without cookies (not published by #394) and to a bad token: classified by shape (`notLoggedIn` / `rejected`), never success.
- A vote on a closed poll by a stale form, a body without `sondage_submit`, another field order: not tried; the flow sends only `W42`'s body.

## Fixtures
`R83` (own topic, vote form, logged in), `R32b` (other poll, 10 answers), `R33a`/`R33b` (results), `W42` (vote accepted), `W43`/`W44` (already voted), `W17b`, `W17c`, `W20a`, `W30` (other answers), `R55-p1`/`W00` (session check). Tests: `PollVoteFlowTests`, `PollVoteSessionGateTests` (extension), `HopResponsePollVoteTests`.

## Intentional differences from legacy
- The body is `W42`'s (document order, both tokens, the "Voter" button `sondage_submit`) instead of a dictionary without the button.
- No `.hop`, a `.hop` without the vote sentence or without a forum refresh is no longer a success.
- "Déjà voté" is its own error; the session is checked before the vote; the session's transport (account cookies, `*.hardware.fr` only) replaces `URLSession.shared`.
