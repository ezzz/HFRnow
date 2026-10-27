# LOT-081 — Accounts and login screen

- **Module:** App (`App/SwiftHFR/Accounts/`)
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** none (claimed in `docs/LOTS.md` by #31; old francoisgn/ios-app_SwiftHFR#95)
- **Depends on:** LOT-080 (app target), LOT-043 (`LoginFlow`, `LoginError`, `LoginResult`), LOT-065 (`CredentialStore`, `AccountBook`, `KeychainCredentialStore`), LOT-042 (`HFRSession`, `AnonymousTransport`). Designed for LOT-044 (`SessionRefreshFlow`, not merged yet).

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

- **Mirror of the store.** `rows` (`AccountRow`: id = `Account.pseudo`, display name, main flag, avatar bytes, session status; no cookie, no token) is always what the credential store holds. An account whose store write failed is never shown.
- **Restore at launch** (`restore()`, from the root `.task`, once per launch; concurrent calls wait for the first): read the store, build one `HFRSession(cookies:hashCheck:)` per account (LOT-042), then check each session one after the other through `SessionChecking`:
  - `LocalSessionCheck` (today): no usable `md_user` (absent, expired, `deleted`, `HFRSession.isLoggedIn`) → `expired`; otherwise the session stays `restored` (not confirmed). Nothing is sent.
  - LOT-044 adapter (once #29 is merged): `SessionRefreshFlow.refresh` mapped to `valid` / `expired` / `unconfirmed` / `failed(NetworkError)`. A `valid` result is persisted (`persistSession(of:)`: cookies and token written back through `AccountBook.add`, which refuses a jar whose `md_user` names another pseudo). Any other result changes neither the session nor the store.
- **Store problems at launch** (`storeProblem`): `corrupted` → message + "Effacer les comptes enregistrés" (confirmation, then `removeAll()`; never done silently, LOT-065); `newerVersion` → "update the app", nothing is overwritten (the store itself refuses writes); `unavailable(status:)` (Keychain error with its `OSStatus`, or a storage error without one; device locked) → "Réessayer" (`retryRestore()`). A failed write of refreshed cookies (`persistSession`) is reported the same way.
- **Add an account** (`logIn(pseudo:password:for: .newAccount)`): `LoginFlow` into a **fresh** `HFRSession`. On success the account is saved as `Account(pseudo: LoginResult.userKey, displayName: LoginResult.displayName, cookies: session.cookies(), hashCheck: session.hashCheck)` with `makeMain: true` (legacy), and only then does the session become the account's session. Typing a known account again refreshes it in place (LOT-065 `add`); its previous session is replaced only once the store accepted the new cookies.
- **Log in again** (`.existing(id:displayName:)`, offered when a session is `expired`, and from the row's context menu): `LoginFlow` into the account's **own** session with `expectedUserKey = Account.pseudo`, so another account's credentials are refused (`accountMismatch`). The current account does not change.
- **Avatar**: when the login returns an avatar URL, it is fetched in the background by `AnonymousAvatarLoader` (cookie-less `AnonymousTransport`, HFR-PROTOCOL §7 E26) only from `https://forum-images.hardware.fr` on the default port (LESSONS 37; host from `R55-p5u1`, HFR-PROTOCOL §6), without following redirects, 200 with an `image/*` content type only, at most 256 KiB. The model decodes it once (bytes that are not an image are dropped), stores it with the account (LOT-065 keeps the avatar in the Keychain item, as legacy) and hands the decoded image to the rows, so no view decodes while rendering (LESSONS 49). A failure keeps the placeholder.
- **Select** (`select(_:)`) → `CredentialStore.setMain`; the main account is the current one and `currentSession` is its session (nil when logged out).
- **Remove** (`remove(_:)`, after a confirmation) → `CredentialStore.deleteAccount`, session dropped; the first remaining account becomes current (LOT-065). No server logout (legacy did none).
- **Typed errors** (`AccountActionError`: `login(LoginError)`, `store(CredentialStoreError)`, `unknownAccount`, `storeFailed` for a storage error that is not a `CredentialStoreError`) → `AccountMessages`: each `LoginError` case and each transport failure has its own text saying what to do; a cancelled login shows nothing. Texts never contain the password, a cookie or page content.

**`LoginModel`** (`@MainActor @Observable`): fields, `canSubmit` (pseudo not blank, password not empty, no attempt running), `submit()` (one task; the sheet's Cancel and disappearance cancel it, and `LoginFlow` then leaves the session as it was), `errorMessage`, `didSucceed` (the view dismisses). The password lives only in this model; it is cleared on success, kept after a failure so the user can fix the pseudo, and never stored or logged.

**Views** (thin, no side effect in `body`, LESSONS 48–49): `LoginView` (sheet; `Form` with `.username` / `.password` content types for AutoFill, keyboard "next" / "go"), `AccountsView` (list, swipe and context-menu actions, store-problem section), `AccountMenuButton` (toolbar menu: accounts, re-login of an expired current account, add, manage; "Se connecter" when there is no account). Dynamic Type: system text styles, avatar size `@ScaledMetric`. iPhone and iPad: sheets and `List` adapt; nothing is width-specific.

**Seams for the other app lots.** `AccountsModel.currentSession` is the session the forum screens use when logged in (nil = logged out); `current?.id` is the `md_user` value for the App Review rule (Q-7). Its **object identity changes** on select, remove, and when a known account is added again, so a screen must never keep the session it was built with. Wiring with LOT-082 (whichever of #32 / #33 merges second does it):
- `AppEnvironment` is rebuilt per account, keyed on `accounts.current?.id`: the navigation view takes `.id(accounts.current?.id)`, so its models (forum list, topic lists, selection) start over, and the data source is `LiveForumDataSource(fetcher: PageFetcher(session: accounts.currentSession ?? HFRSession()))` (an empty session when logged out, as LOT-082 does today). Chosen over a forwarding transport that resolves the current session per request: lists and flags already loaded belong to the previous account and must not stay on screen after a switch.
- The single Q-7 login state of LOT-082 (`ForumVisibility`, `accountName`) reads `accounts.current?.id`, not the session's `userKey()`.
- `AccountMenuButton` moves into the forum list's toolbar; `RootView` keeps no toolbar of its own.
- The navigation is shown only once `accounts.hasRestored`, so the first load is not made logged out and then redone.

## Edge cases

- Login succeeds but the Keychain write fails: `store(.keychain)` is shown; a new account is not added (its session is discarded); for a re-login the session in memory is already renewed (LOT-043 installed it) and keeps working for this run, the stored cookies stay the old ones.
- Two `restore()` calls (the root `.task` restarts): one read, one check per account.
- A login finishes while restore is checking sessions: the check result is applied only if the account still has the same session and is still `checking`.
- `md_user` is URL-encoded by HFR (HFR-PROTOCOL §5): the account key is `LoginResult.userKey` and the re-login sheet shows the display name, never the key.
- A login is cancelled (sheet dismissed): nothing changes and no error is shown. Cancelled after HFR accepted it: a new account is not added; a re-login is still saved, because its session is already renewed in memory and the store must match it.
- The Keychain in an unsigned simulator build (CI): the store may answer `unavailable`; tests use `InMemoryCredentialStore`.
- An account removed while its re-login runs is not brought back: after the login, the account must still have the same session, else `unknownAccount` and nothing is saved.
- "Réessayer" while a restore runs waits for it (and is disabled meanwhile): two restores would check every session twice.
- A store write after a `valid` check fails (Keychain locked): the store problem is shown with "Réessayer"; the session in memory keeps working. A failed avatar write stays silent (decoration).
- Until the store is read, the toolbar shows a disabled "Comptes" button, neither "Se connecter" nor a list.
- Store reads and writes are synchronous Keychain round-trips on the main actor (`select`, `remove`, `logIn`, `restore`): a few milliseconds each, acceptable for this lot; moving them off the main actor is a follow-up if measurement shows a hitch (LESSONS 10).

## Fixtures

None: no HFR page is read by the app code. Tests use fake cookie values, tokens and pseudos (`user1`, `fake-pass`).

## Tests

`App/SwiftHFRTests/Accounts/` (Swift Testing, hosted by the app):
- `AccountsModelRestoreTests`: one session per stored account with its cookies and token; no account = logged out; missing / expired / `deleted` identity is `expired` and the stored cookies are kept; a `valid` check persists the refreshed cookies and token; other outcomes write nothing; restore runs once under concurrent calls; a retry during a running restore checks each session once; a `valid` check of a jar that lost its identity writes nothing; a failed write after a `valid` check is reported; corrupted store reported and erased only on request; newer store reported and never overwritten.
- `AccountsModelLoginTests`: new account stored under its `userKey`, current, `valid`; every `LoginError` leaves store, session object and cookies unchanged; re-login uses the account's own session and `expectedUserKey`, keeps the current account; re-login of an unknown account sends nothing; a known account typed again replaces its session only once stored (Keychain failure first); avatar fetched, decoded and stored, none without a URL, non-image bytes never stored; a new account cancelled after the login is not added; an account removed while its re-login runs is not brought back; a login that finishes during the launch check wins over the check's result.
- `AccountsModelSelectionTests`: select; remove promotes the first remaining account; removing the last logs out; unknown accounts and store failures are reported and change nothing.
- `LoginModelTests`: submit rule; refusal message, fields kept; success clears the password; cancellation shows nothing; re-login locks the pseudo.
- `AccountMessagesTests`, `AnonymousAvatarLoaderTests` (http, other port, look-alike host, other hosts refused without a request; no redirect followed; 3xx / 404 / empty / non-image or missing content type / oversized / offline give no avatar).

Shown to fail without the change (mutations run locally, each makes its tests fail): dropping the single-restore guard, the persist-after-`valid`, the fresh session for a new account, the `expectedUserKey` on re-login, the port check and the no-redirect policy of the avatar loader; review round 1: the post-login removal guard, the cancellation check before saving a new account, the retry-waits-for-restore rule, the reported persist failure, the avatar decode and content-type checks, the still-`checking` guard after a check, and the logged-out-jar guard of `persistSession`.

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
