# LOT-167 — PageNavigation exactness flag (honest list paging)

- **Module:** HFRModels
- **Difficulty / model:** easy, Sonnet → Opus
- **Issue:** #279 (implements FEAT-003, #147; related bug #104)

## Legacy sources
None: new behaviour. The legacy app shows the last pager link as the page count; Bybifok reported it as a fake total (#104). LOT-082 (#100, merged) already shows "Page N" without a total.

## Behaviour
`PageNavigation` (`Packages/HFRKit/Sources/HFRModels/Lists/PageNavigation.swift`) gains a flag telling whether its page count is **exact** or a **lower bound**. The forum-list pager is a window (`1 … 10 20 … 100 200 … 500`): its last link is a lower bound, while the exact page count of a topic is in its row (`sujetCase4`). Source: HFR-PROTOCOL §7b B1 (shape settled in §6c LOT-022, captures `R04`, `R05a`, `R05b`). The flag is `Codable` and backward compatible (absent means lower bound).

The parser (LOT-022 follow-up) sets it and the app disables "Dernière page" when it is false; both are out of this lot's scope beyond the model.

## Edge cases
- Decoding data written before the flag exists.
- Topic-page pagers, where the total is exact.

## Fixtures
Existing LOT-022 captures (`R04`, `R05a`, `R05b`); no new capture.

## Intentional differences from legacy
The legacy app treats the last pager link as the total; this lot does not.

## Learnings
To fill when the lot closes.
