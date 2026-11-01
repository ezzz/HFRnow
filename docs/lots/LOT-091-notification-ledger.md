# LOT-091 — Notification ledger (already-notified state)

- **Module:** HFRStorage (`Sources/HFRStorage/SmallStores/NotificationLedger/`)
- **Difficulty / model:** easy (Opus 5.5 author → Fable 5.1 reviewer; the plan routes Sonnet → Opus)
- **Issue:** [#183](https://github.com/ezzz/HFRnow/issues/183) · feature FEAT-005 ([#149](https://github.com/ezzz/HFRnow/issues/149)), **proposed by Bybifok** (`moust4ki`): the "Vérifier HFR" check and its "already notified" state. Other lots of the feature: LOT-092 ([#184](https://github.com/ezzz/HFRnow/issues/184), the check flow), LOT-141 ([#231](https://github.com/ezzz/HFRnow/issues/231), the App Intent).
- **Depends on:** LOT-013 (#46, `Account.id`); `TopicID` is LOT-010's. Reuses LOT-064's small-store core (`SmallStoreState`, `SmallStorePersistence`, `AccountKey`) and moves `SuperFavoritesStore`'s topic order into it (`TopicOrder`), shared with the ledger.
- **Placement:** [ADR 0013](../adr/0013-storage-tiers.md) matrix, "Notification ledger": **device-only** (badges and notifications are per device; a duplicate on a second device is acceptable).

## Legacy sources
`origin/master` at `21173e77` (the issue cites `origin/master`); on-device data only, no HFR request, so no HFR-PROTOCOL subsection.

| Legacy | What it gives the ledger |
|---|---|
| `HFRswift/Swift/MPBackgroundService.swift:93-101` | read `nb_mp` (one global count), store the count just read, notify when it is higher than the stored one |
| `MPBackgroundService.swift:94`, ObjC `Classes/HFRplusAppDelegate.m:253-256` | a stored count above 1000 or below 0 is reset to 0 |
| `Classes/HFRplusAppDelegate.m:706` (`updateMPBadgeWithString:`), `HFRswift/Swift/MPListView.swift:442` | the count shown in the app (tab badge) overwrites `nb_mp`: a count seen in the app is not notified later |
| `MPBackgroundService.swift:73-74, 96`, `HFRplusAppDelegate.m:221-222, 258, 485` | `nb_mp_failure`, a count of failed checks shown in a debug notification text (`:270`); no decision reads it |

Legacy never notified flags nor named conversations, and kept no last-check date (the system scheduled `BGAppRefreshTask` at least 60 s apart, `MPBackgroundService.swift:37`).

## Behaviour

### `NotificationSummary` (input)
What one check saw for one account: `unreadPrivateMessages: Int?` (LOT-047's count), `unreadThreads: Set<Int>?` (topic numbers of unread conversations, when the check read the MP list), `flaggedTopics: [FlaggedTopicStamp]?` (topic and date of its last post, from the flags list). **Which flag rows:** the flagged topics the check listed. A row the caller has evidence the member already read has nothing to notify and may be left out, but the flags page gives no such evidence today: `FavoritesParser` reads every row as `.unknown` (LOT-024, decision D1), and the only capture (`R10`) shows the same read icon on both rows. Until a capture settles it (*pending capture*: a logged-in `owntopic=1` page with one read and one unread topic, on #109 / CAP-N5 #173), the ledger's date rule is the only de-duplication, so a new post the member has already read can be notified once. A row whose last post has no date (`LastPost.date` is optional) is left out, so it is never notified. **A nil part is "no information"** (LOT-047 contract: logged out or an unknown page is never 0): it yields no news and is not recorded. LOT-092's `UpdateSummary` (HFRClient) maps to it in the app: HFRStorage cannot import HFRClient.

### `NotificationLedger` (pure value, per account)
| Part | News (`diff(summary:)`) | Record (`record(_:)`) | Never recorded |
|---|---|---|---|
| Unread count | `count − recorded`, when positive (legacy `newCount > oldCount`) | the count read replaces the stored one, up or down (legacy stored every count) | baseline 0 (legacy `integerForKey` default): a first check with unread MPs notifies |
| Unread conversations | the unread set minus the recorded one, sorted | the set read replaces the stored one (saved sorted): a conversation read then unread again is news again | **baseline**: no news (no legacy) |
| Flagged topics | a recorded topic whose last post is later than the recorded one, or a topic not recorded whose last post is later than the **watermark** (the latest last post among dropped topics; none yet: any date); one news per topic (its latest date), in the summary's order | per topic, the latest of the recorded and the read last post; topics absent from the summary are kept; at most `topicLimit` (500) topics, the oldest last posts dropped, the watermark raised to the latest dropped one | **baseline**: no news (no legacy; a first check would otherwise notify every flagged topic) |

- `record` is idempotent (a second identical record changes nothing and returns false); `diff` after `record` of the same summary is empty. An invalid summary (negative count, topic number not positive) is no news and is not recorded, at the value level too (the store throws for it).
- `isDue(now:minimumInterval:)`: true when never checked, when `now − lastCheck ≥ minimumInterval` (boundary included), or when the last check is later than `now` (the clock went back, which would otherwise block checks); a negative interval counts as 0. `markChecked(at:)` records a check whatever it found: a failed request counts towards the politeness interval too. The interval itself is the caller's (LOT-141).

### `NotificationLedgerStore` (actor)
`ledger(for:)`, `markCheckedIfDue(account:now:minimumInterval:)`, `recordNews(_:account:)`, `record(_:account:)`, `markChecked(account:at:)`, `removeAccount(_:)`, `loadFailure()`, `reload()`, `discardUnreadableData()`.
- **One step per decision**: `markCheckedIfDue` checks `isDue` and records the check in one actor step, `recordNews` computes the news and records them in one step. Two overlapping checks (the App Intent and a Home refresh, or two intent runs) get the turn once and each news once; a caller that reads `ledger(for:)` then writes in two calls has no such guarantee. One JSON document (`NotificationLedgerDocument`, version 1) over `SmallStorePersistence` (`FileSmallStorePersistence` in the app, `InMemorySmallStorePersistence` in tests).
- Ledgers are keyed by account key (`AccountKey`, ADR 0013 §7): `Alice` and `alice` share one, as their lists and drafts do. An empty key is `emptyAccount`.
- A summary with a negative count or a topic number not positive is `invalidValue`; nothing is saved.
- `removeAccount` drops the account's ledger; the app calls it when the account is removed (wired with LOT-141).
- LOT-064's failure rule: an unreadable or newer document makes reads answer an empty ledger and writes throw, until `reload()` or `discardUnreadableData()`.
- The app records what it showed too (legacy `HFRplusAppDelegate.m:706`), so a count seen in the app is not notified by the next background check.

## Edge cases
- Flags dates are to the minute (`HFRDate`): two posts in the same minute after a record are one news, and a post in the minute already recorded is not news.
- A topic dropped by the 500 limit and listed again unchanged is not news (watermark); a post after the watermark is. The cost: a newly flagged topic whose last post predates the watermark is not notified, which needs more than 500 flagged topics.
- What the flags list lists (every flagged topic, or only those with news) is not captured for this check (#109, CAP-N5 #173): the rule above holds either way, and a topic that leaves the list keeps its record.
- An unreadable store answers an empty ledger, so the caller sees "due" and, for the count, a baseline of 0; its writes throw, so it cannot record: the app should surface `loadFailure()` rather than notify in a loop (LOT-141).

- **LOT-140** (#230) keeps the legacy BGTask: unless its check reads and records this ledger (`recordNews`), one MP can be notified twice, by the BGTask and by the App Intent. Noted on #230.

## Fixtures
None: on-device data, synthetic summaries and documents.

## Intentional differences from legacy
1. **One ledger per account** instead of one global `nb_mp`: switching accounts no longer compares one account's count with another's. CHANGELOG-LEGACY #50.
2. **No 1000 cap**: legacy reset a stored count above 1000 to 0, so a member with more than 1000 unread MPs was notified at every check; counts are validated (≥ 0) when recorded instead.
3. **No information is not 0**: a check that could not read the count leaves the baseline alone. The Swift port only stored a parsed count (`extractMPCount` nil, `MPBackgroundService.swift:91`), but the ObjC path stored the `intValue` of whatever text it found (`HFRplusAppDelegate.m:243-259`), 0 when there was no number, which reset the baseline and notified every unread MP again at the next check.
4. `nb_mp_failure` is not kept: no decision read it.
5. Conversations and flags, and the last-check date, are new (FEAT-005).

## Tests
`NotificationLedgerTests` (count rule and baseline, the 1000 case, conversations, flags with later, equal and older last posts, a topic listed twice, idempotent record, absent parts, the 500 limit, `isDue` at the boundary, before it, never checked, clock back, negative interval; `markChecked`) and `NotificationLedgerStoreTests` (per account key, a second record saves nothing, invalid summaries, empty account, account removal, a file reopened gives the same ledger, an unreadable store). Eighteen mutations, each applied and reverted, each failed named tests: no first-check count news, a count that never goes down, conversations news on a first check, flag news on an equal date, a flag record that replaces instead of keeping the latest, no de-duplication, no topic limit, due only strictly after the interval, a future last check blocking, an absent part clearing the record, no validation in the store, account removal and reads by raw account instead of account key, and after review: no watermark, no validation in the value, `markCheckedIfDue` always due, `recordNews` not recording, conversations saved unsorted. The store tests also cover two overlapping `recordNews` and `markCheckedIfDue` calls, and the corrupt-file test covers the new store.

## Learnings
- A "nothing known" part must be modelled apart from "zero" in the input itself (an optional), or every consumer re-derives LOT-047's contract.
