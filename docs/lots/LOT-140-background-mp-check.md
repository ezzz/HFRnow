# LOT-140 — Background MP check, badge and notification

- **Module:** App (`App/SwiftHFR/Notifications/`); the pure notification rule in HFRClient (`Sources/HFRClient/MPPoll/MPNotificationPlan.swift`), the check-interval setting in HFRStorage
- **Difficulty / model:** medium (Opus 5.5 → Fable 5.2)
- **Issue:** [#230](https://github.com/ezzz/HFRnow/issues/230), with the operator's scope decisions of 2026-11-07 and the UI comparison of 2026-11-11 on that issue
- **Depends on:** LOT-047 (`MPUnreadPoll`), LOT-044 (`SessionRefreshFlow`, not called here: see Behaviour), LOT-065 (credential store), LOT-126 (MP list), LOT-119 (settings screen); LOT-091's ledger (`NotificationLedgerStore`)

## Legacy sources
`git show 87fe0d1c:<path>` (AGENTS.md §2).

| Legacy @ `87fe0d1c` | What it does |
|---|---|
| `HFRswift/Swift/MPBackgroundService.swift:15, 21-31` | `BGAppRefreshTask` `com.hfrplus.refresh_mp`, registered from the app's `init` (`HFRswiftApp.swift:21`) |
| `MPBackgroundService.swift:35-44` | `scheduleAppRefresh`: `earliestBeginDate` = now + 60 s; called when the scene goes to the background (`HFRswiftApp.swift:31-35`) and at the start of every run (`:71`) |
| `MPBackgroundService.swift:48-55`, `HFRswiftApp.swift:27-29` | asks for notification permission (`.alert`, `.sound`, `.badge`) at every launch: the system shows the prompt once |
| `MPBackgroundService.swift:60-66`, `MainWindow.swift:1564-1567, 1779-1784` | app icon badge = `nb_mp` when `mp_badge_enabled`, else 0, set by the running app when either changes; the background run does not set it |
| `MPBackgroundService.swift:70-108` | one `GET https://forum.hardware.fr` (5 s) with the shared cookie jar, count from `cCatTopic red`; stores it in `nb_mp`; notifies when it is higher than the stored one |
| `MPBackgroundService.swift:140-160` | one notification, body "Vous avez un nouveau message privé", sound default, `userInfo` `destination = messages`, random identifier (they stack), no thread identifier |
| `Classes/HFRplusAppDelegate.m:186-212`, `HFRswift/Swift/Common.swift:55-67`, `MainWindow.swift:1656-1665, 1786-1788` | tap: a pending "open messages" flag in `UserDefaults`, the root selects the Messages tab and reloads it |
| `HFRswift/Info.plist:5-8, 211-215` | `BGTaskSchedulerPermittedIdentifiers` = `com.hfrplus.refresh_mp`; `UIBackgroundModes` `fetch`, `processing` |
| `HFRswift/Swift/AppSettingsView.swift:527-531` | section "Notifications MP": one switch, "Badge messages non lus" (`mp_badge_enabled`, default on) |
| `Classes/HFRplusAppDelegate.m:488` | the debugger command that simulates the task (device check) |

## Legacy counterpart (app lots)
- `App/SwiftHFR/Notifications/MPBackgroundCheck.swift` — `HFRswift/Swift/MPBackgroundService.swift (MPBackgroundService.performBackgroundCheck)` @ 87fe0d1c
- `App/SwiftHFR/Notifications/MPBackgroundScheduler.swift` — `MPBackgroundService.swift (registerBGTask, scheduleAppRefresh)` @ 87fe0d1c
- `App/SwiftHFR/Notifications/MPNotificationCenter.swift` — `MPBackgroundService.swift (requestNotificationAuthorization, updateAppIconBadge, scheduleNotification)` @ 87fe0d1c
- `App/SwiftHFR/Notifications/MPNotificationRouter.swift` — `HFRswift/Swift/Common.swift (MessagesNotificationNavigation)` @ 87fe0d1c
- `App/SwiftHFR/Notifications/MPNotificationSettingsSection.swift` + `MPNotificationSettingsModel.swift` — `HFRswift/Swift/AppSettingsView.swift (notificationsSection)` @ 87fe0d1c

## UX evolutions (app lots)
All `b·operator` (operator decisions of 2026-11-07 on #230), rows GAP-011, GAP-190, GAP-191, GAP-192 edited in the PR's `### Ledger`:
- One notification per conversation with news instead of one fixed text; title and body from the MP list row; a burst of more than 5 collapses into one summary (GAP-191).
- Tap opens the conversation (a summary opens the list) (GAP-011).
- Réglages › Notifications MP gains "Vérifier les messages" (15 min to 4 h, Jamais; default 30 min), its footer, « Dernière vérification » and a button to iOS's notification settings (GAP-190).
- The background run sets the app icon badge too (GAP-192): legacy only set it from the running app, so the icon kept the last count the app saw.

## Behaviour

### Check (`MPBackgroundCheck.run(now:)`)
1. **Setting:** "Jamais" → nothing is sent and nothing is scheduled.
2. **Account:** the current (main) account of the credential store (LOT-065; the Keychain items are `AfterFirstUnlock`, Q-9). None, or an unreadable store → nothing is sent.
3. **Politeness:** `NotificationLedgerStore.markCheckedIfDue(account:now:minimumInterval:)` with the chosen interval less one minute (`schedulingSlack`: iOS may launch the task right at its earliest date, computed just before the previous check stamped its own time) (operator: shared with LOT-141). Not due, or the ledger unreadable → stop. A check is stamped whatever it then finds (LOT-091), so « Dernière vérification » also shows a check that got no information.
4. **Count:** `MPUnreadPoll(session:).unreadCount()` (LOT-047) on a session built from the stored cookies and `hash_check`, used for this run only and never written back to the store or to `AccountsModel` (D3). `nil` (no information), `.sessionExpired` or any error → stop: no notification, no badge change, nothing recorded (#230 acceptance, LOT-047 contract). `SessionRefreshFlow` is not called: the next foreground launch checks the session (`AccountsModel.restore`, #300) and asks for a new login; a background run has no one to ask.
5. **List:** `PageFetcher.privateMessages(page: 1)` + `PrivateMessageListParser` (LOT-126), never a thread page (E25: a thread page marks it read). A failure here keeps the count (step 6 records it with no thread set).
6. **News:** `recordNews(NotificationSummary(unreadPrivateMessages: count, unreadThreads: <topic numbers of unread rows of page 1>))`, one actor step (LOT-091).
7. **Notifications:** `MPNotificationPlan.make(newThreads:in:)` (below) on the news' `newThreads` and the page's rows. When that gives nothing (the list could not be read, or no conversation became unread: a reply to one already unread, until #571) and the count went up from a recorded count (not the first check), one legacy notification "Vous avez un nouveau message privé" (identifier `mp-summary`) that opens the list. A conversation's own notification withdraws that legacy one, so a conversation first announced while the list was unreadable is not announced twice.
8. **Badge:** `setBadgeCount(count)` when `mp_badge_enabled`, else 0.

At most 2 requests per run (`GET /`, the MP list page 1), as the operator decided.

### Notification plan (`MPNotificationPlan`, HFRClient, pure)
- One notification per conversation with news, in page order: identifier and `threadIdentifier` `mp-<topic number>` (a later news replaces it instead of stacking).
- One-to-one: title = the interlocutor (as printed, without the `U+200B` HFR puts in long pseudos), body = the conversation's title. Group: title = the conversation's title, no body. No message content.
- More than 5 conversations (`MPNotificationPlan.burstLimit`) → one summary, identifier `mp-summary`, title "Messages privés", body "<n> nouveaux messages privés"; it opens the list.
- A news thread number the page does not list (it cannot happen from page 1, but the plan does not assume it) gives no notification of its own; when nothing is left the plan is empty.
- Every notification: category `mp` (registered with `hiddenPreviewsBodyPlaceholder` "%u nouveaux messages privés", for Show Previews = Never / When Unlocked), interruption level `.active`, sound `.default`, `userInfo` `destination = messages` (legacy key and value) and `mpTopic = <number>` for a conversation.

### Scheduling (`MPBackgroundScheduler`)
- SwiftUI's `.backgroundTask(.appRefresh("com.hfrplus.refresh_mp"))` scene modifier is the handler (legacy registers the same identifier, so the system keeps the update path); the run reschedules first, as legacy.
- `earliestBeginDate = now + interval` (operator: "ce délai est un minimum, pas une garantie"); "Jamais" cancels the pending request. Scheduled when the scene goes to the background, at the start of each run, and when the setting changes.

### Permission
At launch, as legacy (`HFRswiftApp.swift:27-29`, operator's comparison of 2026-11-11): `requestAuthorization([.alert, .sound, .badge])`; iOS shows the prompt once. The category is registered at the same time.

### Tap
`AppDelegate` is the `UNUserNotificationCenter` delegate through a main-actor conformance (the async handler returns on the main actor). `MPNotificationRouter.shared` holds the pending destination (the conversation's number, or the list). The root selects Messages, and `MessageListModel.open(topic:)` reloads page 1 and selects that conversation when it lists it (the reader then opens at its latest message, LOT-126); else the list stays shown. A summary loads page 1, whatever page was on screen. A tap that cold-launches the app waits for the root to be built.

### Foreground
- The running app sets the icon badge from the Messages badge count (`RootModel.unreadPrivateMessages`, which already applies `mp_badge_enabled`), as legacy `MainWindow.swift:1779-1784`.
- What the app shows is recorded in the ledger (LOT-091 rule, legacy `HFRplusAppDelegate.m:706`): every count a page announces (`record(unreadPrivateMessages:)`), the unread conversations of MP list page 1 when it loads, and page 1's unread set with the badge's count again when a conversation is read here. A conversation seen unread in the app is not notified by the next background run; one read here leaves the ledger's set, so its next reply is.

### Settings (Réglages › Notifications MP)
- "Badge messages non lus" (`mp_badge_enabled`, legacy).
- "Vérifier les messages": 15 min, 30 min, 1 h, 2 h, 4 h, Jamais (`mp_check_interval`, minutes, `0` = Jamais, default 30; an unknown stored value reads as 30). Footer « Au plus souvent toutes les <durée>. iOS décide du moment réel ; ce délai est un minimum, pas une garantie. » (« Aucune vérification en arrière-plan. » for Jamais).
- « Dernière vérification : <heure> » from the ledger of the current account (absent before the first one).
- « Réglages des notifications » opens iOS's notification settings of the app (`UIApplication.openNotificationSettingsURLString`).
- No Do Not Disturb option: the app cannot read Focus, and iOS filters per Focus (operator).

### Logs
No pseudo, no subject, no count in logs (operator): only the outcome kind.

## Edge cases
- First check of an account: the ledger records the thread set silently (LOT-091 baseline); the count rule of the ledger would report the count as news, but no notification is built from the count when the list was read.
- Two runs with no change: no news (ledger), no notification.
- An unknown or expired answer: nothing recorded, nothing notified, badge kept.
- Account switched between a run and a tap: the tap opens the current account's list; a conversation it does not list is not selected.
- The ledger file unreadable: `markCheckedIfDue` throws → the run stops (no notification loop, LOT-091).

## Fixtures
Captures read in place (no new fixture): `R336`-`R338` (#567, reply in an unread one-to-one conversation), `R610a`/`R610b` (an older read row becomes unread, #610), `R610e`/`R610g` (group row, creator's list), `R13u1`, `R13a` (MP lists), through `PrivateMessageListParser`.

**Pending (#571, ledger follow-up, `status: ready`):** a new reply in a conversation that is already unread changes only `repliesCount` and the last-post date (`R336` → `R337` → `R338`, HFR-PROTOCOL §6c LOT-140); the ledger keeps only the unread set, so that reply is **not** notified until #571 adds the per-thread watermark. LOT-140 reads only `NotificationNews.newThreads`: once #571 reports moved-forward threads there, the plan notifies them unchanged (the `mp-<number>` identifier replaces the earlier notification). The #230 acceptance item "a reply in an already-unread conversation produces a notification" closes with #571.

## Intentional differences from legacy
| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | one fixed text when the home count rises; a reply in an unread conversation sends nothing | one notification per conversation that became unread, from the list row | operator 2026-11-07 |
| D2 | random identifiers, notifications stack | `mp-<number>` identifier and thread identifier | operator 2026-11-07 (part of #509) |
| D3 | shared cookie jar, cookies the answer sets kept | a session for the run only, written back nowhere | one session per account (LOT-081), no stale write (LOT-047 D3) |
| D4 | `earliestBeginDate` 60 s | the chosen interval (default 30 min) and the ledger's interval guard | operator 2026-11-07 |
| D5 | the background run never sets the icon badge | it does, per `mp_badge_enabled` | an icon badge that only moves while the app runs is stale whenever it matters |
| D6 | `UIBackgroundModes` `fetch` and `processing` | `fetch` only | `processing` serves `BGProcessingTask`, which neither app uses |
| D7 | one global `nb_mp`, `nb_mp_failure` | the per-account ledger (LOT-091 D1-D4) | LOT-091 |
| D8 | tap opens the Messages tab | the conversation, or the list for a summary | operator 2026-11-07 |
| D9 | notification triggered 3 s after the check (`UNTimeIntervalNotificationTrigger(timeInterval: 3)`, `MPBackgroundService.swift:148`) | delivered at once (`trigger: nil`) | nothing waits on the delay; a background task should finish quickly |

## Tests
- HFRClient `MPNotificationPlanTests` (Linux): texts of a one-to-one and a group row from captures, identifiers, order, the burst limit (5 → five, 6 → summary), an unknown number, an empty news list.
- HFRStorage `MPCheckIntervalTests`: values, default, an unknown stored value.
- App `MPBackgroundCheckTests`: Jamais sends nothing; not due sends nothing; `nil` / expired / network error → no notification, no badge, nothing recorded; a list failure keeps the count; two identical runs → one notification; badge off → 0; first run silent. App `MPNotificationRouterTests` and `MessageListModel` open-from-notification test.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
