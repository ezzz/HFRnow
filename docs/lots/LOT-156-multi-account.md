# LOT-156 — Multi-account consistency

- **Module:** App
- **Difficulty / model:** medium (Opus 5.5 → Fable 5.2)
- **Issue:** [#246](https://github.com/ezzz/HFRnow/issues/246)
- **Depends on:** LOT-081 (accounts, `currentSessionGeneration`), LOT-084 (drafts per account), LOT-130 (MPStorage per account), LOT-140 (background MP check)

Everything a member sees or sends follows the selected account. Most of it already does, by construction of the earlier lots: this lot
audits each item against legacy, fixes the two that did not (the app icon badge, the session's expiry), and pins the switch during a send
(Q-8) with a test.

## Legacy sources

At `87fe0d1c` (AGENTS.md §2):

| Legacy | What it does |
|---|---|
| `Classes/MultisManager.m:88-105` (`setPseudoAsMain:`) | marks the account main, then `setCookiesForMain` and `[[MPStorage shared] initOrResetMP:pseudo]` |
| `Classes/MultisManager.m:107-123` (`setCookiesForMain`) | `lougout` (every cookie of the shared jar deleted, the multi-quote cookies included), then the main account's cookies set, `login`, `kLoginChangedNotification` |
| `Classes/MultisManager.m:155-166` (`lougout`) | empties the shared jar, `[HFRplusAppDelegate logout]`, `kLoginChangedNotification` |
| `Classes/HFRplusAppDelegate.m:788-793` (`logout`), `:704-706` (`updateMPBadgeWithString:`) | a logged-in app resets `nb_mp` to 0 (`[nil intValue]`): the Messages badge and, through `nb_mp`, the icon badge |
| `HFRswift/Swift/MainWindow.swift:1374`, `:1564-1567`, `:1779-1784` | the icon badge follows `nb_mp` (`syncAppIconBadge`) |
| `HFRswift/Swift/MainWindow.swift:226`, `Favorites.swift:779`, `MPListView.swift:648` | categories, favourites and MP list reload on `kLoginChangedNotification` |
| `HFRswift/Swift/AccountSessionService.swift:77-115` (`makeReplySessionContext`) | a reply forces the **main** account's cookies into the shared jar, keeping the `quotes*` cookies across that reset |
| `HFRswift/Swift/MPBackgroundService.swift:89-97` | the background check reads the shared jar (the main account) and one global `nb_mp`; `:60-66` (`updateAppIconBadge`) sets the icon |
| `HFRswift/Swift/AccountMenuViews.swift:11-26` (`AccountMenuRow`) | an account row is its avatar, its name and a checkmark: no session state, no expiry |

## Legacy counterpart (app lots)

- `App/SwiftHFR/Root/RootModel+Notifications.swift` (`appIconBadge`): `HFRswift/Swift/MainWindow.swift (RootTabView.syncAppIconBadge)` and the `nb_mp` reset of `HFRplusAppDelegate.m (logout)`.
- `App/SwiftHFR/Accounts/AccountsView.swift` (`AccountRowView.statusText`, `footer`): `HFRswift/Swift/AccountMenuViews.swift (AccountMenuRow)`.

## Audit: what follows the selected account

| Item | Legacy @ `87fe0d1c` | SwiftHFR | Test |
|---|---|---|---|
| Lists (forums, favourites, flags, MP list, search) | reloaded on `kLoginChangedNotification` | the whole root is rebuilt on the new session (`RootView.buildKey` = `currentSessionGeneration`, LOT-081); the tab or destination is kept | `AccountSwitchTests`, `AccountsModelSessionGenerationTests` (LOT-081) |
| Drafts (reply, new topic, MP, edit) | one global text | per topic (or forum) **and** per account (`ComposerServices.account`, LOT-063/084/089/128); a sheet open at a switch goes away and saves its draft under the previous account | LOT-084 suites |
| Multi-quote selection | the shared jar is emptied at a switch: the selection is lost | each account's `HFRSession` holds its own `quotes*` cookies (LOT-042/049): the new account sees its own selection, and the previous one finds its selection again when it comes back (for the cookie's hour) | LOT-049 `QuoteFlowTests` |
| Send during a switch (Q-8) | the reply forces the main account's cookies at send time | a composer posts through the session of the root it was opened in; a switch never touches that session, so the send goes out as the account shown when it started, or is refused before its POST if that session itself changed identity (`sessionChanged`, LOT-048). The sheet goes away with the old root: the send's own task still ends, a confirmation discards that account's draft only, and an unconfirmed or failed outcome lands on the discarded model, unseen; its draft stays under its account (saved before the request leaves) | `MultiAccountConsistencyTests.aSwitchLeavesTheComposerOfThePreviousAccountOnItsOwnSession`, `aSendHeldAcrossASwitchDiscardsOnlyItsOwnAccountsDraft`; engine `PostingSessionChangeTests` |
| MPStorage | `initOrResetMP:` at every switch | one `MPStorageSyncModel` per account, its state per account (LOT-130, GAP-181); the root's rebuild drops the previous one | LOT-130 suites |
| Messages badge (tab) | `nb_mp` reset to 0 at a switch | the count is the session generation's (`SharedPrivateMessageCounts`, LOT-146); 0 until a page of the new session gives one | `PrivateMessageBadgeTests` |
| App icon badge | follows `nb_mp`, reset to 0 at a switch and a logout | **changed here**: a root built logged out, or rebuilt on a new session, shows 0 until a page gives its count; only a window's first root with an account leaves the icon alone, as the background check set it for that account (GAP-192) | `MultiAccountConsistencyTests` (badge), `AppIconBadgeHostedTests` |
| Background MP check | the shared jar, one global `nb_mp` | the current account's stored session and its own ledger (LOT-140, LOT-091); a check for another account never compares counts across accounts | `MPBackgroundCheckTests` (LOT-140) |
| Notification tap after a switch | — | opens the current account's list; a conversation it does not list is not selected (LOT-140) | LOT-140 suites |
| Session state | none shown | each row says its state; **added here**: a confirmed session shows the date its login cookies lapse, and the screen explains the 30 days | `MultiAccountConsistencyTests` (expiry) |

## UX evolutions (app lots)

- **GAP-246** (new, `b·operator`: the scope of #246, "session status shown plainly, expiry ~30 days explained", user feedback ≈12): Comptes shows "Session valable jusqu’au <jour mois>" under an account the forum confirmed, and a footer: HFR keeps an account logged in 30 days, renewed whenever the app opens the forum with it; past that, « Se reconnecter » is enough, and the account's drafts, lists and settings stay. "Session expirée" becomes "Session expirée : reconnectez-vous".
- **GAP-192** (edited): the icon badge is cleared by a root logged out or rebuilt on a new session until its first count. Parity, not an evolution: legacy's switch and logout reset `nb_mp`.

## Behaviour

**Icon badge.** `RootModel.clearsIconBadgeBeforeCount(accountName:initial:)` is true when the root has no account, or when it is rebuilt (`initial` is set: `RootView` passes the destination it kept, which only exists after a first root). `appIconBadge` is then 0, not nil, until `privateMessageCount.latest` has a value; the badge setting off still gives 0. A rebuilt root of the same account (a re-login) clears the icon too, until its home page gives the count back a moment later.

**Session expiry.** `AccountRow.sessionExpiry` is the earliest `expiresDate` of the stored `md_user` and `md_passs` cookies, the `deleted` marker ignored (`AccountRow.sessionExpiry(in:)`). HFR sets both for 30 days at the login and again on the logged-in home page, followed list and profile page 1 (HFR-PROTOCOL §6b, `W03`; doubled `Set-Cookie`, `R74`; other pages not captured), which the app loads at every launch: the footer says "renewed whenever the app opens the forum", not "every page". The date is the **stored** one: the store takes the jar's cookies after a login and after every check that confirms the session (`persistSession`), so after the launch check it is the date the forum last set; pages read since may have pushed it further. It is shown only for a `valid` session (a `restored` session's stored date says nothing about the forum's view yet) and only when it is later than now: a re-login whose store write failed is `valid` with the old cookies still stored. Format: `Date.FormatStyle(locale: fr_FR).day().month(.wide)` in the device's time zone ("18 décembre").

## Edge cases

- **Re-login of the current account**: same account, new session object or the same renewed one; when the root is rebuilt, the icon goes to 0 until the home page's count.
- **A second window** (LOT-146) opened after a switch builds a first root (`initial` nil): it leaves the icon alone; the first window's rebuilt root already cleared it, and the count is shared per generation.
- **The launch import** (LOT-158) can bump the generation at launch (`readStoreAgain`): the rebuilt root clears the icon until the home page's count, a moment.
- **No count ever** (offline after a switch): the icon stays at 0 rather than showing the previous account's count; legacy did the same.
- **Notifications of the previous account** stay in the Notification Center: a tap opens the current account's list (LOT-140). Not withdrawn at a switch, as legacy.
- **A cookie with no date** (none captured): no expiry line.
- **An unreadable credential store at launch**: the first root is logged out and clears the icon, even a count the background check set before. Accepted: the app then shows no account (the store problem screen), and the background check cannot read the account either (`noAccount`); a retry that reads the store rebuilds the root, whose home page gives the count back.

## Fixtures

None new: the expiry rule reads cookies whose shape `W03` and `R74` fixed (HFR-PROTOCOL §6b).

## Intentional differences from legacy

1. **Multi-quote selection per account** (LOT-042/049, recorded here): legacy lost the selection at a switch (the jar emptied); each account keeps its own now.
2. **Session expiry shown** (GAP-246): legacy showed nothing until requests failed.

## Device checks owed (#893)

- Switch account with an unread MP on the first one: the icon badge goes to 0, then to the second account's count once the home page loads; log out the last account: the icon badge goes to 0.
- Comptes: "Session valable jusqu’au …" under a confirmed account, the footer readable in Dynamic Type XL, light and dark.
- Start a reply as account A, switch to B from the account menu during the send: the reply is posted as A (an unconfirmed outcome is not shown, the sheet is gone; A's draft stays), and B's composer holds B's own draft.

## Tests

`App/SwiftHFRTests/Accounts/MultiAccountConsistencyTests.swift`:

- `aSwitchLeavesTheComposerOfThePreviousAccountOnItsOwnSession`: the composer services of user1's environment keep user1's session object, identity and account key after a switch to user2; the new environment's poster is user2's session.
- `aSendHeldAcrossASwitchDiscardsOnlyItsOwnAccountsDraft`: user1's send held at its POST while user2's composer opens the topic; one POST with user1's text, user1's draft discarded, user2's kept.
- `theAppsRootAppliesTheRuleToItsOwnAccountAndDestination`: the rule through `RootModel(environment:store:initial:)`.
- `AppIconBadgeHostedTests`: the existing launch cases now run with an account (unchanged `[3]`, `[3, 3]`); `aRootRebuiltOnANewSessionClearsTheIconBeforeItsCount` (`[0, 3]`), `aLoggedOutRootClearsTheIcon` (`[0]`).
- `aRootLoggedOutOrRebuiltClearsTheIconBadgeUntilItsCount`: the rule's four cases.
- `aClearingRootShowsZeroUntilAPageGivesItsCount`: 0 before a count, then the count, then 0 with the setting off. Fails with `appIconBadge` returning nil before a count.
- `theLaunchRootStillLeavesTheBackgroundChecksBadgeAlone`: nil before a count in a first root (GAP-192 kept).
- `theSessionExpiryIsTheEarliestLoginCookieExpiry`, `eachRowCarriesItsOwnAccountsExpiry`, `theStatusLineSaysWhenAConfirmedSessionLapses` (a past date is not shown).

## Learnings

- Most of "everything follows the account" came free from one decision of LOT-081: rebuild the root on a new session object, and give each account its own `HFRSession`. A new per-account state belongs in `AppEnvironment.make(session:accountName:)` or a model the root builds, never in a global.
