# LOT-157 — Account deletion screen (HFR procedure) and local data wipe

- **Module:** App
- **Difficulty / model:** easy · Opus 5.5 → Fable (AGENTS.md §6)
- **Issue:** [#247](https://github.com/ezzz/HFRnow/issues/247)
- **Depends on:** LOT-081 (accounts, #99), LOT-119 (settings, #210), capture CAP-N6 (#174, `R98a`, merged in #435)

## Legacy sources
At `87fe0d1c` (`legacy/duo-inner-cover`, AGENTS.md §2; `git show 87fe0d1c:<path>`):

| Where | What |
|---|---|
| `HFRswift/Swift/PlusTab.swift:55-63` | iPhone Plus tab: the red "Supprimer mon compte" row opens the mail composer at once (no screen), or the alert "Mail indisponible" when no mail account is set up (`:71-75`). |
| `HFRswift/Swift/PlusTab.swift:79-110` | `AccountDeletionView` (iPad sidebar, `MainWindow.swift:2017-2018`): a `ContentUnavailableView` "Une demande de suppression sera préparée dans l’application Mail." and a destructive "Préparer la demande" button opening the same composer. |
| `HFRswift/Swift/PlusTab.swift:139-174` | `DeleteAccountMailComposeView`: `MFMailComposeViewController` with a fixed subject, a fixed body and a recipient address hard-coded in source (Q-10). |
| `Classes/MultisManager.m:125-153` | Removing an account deletes its Keychain entry only; legacy has no wipe of the account's other data. |

## Legacy counterpart (app lots)
- `App/SwiftHFR/Accounts/AccountDeletionView.swift` — `HFRswift/Swift/PlusTab.swift (AccountDeletionView)` @ `87fe0d1c`.
- `App/SwiftHFR/Accounts/AccountDeletionModel.swift` — none @ `87fe0d1c` (legacy had no state beyond the composer sheet).
- `App/SwiftHFR/Accounts/AccountDataEraser.swift` — none @ `87fe0d1c` (legacy had no wipe).
- `App/SwiftHFR/Root/PlusView.swift (PlusEntryView)` — `HFRswift/Swift/PlusTab.swift (PlusHomeView)` and `MainWindow.swift:2017-2018` @ `87fe0d1c`: both the iPhone row and the iPad sidebar entry open the screen.

## UX evolutions (app lots)
- **GAP-166**, `b`: the mail composer is replaced by a screen that explains the account belongs to HFR and opens HFR's own procedure (its "Données personnelles" page) in the browser, plus a per-account wipe of this app's data. Why: no address in source (Q-10, issue #247 scope, operator 2026-10-27), and the forum has no deletion page of its own (`R98a`). **Conflict to settle:** UXD-21 (2026-11-02) says "account deletion stays the legacy mail composer unless App Review asks". This spec follows the issue's scope and Q-10 (no composer, no address); see "Decisions needed".
- The iPhone row now opens a screen, as the iPad entry did (one entry point, LESSONS 7).

## Behaviour
### The screen ("Supprimer mon compte")
1. **Explanation**: the account belongs to the forum Hardware.fr, not to the app; the app cannot delete it. HFR explains on its "Données personnelles" page how to exercise the GDPR rights, deletion included.
2. **Link** "Ouvrir la page Données personnelles": opens `https://www.hardware.fr/html/donnees_personnelles/` in the default browser (SwiftUI `Link`; the in-app browser setting does not apply: the request goes to the user's own browser, with no app cookie). Source: `R98a` and the footer of every forum page (`R01`), [HFR-PROTOCOL §6b "Account deletion"](../HFR-PROTOCOL.md). No mail composer, no e-mail address in source (Q-10). The app sends nothing to the forum.
3. **This device**: one destructive row per account in the app, "Effacer les données de <nom>", each behind a confirmation that says what goes and that the HFR account itself is not deleted. Logged out (no account): the section says there is no account on this device.
4. **Result**: success says the data of that account is erased from this device; a partial failure names the stores that could not be erased and offers "Réessayer", which erases them again for that account. A refused Keychain removal is reported and nothing else is erased.

### The wipe (one account, this device only)
Order: the account first, then its data, so no screen keeps writing as that account (the root environment is rebuilt on the next current account, LOT-081).

| Store (ADR 0013 appendix) | Where | How |
|---|---|---|
| Credentials, cookies, `hash_check`, avatar bytes (A) | Keychain item `hfr.accounts.v1` | `AccountsModel.erase`: `deleteAccount(pseudo:)`; when no account is left, the item itself is deleted (`removeAll()`), so no Keychain item remains |
| Live session cookies (A) | the account's in-memory `HFRSession` (ephemeral jar, never `HTTPCookieStorage.shared`) | dropped with the account; the current account moves to the first remaining one |
| Drafts (D, LOT-063) | `Application Support/Drafts/drafts.json` | `DraftStore.discardAll(account:)` |
| Blocklist (B, LOT-061 local copy) | `Application Support/PseudoLists/lists.json` | `PseudoListStore.replaceBlocklist(with: [], account:)` (removes the account's key) |
| Reading positions (D, LOT-090) | `Application Support/Positions/positions.json` | `ReadingPositionStore.removeAccount(_:)` |
| Super-favourites (C, LOT-064) | `Application Support/Favorites/super-favorites.json` | `SuperFavoritesStore.replace([], account:)` (removes the account's key) |
| App smiley favourites (C, LOT-064) | `Application Support/SmileyFavorites/favorites.json` | `AppSmileyFavoritesStore.replace([], account:)` (removes the account's key) |

Every data store is erased even when an earlier one failed; the failures are returned by name. Each store keeps the other accounts' entries untouched (tests).

**Not erased, because they belong to no account** (shared by every account and the logged-out visitor, ADR 0013): the allowlist (C, global), the folded favourites sections (device UI state), the smiley search history, the rehost upload history, the offline topics (LOT-068), the avatar and page caches (public forum images and pages, rebuilt on demand), and the settings. The screen's footer says so.

**Not wired in the app yet** (nothing to erase today): the iCloud KVS lists and positions (LOT-172's `SyncedListsStore` has no app caller), the MPStorage local copy and its sync state (LOT-130), the notification ledger (LOT-091). Each lot that wires a per-account store adds it to `AccountDataEraser` (a test lists the stores it erases, so the change is visible).

## Edge cases
- **Corrupted or locked Keychain item**: the removal throws; the screen shows the store message (LOT-081 `AccountMessages`) and erases nothing else.
- **Account removed elsewhere meanwhile** (manage screen): `unknownAccount`, shown; nothing else erased.
- **A store that cannot be read** (corrupt file): its erase throws and is reported by name; "Réessayer" runs it again. The store never overwrites unreadable data (its own rule), so the data stays until the user resolves it where the store offers it.
- **A write in flight as the erased account** (a debounced draft save in a composer still open on iPad, a reading position recorded by a reader still on screen) can land after the wipe. Known limitation: the composer and reader are tied to the previous `AppEnvironment` and close when it is rebuilt; a late write leaves at most one record, erased by a later wipe of the same pseudo.
- **Two taps**: one erase runs at a time; the buttons are disabled while it runs.
- "Retirer" on the accounts screen (LOT-081) still removes only the account (legacy `MultisManager.m:125-153`): the data stays for a re-login. The wipe is the explicit action of this screen.

## Fixtures
None new. `R98a` (CAP-N6, #174) and `R01` are the sources of the URL.

## Intentional differences from legacy
- No mail composer and no hard-coded recipient (Q-10); the screen links HFR's own published procedure.
- The local wipe is new (App Store 5.1.1(v): the app's own copy of the account's data can be removed).

## Decisions needed
1. **UXD-21 vs. issue scope**: keep this screen (default: link to HFR's "Données personnelles" page, no address in source), or restore the legacy mail composer (needs the recipient address in source or in configuration, Q-10).
2. **Wording** of the French strings (defaults in `AccountDeletionView.swift`).
3. **Device-wide stores**: a second action "Effacer toutes les données de l’app" (allowlist, histories, offline topics, caches, settings) is not offered; default: not offered (the per-account wipe covers what identifies the account; the rest is shared).

## Mac checks
`xcodebuild build test` on iPhone 18 Pro and an iPad simulator (iOS 27.0); light, dark and Dynamic Type XL on the screen; the link opens Safari on the "Données personnelles" page; after a wipe of the only account, Keychain Access shows no `hfr.accounts.v1` item for the app.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
