# LOT-093 — Filtered-posts flow

- **Module:** HFRClient
- **Difficulty / model:** medium (the plan routes Sonnet → Opus; taken by an Opus contributor, `ext/bybifok-opus-1`, so the reviewer is Fable)
- **Issue:** [#185](https://github.com/ezzz/HFRnow/issues/185)
- **Depends on:** LOT-030 (#57): `MessageBlockParser`, `MessageBlock` (`quotedByCount`, `isContinuation`, `contentHTML`); LOT-032 (#59): `MessageQuoteAnalyzer`; LOT-045 (#71): `PageFetcher.topicPage`, `AnonymousTransport`. Also reads LOT-033's `TopicPageMetadataParser` (last page).
- **Absorbs:** the Phase 4 backlog item "filtered-posts use case (C11)"; legacy backlog HFR-031 ("Résultats suivants").

## Legacy sources

Legacy app: `francoisgn/hfrnow` at `2440d79` (an ancestor of `origin/master`).

| Legacy | What it gives this lot |
|---|---|
| `Classes/FilterPostsQuotes.m:202-312` (`fetchFilteredPostsForTopic:startPage:progress:completion:`) | the page walk: start page, `#t<id>` of the favourite link, stop at 40 messages or at the last page, progress after each page, errors |
| `FilterPostsQuotes.m:261-267` | pages fetched with `setUseCookiePersistence:NO` and empty request cookies: no session |
| `FilterPostsQuotes.m:314-317` (`cancelSwiftFiltering`) | cancellation |
| `HFRswift/Wrapped/ParseMessagesOperation.m:141-347` (`parseData:filterPostsQuotes:YES…`) | the selection rules |
| `HFRswift/Swift/FavoritePostFilterService.swift:10-49` | progress ("N posts \| page X/Y") and batch (`startPage`, `endPage`, `isFinished`) |
| `HFRswift/Swift/MessagesView.swift:3970-3990` | next batch from `endPage + 1` |
| `Classes/HFRplusAppDelegate.m:108-114`, `HFRswift/Swift/AppSettingsView.swift:101-102, 167-168` | settings: `filter_posts_quotes` (`wl_pseudo` or `pseudo`), `filter_posts_min_quotes` (3) |

## Behaviour

Code in `Sources/HFRClient/FilteredPosts/`, tests in `Tests/HFRClientTests/FilteredPosts/`.

### `FilteredPostsCriteria`

`keeps(_:quotes:)` keeps a message when any rule holds (legacy: `bFilterCurrentPost = NO`):
1. HFR's "Message cité N fois" trailer gives `quotedByCount >= effectiveMinimumQuoteCount` (`:336-347`). The minimum is `minimumQuoteCount`, and 0 or less reads as 3 (`:340-343`).
2. `includesAllowlist` is on and the author is in `allowlist` (`:187-189`, setting `filter_posts_quotes` containing `wl`). Legacy's `isWL:` refused a blocklisted pseudo (`BlackList.m:119-122`): the caller passes its allowlist minus its blocklist.
3. The author is the account's `pseudo` (`:183-186`).
4. A quote of the message, at any depth, cites `pseudo` (`:196-206`, LOT-032 authors).
5. The content HTML contains `pseudo`, case-insensitive (`:327-331`). This is legacy's "pseudo" mode, which the Swift app always had on (`AppSettingsView.swift:167-168`).

Pseudos compare by `HFRText.pseudoComparisonKey`: zero-width spaces removed, trimmed, lower-cased. A nil or blank `pseudo` turns rules 3-5 off.

### `FilteredPostsFlow`

- `posts(in:from:after:criteria:progress:)` reads `topic` from `startPage`, one page after another.
  - Each page is one GET by `PageFetcher.topicPage(…, as: .anonymous)` on the flow's own `AnonymousTransport`. The flow has no session to send, so filtering never moves the account's read flag (HFR-PROTOCOL §7 E25). Legacy used no cookies either (`FilterPostsQuotes.m:261-267`).
  - Only forum topics, from page 1 on, are filtered. Anything else gives `invalidTopic` before any request: a private conversation is not readable without the session.
- **On each page**:
  - the continuation block (pages 2 and later) is never kept;
  - on the first page only, the messages up to `after` (the last message read) are skipped;
  - the other messages go through the criteria, with their LOT-032 quotes;
  - `progress` gets `(page, maxPage, resultCount)`, where `maxPage` comes from that page's pager.
- **End of a batch**:
  - after the topic's last page: `isFinished`, no `resumePage`;
  - after the page that brings the batch to `batchSize` (40) messages or more: a whole page is always kept, so a batch can exceed 40, as in legacy. Then `resumePage = endPage + 1`.
  - A page past the end comes back as the last page (`R24`: 302 from `…_2202.htm` to `…_2201.htm`). It ends the batch as finished without reading the page again; `maxPage` is the page HFR served, and `endPage` stays `startPage` when that happened on the first request.
  - **No page limit** (LESSONS 4): criteria that keep nothing read every page up to the topic's last, one GET at a time (2,201 pages on topic 28563), as legacy did (`FilterPostsQuotes.m:255-303`). Each page is up to a few hundred kilobytes (21–140 KB for the anonymous captures), decoded and dropped once read; cancellation stops the walk before the next request.
- **Errors**:
  - `network`: transport failure, HTTP error, or cancellation, which is checked before each page, so a cancelled run requests nothing more;
  - `unexpectedPage`: a page of another topic, a final URL that is not a `sujet_<post>_<page>.htm` page, or a page without any message block;
  - `page`: a parser error.

  The pages read before an error are not returned, as in legacy (`FilterPostsQuotes.m:268-274`).

## Edge cases

- **Page 1's first post** is a message like the others. Legacy dropped the first block of every page (`:141-144`): on pages 2 and later that is the continuation block, but on page 1 it is the topic's opening post (`R20`).
- **The advertisement** is the second block of anonymous pages (`R20`, `R22a`, `R22b`, `R24`), so legacy's first-block rule never hit it. `MessageBlockParser` skips it.
- **Long pseudos**: HFR prints them with a zero-width space (`R20`'s first author is `user3` + U+200B). Legacy compared the raw name with the account's pseudo (`:184`) and with quote authors (`:206`), so the account's own posts and quotes of it were missed; its allowlist check already removed U+200B (`BlackList.m:133-135`). Here every comparison uses the pseudo key.
- **`after` not on the first page** (a deleted message, a stale favourite): the messages numbered after it are still read, because message numbers grow in posting order (§6c LOT-090). Legacy skipped the whole page when the id was not found.
- **Rule 5 can over-match**: a pseudo inside a longer one (`user4` in `user45`) or inside markup matches, as in legacy. Kept for parity.
- Deleted messages (`messagetabledel`, pending capture in LOT-030) get no special rule, as in legacy.

## Fixtures

Captures only, nothing new: the anonymous topic pages `R20`, `R22a`, `R22b`, `R23`, `R24`, `R26`, `R27`, `R27b`, `R28`, `R31`, `R32a`, and `R04` as a page without messages (a derived probe: the list page served at a topic URL). Oracles: LOT-003 (`name`, `quotedNB`, `dicoHTML`, `postID` of every message).

## Tests

- `FilteredPostsLegacyTests` (differential, LESSONS 52). Legacy's rule is applied to the oracle's fields and compared with `FilteredPostsCriteria` on our reading of the same capture, for every message but the page's first.
  - The fields: `name`, `quotedNB`, the `Topic` headers of `dicoHTML` minus their last 10 characters, and `dicoHTML` lower-cased.
  - The pages: the ten anonymous topic pages.
  - The criteria, four sets per page, built from the page's own authors: count only; account and allowlist with minimum 2; allowlist off with minimum 0; roles swapped.
  - A second test checks that each rule keeps messages somewhere and that some messages are left out.
  - No oracle was exported in filter mode (`hfrnow.patch` supports it, never run). The rule is transcribed from `ParseMessagesOperation.m`, the inputs are legacy's.
- `FilteredPostsFlowTests`:
  - the last page (one anonymous GET without `Cookie`, continuation left out, finished, one progress report);
  - a full batch on page 1, opening post kept, `resumePage` 2;
  - the next page requested after a short batch, and a failure there;
  - cancellation after a page;
  - a page past the end (`R24`);
  - `after` on the first page;
  - `invalidTopic` (four cases, no request), another topic's page, a page without messages, an HTTP error;
  - the public flow's transports are `AnonymousTransport`.
- `FilteredPostsCriteriaTests`:
  - on `R20`: the floor of 3, pseudo keys (U+200B, case, spaces), a blank pseudo, the allowlist switch, and a mention through a personal smiley (`[:user6]` in a post by `user5`, as legacy reads it);
  - on small models: a quote of the account at depth 2 whose header does not spell the pseudo as text, and author keys.

Shown to fail with the behaviour removed (each mutation caught):
- criteria: each of the five rules removed, a count strictly greater, no floor, the allowlist switch ignored, raw author comparison, depth-1 quotes only;
- flow: continuation kept, legacy's first-block drop, `after` ignored, a batch of 41, no batch stop, no topic check, a page past the end read as a page, an empty page accepted, a session reachable from the flow, `prive` accepted, no progress.

Cancellation before a page is `PageFetcher`'s own check (LOT-045), pinned here by the cancellation test. The guard on a blank pseudo has no observable mutant: Foundation's `contains("")` is false.

## Pending capture

- Two **consecutive pages** of one topic, anonymous (capture issue [#353](https://github.com/ezzz/HFRnow/issues/353)): the walk from one page to the next is tested with page 1 (`R20`) followed by a failure, a cancellation or nothing. No captured pair shows a batch spanning two read pages.
- A **filter-mode legacy oracle** (`tooling/legacy-oracle`, `filter` input), to replace the transcribed rule in the differential test.

## Intentional differences from legacy

1. **Page 1's opening post can be kept** (legacy dropped the first block of every page, `ParseMessagesOperation.m:141-144`). [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 48.
2. **Long pseudos match** their zero-width-space form for the account's own posts and quotes of it (legacy compared raw names there, `:184`, `:206`). Row 48.
3. **`after` by message number**, not by the id on the page: a last-read message missing from the page no longer skips the whole page (legacy skipped every block until it saw the id, `:161-166`). Row 48.
4. **The last page comes from each page read**, not from the favourite row given at the start (`topic.maxTopicPage`), so a topic that grew meanwhile is read to its real end; a page past the end is read as the end.
5. **No settings string**: the allowlist is a switch, the "pseudo" rules are on whenever a pseudo is given (the Swift app always ran in `pseudo` mode). Legacy ObjC without `pseudo` in the setting also skipped the quote-count rule (`:320-322`); that combination is not offered.

## Learnings

- Legacy's "first block of the page" was the continuation block only from page 2 on: on page 1 it is the opening post. Read the block's own shape (`isContinuation`), not its position.
