# LOT-044 — Session health & refresh

- **Module:** HFRClient
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** [#70](https://github.com/ezzz/HFRnow/issues/70) (old francoisgn/ios-app_SwiftHFR#73)
- **Depends on:** LOT-042 (`HFRSession`: jar, `userKey(now:)`, `mergeCookies`, `updateHashCheck`), LOT-013 (`StoredCookie`); uses LOT-025 (`ProfileEditPageParser`), LOT-037 (`HopResponseParser`), LOT-041 (`HFREndpoint.editProfile`); `StaleSessionNoticeParser` (#383)

## Legacy sources

Legacy app: `master` of ezzz/HFRnow @ `21173e7` (same lines as ezzz/HFRnow @ `2440d79`). Audit [A](../audit/A-network-sessions.md) §4.5 and lot NET-07.

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
2. Create a **probe** `HFRSession` seeded with those cookies (internal `SessionJar` protocol, shared with LOT-043's login) and GET profile page 1 through it without following redirects (`send`: 4xx/5xx throw). Without a test factory the probe is `session.probe(cookies:now:)`, which keeps the refreshed session's host policy, so a test session restricted to the loopback host never yields a probe that may reach the forum ([#320](https://github.com/ezzz/HFRnow/issues/320), `SessionRefreshProbeTests`, `HFRSessionProbeTests`).
3. HFR's stale-session page (#383, `R70c`): a 2xx served at exactly the requested page-1 URL whose body `StaleSessionNoticeParser` recognizes (a lone `.hop` "Identifiants invalides !", no link or input, one refresh meta to exactly `https://forum.hardware.fr/unlog.php?config=hfr.inc`; matched on the sentence and the target, never the size). In one actor turn on the session (`confirmStaleSession`): cancellation check, then `expired(.credentialsRefused)` only while the session still has the seed's identity, login generation and `md_user`/`md_passs` cookies, else `unconfirmed(.sessionChanged)`. Nothing is written either way, and the refresh target is never followed (`unlog.php` without `codehex` does nothing, `R72a`). The cookie-less answer (`R71b`, "Mot de passe incorrect !" refreshing to `login.php`) is not this page and falls through to step 4.
4. The answer confirms the session only if all hold, else `unconfirmed(.unrecognizedPage)`:
   - 2xx, served at exactly the requested page-1 URL on `https://forum.hardware.fr` (port absent or 443, LESSONS 37); a 3xx (to page 5, to a login page) or a page from another origin is something else;
   - no `.hop` block (`HopResponseParser` finds none): `W17c` shows a `.hop` refusal holding a non-empty `hash_check` in its replay form although the POST carried no cookies;
   - `ProfileEditPageParser` finds a non-empty `hash_check` (`R55-p1`). HFR prints an empty token to a logged-out visitor (`R01`, `W00`, `R40b`), and a GET carries no token to echo.
5. The probe's `md_user` after the answer must be the same usable value, else `unconfirmed(.identityNotConfirmed)` (removed, changed or `deleted`). The doubled pair of every logged-in answer (`R74`: the value for `.hardware.fr`, then `deleted` for `.forum.hardware.fr` expired in 1970) keeps it: the expired copy of another domain removes nothing the jar holds.
6. Diff the probe's cookies with the seed by `jarKey`. In one actor turn on the session (`adoptRefresh`): cancellation check (`NetworkError.cancelled`), identity and login generation still the seed's (else `unconfirmed(.sessionChanged)`, nothing written), then for each changed key write the probe's cookies, or delete the key if HFR removed it, **only when the session still holds the seed's cookies for that key**; same compare-and-set for `hash_check`. Return `valid`.

For every non-`valid` result and every thrown error, the flow does not write the session's cookies or `hash_check` (concurrent operations may still change them; `sessionChanged` reports one). The flow never clears a session: `expired` describes the jar, it does not empty it; the app decides (prompt a new login, LOT-043).

**When to refresh** (app policy, not engine): at launch for each stored account, as legacy did; and when a flow meets a logged-out-looking answer (LOT-023 `.notAuthenticated`, LOT-024 `.hop` notice, LOT-037 `.loggedOut`), to confirm it before telling the user. The app persists `session.cookies(now:)` and `hashCheck` after a `valid` refresh (LOT-065).

## Edge cases

- A request of the account (a write setting `md_data`) lands while the probe is in flight: its cookies and token win; only keys nobody touched get the probe's values.
- The session is logged out or switched to another identity meanwhile: nothing is written (`sessionChanged`), so a refresh never revives an identity.
- A login of the **same** account is adopted meanwhile, even one that installs the seed's own token: identity and token cannot tell it, so the seed carries `HFRSession.loginGeneration`, which `adoptLogin` advances; a moved generation writes nothing (`sessionChanged`) and the login's cookies and token stay. Without it, the probe's token (read with the old cookies) would be paired with the re-login's cookies and the next POST refused (`W17b`) ([#340](https://github.com/ezzz/HFRnow/issues/340)).
- HFR removes a cookie on a valid answer (an expired `Set-Cookie`): it is removed from the session too, as a direct request would have done.
- One key set for both `.hardware.fr` and `hardware.fr`: the session keeps one (LOT-042 "one key, one value").
- A refused `md_passs` (`R70c`) is `expired(.credentialsRefused)`; the same page served elsewhere (another URL, a 3xx, another origin) stays `unrecognizedPage`. A login, a logout or a new `md_passs` that lands while the request runs makes it `sessionChanged`: the page described the cookies sent, not the session now. Other cookies (a quote selection) changing meanwhile do not matter.

## Fixtures

Shared corpus only, no new file, read in place (`Tests/HFRClientTests/Support/Capture.swift`, shared with LOT-043): `R55-p1` (page 1 logged in; its meta: GET, 200, sets `md_user` and `md_passs`), and as stand-ins for a page that is not the logged-in profile page: `W00`, `R01`, `R40b` (logged-out GET pages, empty token), `R12` (`.hop` notice, no token), `W17c` (`.hop` refusal echoing a token). None of them is offered as the captured answer of page 1 to stale cookies; that answer is `R70c` (#383), with `R71b` (page 1 without cookies) and the `R74` meta (doubled `Set-Cookie`, attributes in its note). Cookie values in tests are fake.

## Tests

`StaleSessionRefreshTests` (#383): `staleCaptureMetaShapesTheScript`, `staleSessionPageIsExpiredAndChangesNothing`, `cookielessProfilePageStaysUnconfirmed` (`R71b`), `stalePageElsewhereIsUnconfirmed` (home, page 5, look-alike host, `http`, 302), `loginAdoptedDuringTheStaleAnswerIsNotReportedExpired` (new and same `md_passs`), `passwordCookieChangedDuringTheStaleAnswerIsNotReportedExpired`, `otherCookiesChangedDuringTheStaleAnswerStillExpire`, `logoutDuringTheStaleAnswerIsSessionChanged`, `cancellationDuringTheStaleAnswerThrows`, `doubledSetCookieOfALoggedInAnswerKeepsTheAccountLoggedIn` (`R74`). `StaleSessionNoticeParserTests` (HFRParsing): `R70a`–`R70d` recognized, no other capture of the corpus, `R71a`/`R71b` not, and 14 one-part variants of `R70c` (sentence, link, input, second `.hop`, target path, query, fragment, host, port, missing or second refresh) not.

`SessionRefreshFlowTests` (scripted probe on the captures, real `HFRSession` as the account session):
`captureMetaShapesTheScript`, `validRefreshMergesWhatHFRSetAndTheToken`, `probeStartsFromTheSessionCookies`, `cookieRemovedByHFRIsRemovedOnAValidRefresh`, `concurrentChangesWinOverTheProbeCopy`, `sameAccountReloginWithTheSameTokenDuringTheRefreshWins` (#340), `noUsableIdentityIsExpiredWithoutSending` (absent, expired, `deleted`), `pagesWithoutTheAccountTokenAreUnconfirmed` (5 pages), `profilePageServedElsewhereOrRedirectedIsUnconfirmed`, `profilePageFromAnotherOriginIsUnconfirmed` (other host, look-alike host, `http`, port 8443), `identityNotKeptByTheAnswerIsUnconfirmed` (`deleted`, other user, removed), `sessionLoggedOutDuringTheRefreshIsNotRevived`, `transportFailuresThrowAndChangeNothing` (timeout, offline, HTTP 500), `cancellationChangesNothing`.

Shown to fail without the change (mutations run locally, each fails its tests): dropping the `.hop` check, the URL path check, the exact-URL check with `doNotFollow`, the origin check (scheme, host, port), the identity check after the answer, the identity check at adoption, the login-generation check at adoption (#340), the cookie or token compare-and-set, the cancellation check, the no-identity shortcut, and replacing the jar with the answer's cookies (legacy `updateCookies`). #383: dropping the stale-page branch, its URL or status check, the cancellation, login-generation or credential-cookie check of `confirmStaleSession`, and each part of the parser's rule (sentence, block contents, single `.hop`, single refresh, target host, port, query, fragment).

## Pending capture

Captured since (#168, #173, #281, Run 7), handled by #383:
- **Profile page 1 with a refused `md_passs`** (`R70c`, [#281](https://github.com/ezzz/HFRnow/issues/281)): the stale-session page, now `expired(.credentialsRefused)` (step 3).
- **The two `md_user` / `md_passs` `Set-Cookie` of every logged-in page** (`R74` note, [#282](https://github.com/ezzz/HFRnow/issues/282)): the value for `.hardware.fr`, then `deleted` for `.forum.hardware.fr` expired in 1970. A removal of another domain, not a logout: the refresh stays `valid` (step 5).

Still pending; until captured, each case is `unconfirmed` and the session is kept:
- **Cookies invalidated by HFR itself** (a password changed elsewhere, a session closed by `unlog.php` with its `codehex`): likely the same page as `R70c` (HFR-PROTOCOL §6c LOT-044), not captured. Recognized as expired only if HFR serves that same page.
- **`md_user=deleted` set for the forum's own cookie domain** ([#283](https://github.com/ezzz/HFRnow/issues/283)): legacy code reads it as logged out; `R74` shows HFR sending it only for `.forum.hardware.fr`, expired. Another shape would be `identityNotConfirmed`.

## Intentional differences from legacy

1. Merge, not replace: cookies the answer does not mention are kept (legacy kept only the answer's cookies, audit A §4.5 bug a).
2. The page is read: the session changes only on the account's own profile page with a token (legacy stored the cookies of any answer).
3. Nothing is written when nothing is confirmed (legacy rewrote the keychain even when no account matched, bug b); failures are typed (bug c).
4. Compare-and-set against concurrent requests (legacy had one global jar and no concurrency).
5. `hash_check` is refreshed from page 1 (legacy read it only at login, page 5).
6. No migration from the shared jar (`MultisManager.m:244-253`) and no pseudo repair (`:254-277`): legacy data import is LOT-067.
7. A refused `md_passs` is reported (`expired(.credentialsRefused)`, #383). Legacy's answer handler read only the `md_user` cookies of the answer (`MultisManager.m:228-240`): the stale page sets none (`R70c` meta), so no account matched, nothing changed and the account stayed shown as logged in.

## Learnings

- A `.hop` refusal can hold a non-empty `hash_check` in its replay form although the POST carried no cookies (`W17c`): a non-empty token is evidence of a logged-in session only on the expected profile-page GET, after its URL and `.hop` checks.
- #383: a page that proves expiry describes the cookies the request carried; report it only after checking, in one actor turn, that the session still holds them (identity, login generation, credential cookies).
