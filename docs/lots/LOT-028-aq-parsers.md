# LOT-028 — AQ listing and RSS parsers

- **Module:** HFRParsing
- **Difficulty / model:** easy · Sonnet → Opus
- **Issue:** [#56](https://github.com/ezzz/HFRnow/issues/56). Split from [LOT-025](LOT-025-small-parsers.md), whose AQ part was left out ("Not covered / gaps").

Stub: the lot is `blocked` until the AQ capture ([#133](https://github.com/ezzz/HFRnow/issues/133)) exists (third-party host `aq.super-h.fr`, LOT-001 checklist row P08), with a legacy oracle for both parsers (LESSONS 35–36). Q-4 is decided: AQ is kept, with a first-use notice (LOT-071).

## Legacy sources
`AQPlusView.swift:29-87` (ezzz/HFRnow @ `2440d79`; HFR-PROTOCOL §8, `aq.super-h.fr` row): `getAlertesByTopic.php?topic_id=` (response format unverified, pending the AQ capture) and `rss.php` (RSS). To complete with line ranges when the lot is claimed.

## Behaviour
Inputs: the `getAlertesByTopic` response and the RSS feed. Outputs: the AQ item models of LOT-012 (`HFRModels/AQ`), every item with its category (hiding the Apple category is app policy, Q-7).

## Edge cases
HTML entities in titles, authors and comments (HFR-PROTOCOL §7b B4, Bybifok; legacy fix `a817498`; [#105](https://github.com/ezzz/HFRnow/issues/105)).

## Fixtures
Captured 2026-11-02 (#133, run 10 of the corpus): `T01` (`rss.php`, 25 items) and `T02` (`api/getAlertesByTopic.php`,
123 alerts of one topic), anonymized by position (members → `userN`, member-written alert titles and comments → `x` per
word with entities and punctuation kept, public topic titles kept; MANIFEST run 10). Oracle of the legacy RSS parser:
`Fixtures/LOT-028/T01.oracle.json` (kind `aq-rss` of `tooling/legacy-oracle`, `AQRSSParserDelegate` of `AQPlusView.swift`
@ `2440d79`; `relativeDate` is not exported, it reads Swift `Date()`). Legacy has no parser for `T02`: it only checks
that the answer contains the message id (`MessagesView.swift` `isAQAlreadySignaled`, `content.contains(postID)`).

## Intentional differences from legacy
To write with the fixtures.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
