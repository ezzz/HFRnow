# LOT-028 — AQ listing and RSS parsers

- **Module:** HFRParsing
- **Difficulty / model:** easy · Sonnet → Opus
- **Issue:** [#56](https://github.com/ezzz/HFRnow/issues/56). Split from [LOT-025](LOT-025-small-parsers.md), whose AQ part was left out ("Not covered / gaps").

Implemented: `AQFeedParser` (RSS, `T01`), `AQAlertListParser` (listing, `T02`), internal `AQXMLDocument` and `RFC822Date` (`Sources/HFRParsing/AQ/`).

Background: the AQ capture ([#133](https://github.com/ezzz/HFRnow/issues/133), third-party host `aq.super-h.fr`, LOT-001 checklist row P08) and the oracle of the legacy RSS parser exist (see Fixtures). Q-4 is decided: AQ is kept, with a first-use notice (LOT-071).

## Legacy sources
`AQPlusView.swift` (ezzz/HFRnow @ `2440d79`; HFR-PROTOCOL §8, `aq.super-h.fr` row): `getAlertesByTopic.php?topic_id=` (XML `<alertes>` of `<alerte …/>`, `T02`; legacy only checks `content.contains(postID)`) and `rss.php` (RSS 2.0, `T01`). `AQRSSParserDelegate` is `AQPlusView.swift:94-245` @ `2440d79`: item fields `135-172`, placeholders `101, 103`, keep rule (empty link, `&cat=25&post`) `174-180`, description guard `183-185` and regexes `187-199`, date `113-118, 201-206`, relative label `208-231` (app, not ported). `getAlertesByTopic` is read at `MessagesView.swift` `isAQAlreadySignaled` (`content.contains(postID)`).

## Behaviour
Inputs: the `getAlertesByTopic` response and the RSS feed. Outputs: the AQ item models of LOT-012 (`HFRModels/AQ`), every item with its category (hiding the Apple category is app policy, Q-7).

Public API (HFRParsing, no `HFRModels` change):

| Function | Result |
|---|---|
| `AQFeedParser.parse(_ xml:)` | `[AQFeedItem]`, document order, every category; `throws(ParsingError)` |
| `AQFeedParser.category(of:)` | `Int?`, the `cat` parameter of the item's link, for the Q-7 filter (callers compare with 25) |
| `AQAlertListParser.parse(_ xml:)` | `[AQAlert]`, newest first as served; `throws(ParsingError)` |
| `AQAlertListParser.isReported(postID:in:)` | the question legacy answered with `contains(postID)` |

Both documents are read with SwiftSoup's XML parser (`Parser.xmlParser()`, not `parseHTML`: names keep their case, CDATA is text; LESSONS 26 is about HTML pages). The feed `description` is CDATA HTML read with the legacy's four regular expressions.

## Edge cases
HTML entities in titles, authors and comments (HFR-PROTOCOL §7b B4, Bybifok; legacy fix `a817498`; [#105](https://github.com/ezzz/HFRnow/issues/105)).

## Fixtures
Captured 2026-11-02 (#133, run 10 of the corpus): `T01` (`rss.php`, 25 items) and `T02` (`api/getAlertesByTopic.php`,
123 alerts of one topic), anonymized by position (members → `userN`, member-written alert titles and comments → `x` per
word with entities and punctuation kept, public topic titles kept; MANIFEST run 10). Oracle of the legacy RSS parser:
`Fixtures/LOT-028/T01.oracle.json` (kind `aq-rss` of `tooling/legacy-oracle`, `AQRSSParserDelegate` of `AQPlusView.swift`
@ `2440d79`; `relativeDate` is not exported, it reads Swift `Date()`). Legacy has no parser for `T02`: it only checks
that the answer contains the message id (`MessagesView.swift` `isAQAlreadySignaled`, `content.contains(postID)`).
Entities seen: in the RSS topic titles (`&quot;`, `&#039;`, `&amp;`, kept undecoded by legacy as `topicTitle`) and in `T02`'s `nom`
attributes; none in an RSS item `<title>` or a reporter comment. *Pending capture*: a comment holding an entity ([#438](https://github.com/ezzz/HFRnow/issues/438)).
An entity inside a pseudo cannot survive anonymization (aliased).

Also handled, each tested on `T01`/`T02`:
- 2 of 25 feed links are canonical `/hfr/…-sujet_<post>_<page>.htm` paths with no `cat`: `category(of:)` is nil, legacy's substring test never hid them either.
- `T02` repeats a message number inside one `postsIds` (several reporters of one message): kept as served.
- `T02` `nom` can end with a space: kept.
- Not a feed (HTML error page, empty body, the other AQ document) or not a listing: `missingElement`, never an empty list. An `<rss><channel>` with no item, or `<alertes/>`, is an empty list (format-implied; no capture of an empty answer).

## Intentional differences from legacy
- Topic titles, initiators and comments are entity-decoded; legacy returned `&quot;`/`&#039;` in `topicTitle` (B4, 4 of 25 items of `T01`). Decoding the comment and initiator is untested on a capture (*pending capture*, #438): same function, same HTML context.
- A `<link>` that is not an `https` link to `forum.hardware.fr` (no explicit port) skips the item (legacy skipped only an empty one): the feed is third-party and the app follows the links (LESSONS 43). All 25 `T01` links are forum links. Links go through `HFRURL.absolute` (scheme and user-info checks).
- An unreadable `pubDate` is `publishedAt == nil` (legacy: now, so the item counted as new); only `±hhmm`/`GMT` offsets and four-digit years are read (`T01` shape); the 2-digit-year form of legacy's `yy` is not captured and not accepted.
- The category filter is by `cat` parameter (`category(of:) == 25`), not legacy's `&cat=25&post` substring: a link with `cat=25` in another position is now hidden too.
- `isNew`, the relative label ("il y a 3 h"), the unread count and the category-25 filter are app logic, not parsed; `isNew` is `publishedAt >= lastCheck` (the test checks this against the oracle).
- The listing is parsed (legacy only searched the text), strictly: a missing attribute or a non-integer `id`/`postsIds` entry throws instead of being skipped. `isReported` compares whole numbers (legacy `contains` also matched `7539691` inside `75396914`). The listing format is the one captured in `T02`, which settles the LOT-012 "unverified" note.

## Tests
`Tests/HFRParsingTests/AQ/AQParsersTests.swift`: differential on all 25 `T01` items (title, comment, initiator, link, topic title = decoded oracle; `isNew` and `newCount`), `pubDate` against the description's printed Paris time, `T02` (123 alerts) and errors. Each rule was checked to fail without it (entity decoding, link skip, host restriction, offset, duplicate numbers, channel-blurb guard, case-insensitive captures, `postsIds` of 0, root element).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
