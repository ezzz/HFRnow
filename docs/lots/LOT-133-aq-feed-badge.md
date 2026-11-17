# LOT-133 — Alertes Qualitay feed and badge

- **Module:** App (one new key in `HFRStorage`)
- **Difficulty / model:** easy · Sonnet → Opus (author → reviewer)
- **Issue:** [#223](https://github.com/ezzz/HFRnow/issues/223). Depends on [LOT-055](LOT-055-aq-client.md) (AQ client, #81),
  [LOT-082](LOT-082-adaptive-navigation.md) (Plus tab and sidebar), [LOT-119](LOT-119-settings-screen.md) (settings store).
  Gap row: GAP-005. Decisions: Q-7 (category 25), D-071-3 ([LOT-071](LOT-071-third-party-services.md): the badge is fetched at launch as legacy).

## Legacy sources
`legacy/duo-inner-cover` @ `87fe0d1c` (`git show 87fe0d1c:<path>`):

| Part | Legacy |
|---|---|
| Last check, hidden category | `HFRswift/Swift/AQPlusView.swift:38-58` (`last_check_aq`, default 2010-01-01; category 25 hidden when no account or the account is `applereview`) |
| Badge | `AQPlusView.swift:60-92` (`AQBadgeCheckService`: GET, count of `isNew`, `:86` drops the count when the list was shown meanwhile), `:29-36` (`nb_aq`) |
| List view model, view | `AQPlusView.swift:247-322` (`refresh`: sets `last_check_aq` = now and the count to 0 once the rows are set), `:324-446` (`AQPlusView`: loads once on first appearance, pull to refresh, "Actualiser", "Aucune AQ") |
| Row text | `AQPlusView.swift:208-231` (relative date), `:402-417` (row: topic title, "par <initiator>", date, AQ title and comment, bold while new) |
| Row link | `AQPlusView.swift:341-380` (page from the link, `numreponse`-less topic) |
| Launch trigger | `MainWindow.swift:1178-1192` @ `2440d79` (3 s after the main window, logged out too) |
| Older ObjC list | `Classes/AQTableViewController.m:70-71, 127-133, 154-222, 293-330` (same rules) |

## Legacy counterpart (app lots)

| SwiftHFR | Legacy @ `87fe0d1c` |
|---|---|
| `App/SwiftHFR/QualityAlerts/QualityAlertsModel.swift` | `AQPlusView.swift` (`AQPlusViewModel`, `AQBadgeCheckService`, `AQUnreadCounter`) |
| `App/SwiftHFR/QualityAlerts/QualityAlertsView.swift` | `AQPlusView.swift` (`AQPlusView`), `Classes/AQTableViewController.m` |
| `App/SwiftHFR/QualityAlerts/QualityAlertAge.swift` | `AQPlusView.swift` (`relativeDateLabel`) |
| `App/SwiftHFR/QualityAlerts/QualityAlertsSource.swift` | `AQPlusView.swift` (`AQSupport.feedURL`) |
| `App/SwiftHFR/Root/PlusView.swift`, `RootTabsView.swift`, `RootSidebarView.swift` | `MainWindow.swift` (Plus tab badge, `iAQBadgeNumer`) |

## UX evolutions (app lots)
None that changes what legacy shows. Behaviour notes (no GAP row beyond GAP-005, which this lot closes):
- **GAP-005**: the Plus tab, its "Alertes Qualitay" row and the iPad sidebar row show the new count (legacy `MainWindow.swift:1297`);
  fetched about 3 s after the root appears, logged out too. Operator observation, #223, 2026-11-11: legacy shows "25" on a first
  launch; so does this lot (nothing was ever checked, `T01` has 25 items).
- The count is recomputed at each root build (launch, login, logout) instead of read back from `nb_aq` (B23 of
  [LOT-070](LOT-070-parity-gates.md)): legacy ran it once per process, so a login kept the logged-out count.

## Behaviour
- **Source**: `AQClient.feed()` (LOT-055: cookie-less, 20 s, no redirect, typed errors). The base URL is `AQBaseURL` of the Info.plist
  (`AQ_BASE_URL` in `App/Config/Shared.xcconfig`, ADR 0007; the public host legacy hard-codes, committed so a build without
  `Secrets.xcconfig` shows the badge: **to confirm by the operator**). An empty, unexpanded or refused value (`AQConfiguration`:
  https only, never `hardware.fr`) means no source: the list says "indisponible", no request is made.
- **Hidden category (Q-7)**: items whose link has `cat=25` are removed **before** counting and listing when
  `ForumVisibility.hidesCategory` says so (logged out, an expired session, `applereview`); one rule for the forum list and AQ. Links
  with no `cat` (the canonical `…-sujet_N_P.htm` links, 2 of 25 in `T01`) are kept, as legacy (`contains("&cat=25&post")`).
- **New since**: `AQClient.isNew` (`publishedAt >= last_check_aq`, default 2010-01-01; an unreadable date is not new, LOT-055). The key
  `last_check_aq` is `SettingKey.aqLastCheck`: device scope, a `Double` of seconds since 1970. Legacy wrote a `Date` object, which
  the store cannot read: after an update it reads as "never checked" and the next count is the whole feed, once.
- **Badge** (`QualityAlertsModel.refreshCount`): fetch, filter, `newCount`. A failed or unreadable answer says nothing and keeps the count
  (legacy's silent `catch`). Every count request takes a ticket; showing the list takes one too, so a request that started before
  the visit cannot bring the badge back (legacy `:86` compared dates; a ticket also covers two equal instants).
- **List** (`load`): rows from the same items, `isNew` against the check **before** this visit; then, once the rows are set, last check =
  now and count = 0. A failure keeps the rows of an earlier success, shows a retry and marks nothing. A load overtaken by a newer one
  is dropped; a cancelled one shows nothing.
- **Launch** (`checkAtLaunch`): waits 3 s, then `refreshCount`; a cancelled wait fetches nothing.
- **Row**: title = topic title (TU abbreviation), "par <initiator>", legacy age words (`QualityAlertAge`), AQ title and comment; bold
  while new. A row opens the reader on `ReaderTarget(link:)`: topic, **page and anchor kept** (issues #105, #106; all 25 links of
  `T01` route to a topic with page and message), `numreponse` links let HFR pick the page (R25). A link that is not a forum topic
  link has no target: the row is plain text.

## Edge cases
- A feed with every item hidden: "Aucune AQ" after a successful load (the last check still moves).
- Logged-in account that is not the review account: category 25 is shown and counted.
- Titles keep the HTML entities the parser leaves (`&quot;`, B4 settled in HFR-PROTOCOL §7): shown as legacy shows them; decoding
  is not part of this lot.

## Fixtures
`T01` (`rss.php`, LOT-001 corpus run 10, #133) parsed by the real `AQFeedParser`: 25 items, two newer than 2026-10-01 (oracle
`LOT-028/T01.oracle.json`). No AQ answer is written by hand.
**Pending captures** (a Mac capture issue names them): a feed answer that holds a category-25 item (`T01` has none: the tests derive one
from a captured item by changing its `cat`, and say so); an item with a reporter comment that holds an entity (#438).

## Intentional differences from legacy
- The count is not persisted (`nb_aq`): recomputed, see above. An unreadable date is not new (LOT-055). A failed load is a failure, not
  an empty list. Rows are buttons in the Plus stack; the legacy topic row (flag cues, swipe actions) is not reproduced.
- No redirect is followed and no cookie sent (LOT-055).

## Tests
- `QualityAlertsModelTests` (9): count at launch, count against the last check (oracle: 2), showing the list marks it seen, a count
  in flight cannot bring the badge back, failures keep count and rows and mark nothing, unavailable source, launch wait and its
  cancellation, a newer load wins.
- `QualityAlertsVisibilityTests` (4 + parameterized): category 25 hidden logged out / `applereview` / expired session, shown otherwise,
  kept without `cat`.
- `QualityAlertsRowTests`: target page and anchor on `T01`, link outside the forum, the age words, unreadable date, the configured address.
- `RootAlertsBadgeTests`, `SettingKeyTests.aqLastCheck…`.
- Mutations checked to fail (the model, its source and `ReaderTarget` compiled on Linux in a scratch package): no ticket in `load`, no
  last-check write, no badge reset, no category filter, no load ticket guard, count ignoring the last check, a failure that marks
  seen, no ticket check in the count.
- Not run by the author (Linux cannot build the app): the views and the Plus integration, covered by the compile check and the
  device checks listed on the PR (light, dark, Dynamic Type XL, iPhone and iPad).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- App models that import only Foundation, Observation and the engine can be compiled and tested on Linux in a scratch SwiftPM package
  that copies their files: that is how mutations of an app lot are checked from a cloud session.
