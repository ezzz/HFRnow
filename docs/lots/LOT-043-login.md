# LOT-043 — Login (validate before replacing cookies)

- **Module:** HFRClient (plus the login request builder in HFRNetwork)
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** none (claimed by the orchestrator in `docs/LOTS.md`; old francoisgn/ios-app_SwiftHFR#72)
- **Depends on:** LOT-042 (`HFRSession`, `replaceCookies(with:now:)`, `updateHashCheck(_:)`, `userKey(now:)`), LOT-025 (`ProfileEditPageParser`)

## Legacy sources

Legacy app: `master` of ezzz/HFRnow @ `21173e7` (same lines as francoisgn/hfrnow @ `2440d79`). Audit [A](../audit/A-network-sessions.md) §4.2 and lot NET-04.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/LoginService.swift:49, 131-134`: every cookie of the shared jar deleted **before** the credentials are posted | the attempt runs in a fresh jar; the account session is changed only after validation |
| `LoginService.swift:51-68`: POST `/login_validation.php?config=hfr.inc`, fields `pseudo, password, action=send, login=Se connecter` | `HFREndpoint.login(pseudo:password:)` |
| `LoginService.swift:70-74`: success ⇔ body contains `login_redirection.php`, else `invalidCredentials`; HTTP status ignored | `LoginResponse.classify(_:)`; the transport's `send` maps 4xx/5xx to `NetworkError.httpStatus` |
| `LoginService.swift:76-85`: answer cookies copied into the shared jar | the attempt's own `HFRSession` stores them |
| `LoginService.swift:87-113`: GET `editprofil.php?config=hfr.inc&page=5`, `hash_check` regex (`missingHash`), avatar regex, avatar downloaded with `try?` | `HFREndpoint.editProfile(page: .hashAndAvatar)` + `ProfileEditPageParser` (LOT-025); the avatar URL is returned, not downloaded |
| `LoginService.swift:115-120`: jar cookies whose domain contains `hardware.fr`; a non-`deleted` `md_user` required (`missingPseudoCookie`) | `HFRSession.userKey(now:)`, `HFRSession.cookies(now:)` (LOT-042) |
| `HFRswift/Swift/AccountSessionService.swift:61-67`: pseudo trimmed, empty refused, then login with the trimmed pseudo | same, in `LoginFlow.login` |
| `Classes/MultisManager.m:73-77`: an account is identified by its `md_user` value, compared exactly | `expectedUserKey` compared exactly |

## Behaviour

`LoginFlow.login(pseudo:password:into:expectedUserKey:now:) async throws(LoginError) -> LoginResult`, in `Packages/HFRKit/Sources/HFRClient/Login/`.

1. Trim the pseudo (whitespace and newlines); an empty pseudo or an empty password throws `missingCredentials` and sends nothing. The password is sent as typed.
2. Create a **new, empty** `HFRSession` for this attempt (the jar). Nothing of the target session (`into:`) is read or sent.
3. POST the credentials through the jar (`HFREndpoint.login`, body in the legacy order, the order of `W01`/`W01b`/`W03`). Classify the decoded answer:
   - contains `login_redirection.php` → accepted (legacy rule; `W03`, `W01b`);
   - else contains "Votre mot de passe ou nom d'utilisateur n'est pas valide" → `invalidCredentials` (`W01`);
   - else → `unrecognizedResponse`.
4. The jar must hold a usable `md_user` (`HFRSession.userKey`: present, not empty, not expired, not `deleted`), else `missingIdentityCookie`. When `expectedUserKey` is given and differs from it → `accountMismatch` (re-login of an existing account must not install another account's cookies in its session).
5. GET the profile page 5 through the jar (so with the new cookies) and parse it with `ProfileEditPageParser`. Any parse failure (no `hash_check`, or only empty ones as on logged-out pages) → `missingHashCheck`: the new cookies do not give a working session.
6. Read the jar's cookies **after** page 5, which sets `md_user` and `md_passs` again (`R55-p5` meta).
7. If the task was cancelled → `network(.cancelled)`. Otherwise install the result in the target session in one actor turn (`adoptLogin`: `replaceCookies(with:)` then `updateHashCheck(_:)`), so no request of that session sees the new cookies with the old token.
8. Return `LoginResult(userKey: md_user value, displayName: trimmed pseudo, avatarURL:)`. Cookies and token stay in the session; the app persists them from `HFRSession.cookies(now:)` and `hashCheck` (LOT-065, LOT-081).

Errors (`LoginError`) carry no pseudo, password or page text. Transport failures are `network(NetworkError)` (status 4xx/5xx, timeout, offline, cancelled). **Whenever `login` throws, the target session's cookies and `hash_check` are unchanged.**

`HFREndpoint.login(pseudo:password:)` (HFRNetwork) builds the POST only; it neither trims nor refuses values.

## Edge cases

- Wrong password: one request, no profile page, session untouched.
- Success page without `md_user` (cookies refused, or `md_user=deleted`): refused before page 5.
- Credentials of another account while re-logging an account in: `accountMismatch`, before page 5.
- Network failure, HTTP error or cancellation at either step: session untouched.
- Re-login replaces the whole jar: cookies the session held before (an expired identity, `md_data`, multi-quote `quotes*` selections) are dropped, as legacy's wipe did.
- Two logins into the same session at once: each runs in its own jar; the last one to finish is installed.
- The avatar URL comes from a page of the forum but points to `forum-images.hardware.fr`: the app fetches it with `AnonymousTransport` (HFR-PROTOCOL §7 E26), never with the account session.

## Fixtures

Shared corpus only, no new file (read from `HFRParsingTests/Fixtures/captures` by path, `Tests/HFRClientTests/Support/Capture.swift`):
`W03` (success, user2), `W01b` (success, user1), `W01` (refusal), `W00` (login form, used as "any other page" and as a page whose `hash_check` is empty), `R55-p5` (page 5 without avatar), `R55-p5u1` (page 5 with avatar). The metas of `W01`, `W01b`, `W03` and `R55-p5` give the status, URL, request body and set cookie names. Cookie values in tests are fake.

## Tests

- `LoginResponseTests` (differential): on `W00`, `W01`, `W01b`, `W03`, the port accepts exactly what the legacy rule (`LoginService.swift:72`) accepts, and splits legacy refusals into `refused` (`W01`) and `unrecognized` (`W00`). Capture metas: POST answered 200 either way, `md_user`, `md_passs`, `md_id` set only on success, legacy field order; `R55-p5` sets `md_user` and `md_passs`; `HFREndpoint.login` reproduces `W03`'s anonymized request body.
- `LoginFlowTests`: success installs the jar's cookies (page 5's refresh included) and the page-5 token, drops the old ones, sends the trimmed pseudo; avatar on `R55-p5u1`; every failure path (refusal, unknown page, no identity, `deleted`, account mismatch, page 5 without token, network failure at each step, HTTP 500, cancellation, empty credentials) leaves the target session exactly as it was.
- `HFREndpointLoginTests` (HFRNetwork): URL, method, content type, field order, encoding of reserved and non-ASCII characters.

Shown to fail without the change: clearing the session before validating (legacy order), dropping the cancellation check, dropping the account check, reading the cookies before page 5, not trimming, and calling unknown pages refusals each make the matching tests fail.

## Pending capture

- **Login flood / lockout answer** (several wrong passwords): its text is unknown (HFR-PROTOCOL §7 "Login"); it is reported as `unrecognizedResponse`, not as a refusal.
- **Pseudo typed in another case** than the account's: whether HFR's `md_user` keeps the typed case or the account's is unknown; `expectedUserKey` is compared exactly (as legacy compared `md_user`), so a case variant would be refused as `accountMismatch`.
- **Profile page 5 requested without a working session**: not captured; the flow relies on the parser refusing a page without a non-empty `hash_check` (logged-out pages print it empty, `R01`, `W00`).

## Intentional differences from legacy

- The account session is never changed before the login is validated (legacy logged the current account out on a typo).
- Validation also requires the profile page to yield a token read **with the new cookies**; legacy read it too (`missingHash`) but checked `md_user` last.
- Unknown answers are `unrecognizedResponse`, not `invalidCredentials` (LESSONS 44: "refused" must stay distinguishable from "could not read").
- An empty password is refused locally (legacy sent it).
- HTTP 4xx/5xx are errors (legacy ignored the status).
- `expectedUserKey` refuses another account's credentials on re-login (legacy `addCompte` silently kept the old cookies of a duplicate and installed the new ones in the shared jar).
- The avatar is not downloaded here: the URL is returned for the app's image pipeline (anonymous transport, LOT-066 cache).
- The password is never stored, as in legacy.

## Learnings

- Profile page 5 sets `md_user` and `md_passs` again: read a jar after the last request of a flow, not after the login POST.
- A test that cancels its own task is reported as *cancelled*, not failed or passed, by Swift Testing: cancel a child `Task` instead.
