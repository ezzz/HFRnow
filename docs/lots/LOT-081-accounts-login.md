# LOT-081 — Accounts and login screen

- **Module:** App (`App/SwiftHFR/Accounts/`)
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** none (claimed in `docs/LOTS.md` by #31; old francoisgn/ios-app_SwiftHFR#95)
- **Depends on:** LOT-080 (app target), LOT-043 (`LoginFlow`, `LoginError`, `LoginResult`), LOT-065 (`CredentialStore`, `AccountBook`, `KeychainCredentialStore`), LOT-042 (`HFRSession`, `AnonymousTransport`). Uses LOT-044 (`SessionRefreshFlow`), wired by [#300](#300--forum-session-check-wiring).

## Legacy sources

Legacy app: `master` of ezzz/HFRnow (read-only), SwiftUI layer `HFRswift/`.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/AddAccountView.swift:10-97`: sheet "Ajouter un pseudo", pseudo + password, submit enabled when both are filled (`:23-25`), error text, dismiss on success | `LoginView` + `LoginModel` (same fields, content types and rule; the logic is in the model) |
| `HFRswift/Swift/AccountsStore.swift:28-87`: `ObservableObject` mirroring `MultisManager`, current = main account, `setMain`, `delete`, `addAccount` | `AccountsModel` (`@Observable @MainActor`) mirroring the LOT-065 store |
| `HFRswift/Swift/AccountSessionService.swift:61-75`: login, then `addCompte`, then the new account becomes main | `AccountsModel.logIn(…, for: .newAccount)`: `LoginFlow`, then `CredentialStore.save(makeMain: true)` |
| `HFRswift/Swift/MainWindow.swift:267-290`: toolbar menu listing the accounts (tap = make main), "Ajouter un pseudo", "Déconnexion" with confirmation (`:236-245`) | `AccountMenuButton` (switch, add, manage) and `AccountsView` (select, add, re-login, remove with confirmation) |
| `HFRswift/Swift/AccountMenuViews.swift:11-48`: row with avatar, name, checkmark on the main account | `AccountRowView`, `AccountAvatarView` |
| `HFRswift/Swift/LoginService.swift:18-38`: French error texts, network errors shown with `localizedDescription` | `AccountMessages`: one actionable text per `LoginError` and `NetworkError` case |
| `Classes/HFRplusAppDelegate.m:150` (`updateAllAccounts` at launch) | `AccountsModel.restore()` at launch, one session per account, then a session check per account |
| `Classes/MultisManager.m:125-153`: delete, first remaining account promoted | `CredentialStore.deleteAccount` (LOT-065), session dropped |

## Behaviour

**`AccountsModel`** (`@MainActor @Observable`, created once by `SwiftHFRApp`, shared through the SwiftUI environment) is the only owner of account sessions in the app.

- **Mirror of the store.** `rows` (`AccountRow`: id = `Account.pseudo`, display name, main flag, decoded avatar image, session status; no cookie, no token) is always what the credential store holds. An account whose store write failed is never shown.
- **Restore at launch** (`restore()`, from the root `.task`, once per launch; concurrent calls wait for the first): read the store, build one `HFRSession(cookies:hashCheck:)` per account (LOT-042), then check each session one after the other through `SessionChecking`:
  - `ForumSessionCheck` ([#300](#300--forum-session-check-wiring)): `SessionRefreshFlow.refresh` (LOT-044) mapped to `valid` / `expired` / `unconfirmed` / `failed(NetworkError)`. A `valid` result is persisted only when the jar still holds the account's own identity (`persistSession(of:)`: a logged-out jar, `md_user=deleted`, is skipped, and `AccountBook.add` refuses a jar whose `md_user` names another pseudo; cookies and token are then written back), and only when no login was saved for that account meanwhile. Any other result changes neither the session nor the store.
- **Store problems at launch** (`storeProblem`): `corrupted` → message + "Effacer les comptes enregistrés" (confirmation, then `removeAll()`; never done silently, LOT-065); `newerVersion` → "update the app", nothing is overwritten (the store itself refuses writes); `unavailable(status:)` (Keychain error with its `OSStatus`, or a storage error without one; device locked) → "Réessayer" (`retryRestore()`). A failed write of refreshed cookies (`persistSession`) is reported the same way.
- **Add an account** (`logIn(pseudo:password:for: .newAccount)`): `LoginFlow` into a **fresh** `HFRSession`. On success the account is saved as `Account(pseudo: LoginResult.userKey, displayName: LoginResult.displayName, cookies: session.cookies(), hashCheck: session.hashCheck)` with `makeMain: true` (legacy), and only then does the session become the account's session. Typing a known account again refreshes it in place (LOT-065 `add`); its previous session is replaced only once the store accepted the new cookies.
- **Log in again** (`.existing(id:displayName:)`, offered when a session is `expired`, and from the row's context menu): `LoginFlow` into the account's **own** session with `expectedUserKey = Account.pseudo`, so another account's credentials are refused (`accountMismatch`). The current account does not change.
- **Avatar**: when the login returns an avatar URL, it is fetched in the background by `AnonymousAvatarLoader` (cookie-less `AnonymousTransport`, HFR-PROTOCOL §7 E26) only from `https://forum-images.hardware.fr` on the default port (LESSONS 37; host from `R55-p5u1`, HFR-PROTOCOL §6), without following redirects, 200 with an `image/*` content type only, at most 256 KiB. The model decodes it once (bytes that are not an image are dropped), stores it with the account (LOT-065 keeps the avatar in the Keychain item, as legacy) and hands the decoded image to the rows, so no view decodes while rendering (LESSONS 49). A failure keeps the placeholder.
- **Select** (`select(_:)`) → `CredentialStore.setMain`; the main account is the current one and `currentSession` is its session (nil when logged out).
- **Remove** (`remove(_:)`, after a confirmation) → `CredentialStore.deleteAccount`, session dropped; the first remaining account becomes current (LOT-065). No server logout (legacy did none).
- **Typed errors** (`AccountActionError`: `login(LoginError)`, `store(CredentialStoreError)`, `unknownAccount`, `storeFailed` for a storage error that is not a `CredentialStoreError`) → `AccountMessages`: each `LoginError` case and each transport failure has its own text saying what to do; a cancelled login shows nothing. Texts never contain the password, a cookie or page content.

**`LoginModel`** (`@MainActor @Observable`): fields, `canSubmit` (pseudo not blank, password not empty, no attempt running), `submit()` (one task; the sheet's Cancel and disappearance cancel it, and `LoginFlow` then leaves the session as it was), `errorMessage`, `didSucceed` (the view dismisses). The password lives only in this model; it is cleared on success, kept after a failure so the user can fix the pseudo, and never stored or logged.

**Views** (thin, no side effect in `body`, LESSONS 48–49): `LoginView` (sheet; `Form` with `.username` / `.password` content types for AutoFill, keyboard "next" / "go"), `AccountsView` (list, swipe and context-menu actions, store-problem section), `AccountMenuButton` (toolbar menu: accounts, re-login of an expired current account, add, manage; "Se connecter" when there is no account). Dynamic Type: system text styles, avatar size `@ScaledMetric`. iPhone and iPad: sheets and `List` adapt; nothing is width-specific.

**Wiring with LOT-082 (done here, #32 merged first).** `AccountsModel.currentSession` is the current account's session (nil = logged out) and `current?.id` its `md_user` value. The session's **object identity changes** on select, remove, logout, and when a known account is added again; `currentSessionGeneration` changes exactly then (`current?.id` is not enough: adding the current account again replaces its session without changing its id).
- `RootView` builds `AppEnvironment.current(of: accounts)` = `AppEnvironment.make(session: accounts.forumSession, accountName: accounts.current?.id)` and shows `AdaptiveNavigationView` with `.id(generation)`, rebuilt whenever `currentSessionGeneration` changes: the forum list, topic lists and selection start over, so lists and flags of the previous account never stay on screen. Chosen over a forwarding transport that resolves the current session per request, which would keep those lists. `forumSession` is the current session, or one logged-out `HFRSession` kept for the whole run (never an account's).
- The Q-7 rule's account name (`AppEnvironment.accountName`, read by `ForumListModel` and `ForumVisibility`) is `accounts.current?.id`, so the rule and the account menu agree; `isLoggedIn` stays the jar's (an expired current account reads as logged out), and the forum page's own logged-in state still wins in `NavigationModel`.
- `AccountMenuButton` is in the forum list's toolbar (`ForumListView`); `RootView` has no toolbar of its own.
- The navigation is shown only once `accounts.hasRestored` (a progress view before), so the first load is not made logged out and then redone.

## #300 — forum session check wiring

[#300](https://github.com/ezzz/HFRnow/issues/300), not a lot: the forum check of LOT-044 replaces the placeholder `LocalSessionCheck` (deleted; previews use a check that sends nothing). Claim `mac/w6-session-wire-opus (2026-10-28)`.

**Legacy.** `Classes/HFRplusAppDelegate.m:150` calls `updateAllAccounts` once, at launch; `Classes/MultisManager.m:280-293` GETs profile page 1 per account and has no failure callback, so a failed refresh was never retried nor reported. `applicationWillEnterForeground` / `applicationDidBecomeActive` (`HFRplusAppDelegate.m:495`, `:623`) do not refresh sessions.

**Mapping** (`ForumSessionCheck`, `App/SwiftHFR/Accounts/AccountServices.swift`), behind an app-side `SessionRefreshing` protocol that `SessionRefreshFlow` conforms to (its probe seam is internal to `HFRClient`, LOT-081 learnings):

| `SessionRefreshFlow.refresh` | `SessionCheckResult` | Row status | UI |
|---|---|---|---|
| `valid` | `valid` | `valid` | nothing; refreshed cookies and token persisted |
| `expired(.noIdentityCookie)` (nothing sent) | `expired` | `expired` | "Session expirée", re-login from the row and from the account menu (LOT-081) |
| `unconfirmed(.unrecognizedPage / .identityNotConfirmed / .sessionChanged)` | `unconfirmed` | `restored` | session kept, nothing written; a `checkFailed` row becomes `restored` |
| throws `.cancelled` | `unconfirmed` | `restored` | session kept, nothing written: a cancelled check says nothing about the forum (no code path cancels a check today) |
| throws any other `NetworkError` | `failed(error)` | `checkFailed(error)` | "Session non vérifiée (forum injoignable)"; the session is kept |

Nothing but a jar without a usable `md_user` is `expired`: an unknown page or a network error never logs an account out (LOT-044). Stale cookies at the server are not captured yet ([#281](https://github.com/ezzz/HFRnow/issues/281)): today they end `unconfirmed`, so the account stays usable until a page tells the user, and becomes `expired` only once that capture adds a `SessionExpiry` case.

**Quiet re-check** (`AccountsModel.recheckUnconfirmedSessions(now:)`, called by `SwiftHFRApp` when the scene becomes `active`): the accounts whose status is `restored` or `checkFailed` are checked again, one after the other, through the same check; `valid` and `expired` accounts are not (legacy checked at launch only; a `valid` session already proved itself this run, and an `expired` one needs a login). Rows keep their status while it runs (no "Vérification…" text). It is skipped while another re-check or a restore (launch or retry) runs, and until `recheckInterval` (5 min) has passed since the last check (launch or re-check) ended, so switching apps does not send a request each time. A result is applied only if the account still has the same session **and** the same status as when its check started: a login, a removal or the launch check that landed meanwhile wins.

**Edge cases.** No re-check starts while the launch check runs: it may already have marked one account `checkFailed` while it waits on the next one, and a re-check then would put two checks in flight (Fable review of #309). A `valid` re-check persists like the launch check (`persistSession(of:)`). No new HFR fact: the request, its rules and its pending captures are LOT-044's.

**Tests** (`App/SwiftHFRTests/Accounts/ForumSessionCheckTests.swift`; `ScriptedRefresher` in `AccountTestSupport.swift` answers with the outcomes LOT-044's capture-backed tests proved, and expires identity-less jars itself, as the flow's step 1):
`everyFlowOutcomeMapsToItsCheckResult`, `transportFailuresAreFailedAndCancellationIsUnconfirmed` (offline, timeout, HTTP 500, transport), `liveFlowExpiresJarsWithoutIdentityAndKeepsTheirCookies` (real `SessionRefreshFlow` behind a `CapturedForum` that answers nothing: no `md_user`, lapsed, `deleted`; nothing sent), `launchCheckConfirmsReportsAndNeverLogsOut` (valid persisted; stale, unknown page and offline kept logged in, store untouched; no identity expired), `recheckRetriesOnlyUnconfirmedSessionsAfterTheInterval`, `recheckDuringTheLaunchCheckSendsNothingMore`, `recheckWhileTheLaunchCheckWaitsOnAnotherAccountSendsNothing`, `secondRecheckWhileOneRunsSendsNothing`, `loginDuringARecheckWinsOverItsResult`, `loginSavedWhileACheckWritesBackWinsOverItsCookies`.
`CapturedSessionCheckTests.swift` drives the same model through the **real** `SessionRefreshFlow`, built on its internal probe seam (`@testable import HFRClient`: Xcode builds the package testable in Debug, as the engine tests use it; no new engine API). Each probe is a `CapturedProbe` whose cookie jar is a real `HFRSession` and whose answer is a committed LOT-001 capture read in place from `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures` (as `LiveTopicPageSourceTests`), or a thrown `NetworkError`; nothing is sent: `capturedProfilePageConfirmsTheSessionAndPersistsItsRefresh` (`R55-p1`: `valid`, its `md_passs` and token persisted), `staleCookieStandInsKeepTheSessionLoggedIn` (`W00`, `R55-p1` setting `md_user=deleted`: stale cookies are not captured, #281), `unknownPagesKeepTheSessionLoggedIn` (`R12`, `W17c`, `R01`), `networkErrorsAreReportedAndKeepTheSession` (offline, timeout, `R55-p1` as HTTP 500), `recheckAfterANetworkErrorConfirmsOnTheCapturedProfilePage`. Run by the Fable review of #309 (`ext/bybifok-opus-1`, iPhone 18 Pro, iOS 27.0): each fails with `ForumSessionCheck.check` reduced to the former local rule (no request, `restored`); the first also without the `valid` write-back, the stale and unknown-page ones with `unconfirmed` mapped to `expired`, the network one with failures mapped to `unconfirmed` or `expired`, the re-check one without `checkFailed` in the re-checked statuses.
Shown to fail without the change (mutations run locally): `unconfirmed` mapped to `expired`, network errors mapped to `expired`, no `.cancelled` case, no re-check interval, `valid` re-checked, `checking` re-checked, no same-status guard after a check, no running-re-check guard, no running-restore guard (fails `recheckWhileTheLaunchCheckWaitsOnAnotherAccountSendsNothing`: a third call for `user1`; run by the Fable review of #309), no login-save count in `persistSession` (fails `loginSavedWhileACheckWritesBackWinsOverItsCookies`: the store ends with `refreshed-hash`; run by the Fable review of #309).

**Pending capture:** none new (LOT-044's #281, #282, #283 stay open).

## Edge cases

- Login succeeds but the Keychain write fails: `store(.keychain)` is shown; a new account is not added (its session is discarded); for a re-login the session in memory is already renewed (LOT-043 installed it) and keeps working for this run, the stored cookies stay the old ones.
- Two `restore()` calls (the root `.task` restarts): one read, one check per account.
- A login finishes while restore is checking sessions: the check result is applied only if the account still has the same session and is still `checking`.
- A re-login is saved while a `valid` check writes its session back: the re-login renews the same `HFRSession`, so the session identity cannot tell them apart and the write-back may hold a jar read before the login. `persistSession` notes the account's count of saved logins before reading the jar and writes nothing if a login was saved since (CodeRabbit, #309): the store keeps the login.
- `md_user` is URL-encoded by HFR (HFR-PROTOCOL §5): the account key is `LoginResult.userKey` and the re-login sheet shows the display name, never the key.
- A login is cancelled (sheet dismissed): nothing changes and no error is shown. Cancelled after HFR accepted it: a new account is not added; a re-login is still saved, because its session is already renewed in memory and the store must match it.
- The Keychain in an unsigned simulator build (CI): the store may answer `unavailable`; tests use `InMemoryCredentialStore`.
- An account removed while its re-login runs is not brought back: after the login, the account must still have the same session, else `unknownAccount` and nothing is saved.
- "Réessayer" while a restore runs waits for it (and is disabled meanwhile): two restores would check every session twice.
- A store write after a `valid` check fails (Keychain locked): the store problem is shown with "Réessayer"; the session in memory keeps working, and the retry writes every session already confirmed `valid` again.
- A `valid` check whose jar names another pseudo (`AccountBook.add` refuses it): nothing is written and no store problem is shown, since the store is intact; the account's session is rebuilt from its stored cookies and token and its status goes back to `restored`, so the screens never use a jar of another identity. A `valid` jar holding `md_user=deleted` is not written either (`persistSession` skips a logged-out jar). The LOT-044 flow returns `valid` only when the identity is unchanged, so both are defensive. A failed avatar write stays silent (decoration).
- Until the store is read, the toolbar shows a disabled "Comptes" button, neither "Se connecter" nor a list.
- Store reads and writes are synchronous Keychain round-trips on the main actor (`select`, `remove`, `logIn`, `restore`): a few milliseconds each, acceptable for this lot; moving them off the main actor is a follow-up if measurement shows a hitch (LESSONS 10).

## Fixtures

None: no HFR page is read by the app code. Tests use fake cookie values, tokens and pseudos (`user1`, `fake-pass`).

## Tests

`App/SwiftHFRTests/Accounts/` (Swift Testing, hosted by the app):
- `AccountsModelRestoreTests`: one session per stored account with its cookies and token; no account = logged out; missing / expired / `deleted` identity is `expired` and the stored cookies are kept; a `valid` check persists the refreshed cookies and token; other outcomes write nothing; restore runs once under concurrent calls; a retry during a running restore checks each session once; a `valid` check of a jar that lost its identity writes nothing; a failed write after a `valid` check is reported and the retry saves it; a `valid` jar naming another pseudo is not a store problem and the stored session is put back; corrupted store reported and erased only on request; newer store reported and never overwritten.
- `AccountsModelLoginTests`: new account stored under its `userKey`, current, `valid`; every `LoginError` leaves store, session object and cookies unchanged; re-login uses the account's own session and `expectedUserKey`, keeps the current account; re-login of an unknown account sends nothing; a known account typed again replaces its session only once stored (Keychain failure first); avatar fetched, decoded and stored, none without a URL, non-image bytes never stored; a new account cancelled after the login is not added; an account removed while its re-login runs is not brought back; a login that finishes during the launch check wins over the check's result.
- `AccountsModelSessionGenerationTests`: the generation changes on restore, account switch, removal of the current account, logout and the current account added again; it does not change on selecting the current account or on a re-login (same session object).
- `AccountSwitchTests`: the environment uses the current account's session and name, the new session after a switch and after the current account is added again, and one cookie-less logged-out session after the last account is removed.
- `AccountsModelSelectionTests`: select; remove promotes the first remaining account; removing the last logs out; unknown accounts and store failures are reported and change nothing.
- `LoginModelTests`: submit rule; refusal message, fields kept; success clears the password; cancellation shows nothing; re-login locks the pseudo.
- `AccountMessagesTests`, `AnonymousAvatarLoaderTests` (http, other port, look-alike host, other hosts refused without a request; no redirect followed; 3xx / 404 / empty / non-image or missing content type / oversized / offline give no avatar).

Shown to fail without the change (mutations run locally, each makes its tests fail): dropping the single-restore guard, the persist-after-`valid`, the fresh session for a new account, the `expectedUserKey` on re-login, the port check and the no-redirect policy of the avatar loader; review round 1: the post-login removal guard, the cancellation check before saving a new account, the retry-waits-for-restore rule, the reported persist failure, the avatar decode and content-type checks, the still-`checking` guard after a check, and the logged-out-jar guard of `persistSession`; round 2: the silent `pseudoMismatch` / `invalidPseudo` case of `persistSession`, the re-persist on retry, and the session-identity key of `currentSessionGeneration`.

## Pending capture

None new. The login's pending captures (flood answer, case and encoding of `md_user`, page 5 without a session) and the session check's (LOT-044) stay in the capture backlog; the screen shows `unrecognizedResponse` and `accountMismatch` with their own texts meanwhile.

## Intentional differences from legacy

- A wrong password never logs the current account out (LOT-043), and a failed save never shows an account the store does not hold.
- Re-login of an expired account keeps the account and checks the identity; legacy only offered "add" and "logout".
- "Retirer" instead of "Déconnexion": the action removes the account from the app; it never was a server logout.
- Unknown answers and network failures have their own texts (legacy showed `localizedDescription` or "Pseudo ou mot de passe incorrect.").
- The avatar comes from the forum image host only, without cookies, with a size limit (legacy downloaded whatever URL the regex found, with `try?`).
- Account deletion mail (Q-10) is out of scope.

## Learnings

- `HFRSession` rounds cookie expiries to the second on the way back (LOT-042): compare a jar with what it held before, not with the `StoredCookie`s that seeded it.
- An app-side protocol in front of an engine flow whose test seam is `internal` (`LoginFlow`'s jar) keeps view models testable without widening the engine API.
