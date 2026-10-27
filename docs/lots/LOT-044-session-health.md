# LOT-044 — Session health & refresh

- **Module:** HFRClient
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** none (claimed by the orchestrator in `docs/LOTS.md`; old francoisgn/ios-app_SwiftHFR#73)
- **Depends on:** LOT-042 (`HFRSession`: jar, `userKey(now:)`, `mergeCookies`, `updateHashCheck`), LOT-013 (`StoredCookie`); uses LOT-025 (`ProfileEditPageParser`), LOT-037 (`HopResponseParser`), LOT-041 (`HFREndpoint.editProfile`)

## Legacy sources

Legacy app: `master` of ezzz/HFRnow @ `21173e7` (same lines as francoisgn/hfrnow @ `2440d79`). Audit [A](../audit/A-network-sessions.md) §4.5 and lot NET-07.

| Legacy | Replaced by |
|---|---|
| `Classes/HFRplusAppDelegate.m:150`: `updateAllAccounts` at every launch | the app calls `SessionRefreshFlow.refresh` per account (scheduling stays in the app) |
| `Classes/MultisManager.m:280-287`: GET `/user/editprofil.php?config=hfr.inc&page=1` per account, with its stored cookies, no shared jar | same GET (`HFREndpoint.editProfile(page: .cookieRefresh)`), in a probe jar seeded with the session's cookies |
| `MultisManager.m:290-293`, `228-240` (`updateCookies`): the answer's cookies **replace** the stored cookie array of the account whose `md_user` they carry (non-`deleted`); keychain rewritten even when nothing matched; no failure callback; the page itself is never read | cookies HFR set or removed are **merged** into the session, only when the page proves the session works; failures are typed |
| `MultisManager.m:55, 231, 248, 261`: `md_user` = identity, `deleted` = logged out | `HFRSession.userKey(now:)` (LOT-042) |
| `Classes/ObjCFavoritesLoaderWorker.m:83-95`: "Authentification requise" on a favourites page without `body#id` (the only legacy expiry signal) | not a verdict here: LOT-023/024 report such pages, and callers confirm with this flow |

## Behaviour

`SessionRefreshFlow().refresh(_ session: HFRSession, now:) async throws(NetworkError) -> SessionHealth`, in `Packages/HFRKit/Sources/HFRClient/Session/`.

1. Read the session's identity (`userKey`), cookies and `hash_check` in one actor turn. No usable `md_user` (absent, past its expiry, or `deleted`) → `expired(.noIdentityCookie)`, nothing sent.
2. Create a **probe** `HFRSession` seeded with those cookies (internal `SessionJar` protocol, shared with LOT-043's login) and GET profile page 1 through it without following redirects (`send`: 4xx/5xx throw).
3. The answer confirms the session only if all hold, else `unconfirmed(.unrecognizedPage)`:
   - 2xx, served at exactly the requested page-1 URL on `https://forum.hardware.fr` (port absent or 443, LESSONS 37); a 3xx (to page 5, to a login page) or a page from another origin is something else;
   - no `.hop` block (`HopResponseParser` finds none): `W17c` shows a `.hop` refusal holding a non-empty `hash_check` in its replay form although the POST carried no cookies;
   - `ProfileEditPageParser` finds a non-empty `hash_check` (`R55-p1`). HFR prints an empty token to a logged-out visitor (`R01`, `W00`, `R40b`), and a GET carries no token to echo.
4. The probe's `md_user` after the answer must be the same usable value, else `unconfirmed(.identityNotConfirmed)` (removed, changed or `deleted`).
5. Diff the probe's cookies with the seed by `jarKey`. In one actor turn on the session (`adoptRefresh`): cancellation check (`NetworkError.cancelled`), identity still the seed's (else `unconfirmed(.sessionChanged)`), then for each changed key write the probe's cookies, or delete the key if HFR removed it, **only when the session still holds the seed's cookies for that key**; same compare-and-set for `hash_check`. Return `valid`.

Whatever is returned other than `valid`, and whenever `refresh` throws, the session's cookies and `hash_check` are unchanged. The flow never clears a session: `expired` describes the jar, it does not empty it; the app decides (prompt a new login, LOT-043).

**When to refresh** (app policy, not engine): at launch for each stored account, as legacy did; and when a flow meets a logged-out-looking answer (LOT-023 `.notAuthenticated`, LOT-024 `.hop` notice, LOT-037 `.loggedOut`), to confirm it before telling the user. The app persists `session.cookies(now:)` and `hashCheck` after a `valid` refresh (LOT-065).

## Edge cases

- A request of the account (a write setting `md_data`, a re-login of the same account) lands while the probe is in flight: its cookies and token win; only keys nobody touched get the probe's values.
- The session is logged out or switched to another identity meanwhile: nothing is written (`sessionChanged`), so a refresh never revives an identity.
- HFR removes a cookie on a valid answer (an expired `Set-Cookie`): it is removed from the session too, as a direct request would have done.
- One key set for both `.hardware.fr` and `hardware.fr`: the session keeps one (LOT-042 "one key, one value").
- The answer to stale cookies is not captured (below): today it ends as `unrecognizedPage` or `identityNotConfirmed`, never as `expired`.

## Fixtures

Shared corpus only, no new file, read in place (`Tests/HFRClientTests/Support/Capture.swift`, shared with LOT-043): `R55-p1` (page 1 logged in; its meta: GET, 200, sets `md_user` and `md_passs`), and as stand-ins for a page that is not the logged-in profile page: `W00`, `R01`, `R40b` (logged-out GET pages, empty token), `R12` (`.hop` notice, no token), `W17c` (`.hop` refusal echoing a token). None of them is offered as the captured answer of page 1 to stale cookies. Cookie values in tests are fake.

## Tests

`SessionRefreshFlowTests` (scripted probe on the captures, real `HFRSession` as the account session):
`captureMetaShapesTheScript`, `validRefreshMergesWhatHFRSetAndTheToken`, `probeStartsFromTheSessionCookies`, `cookieRemovedByHFRIsRemovedOnAValidRefresh`, `concurrentChangesWinOverTheProbeCopy`, `noUsableIdentityIsExpiredWithoutSending` (absent, expired, `deleted`), `pagesWithoutTheAccountTokenAreUnconfirmed` (5 pages), `profilePageServedElsewhereOrRedirectedIsUnconfirmed`, `profilePageFromAnotherOriginIsUnconfirmed` (other host, look-alike host, `http`, port 8443), `identityNotKeptByTheAnswerIsUnconfirmed` (`deleted`, other user, removed), `sessionLoggedOutDuringTheRefreshIsNotRevived`, `transportFailuresThrowAndChangeNothing` (timeout, offline, HTTP 500), `cancellationChangesNothing`.

Shown to fail without the change (mutations run locally, each fails its tests): dropping the `.hop` check, the URL path check, the exact-URL check with `doNotFollow`, the origin check (scheme, host, port), the identity check after the answer, the identity check at adoption, the cookie or token compare-and-set, the cancellation check, the no-identity shortcut, and replacing the jar with the answer's cookies (legacy `updateCookies`).

## Pending capture

Added to the capture backlog in `docs/LOTS.md`. None blocks the lot; until captured, each case is `unconfirmed` and the session is kept.
- **Profile page 1 with stale or invalidated cookies** (an old `md_passs`, or cookies of a session closed by `unlog.php`): status, redirect, body and `Set-Cookie`. This is the expiry rule NET-07 asks for; once captured it becomes a `SessionExpiry` case.
- **`md_user=deleted` from the server**: legacy code reads it as logged out, but no capture shows HFR sending it. Today it is `identityNotConfirmed`.
- **The two `md_user` / `md_passs` `Set-Cookie` of every logged-in page** (`R55-p1`, `R55-p3`, `R55-p5`, `R03` metas list each name twice): their domains, paths, expiries, and whether one is a removal. The metas record names only. If one of the pair were `deleted` for another domain, every refresh would end `identityNotConfirmed` (safe, but never `valid`); LOT-043's login reads the same pages.

## Intentional differences from legacy

1. Merge, not replace: cookies the answer does not mention are kept (legacy kept only the answer's cookies, audit A §4.5 bug a).
2. The page is read: the session changes only on the account's own profile page with a token (legacy stored the cookies of any answer).
3. Nothing is written when nothing is confirmed (legacy rewrote the keychain even when no account matched, bug b); failures are typed (bug c).
4. Compare-and-set against concurrent requests (legacy had one global jar and no concurrency).
5. `hash_check` is refreshed from page 1 (legacy read it only at login, page 5).
6. No migration from the shared jar (`MultisManager.m:244-253`) and no pseudo repair (`:254-277`): legacy data import is LOT-067.

## Learnings

- A `.hop` refusal can hold a non-empty `hash_check` in its replay form although the POST carried no cookies (`W17c`): "non-empty token = logged in" holds only for a GET answer without `.hop`.
