# LOT-116 — User profile screen

- **Module:** App
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#207](https://github.com/ezzz/HFRnow/issues/207)
- **Depends on:** LOT-027 (parser), LOT-045 (`PageFetcher.profile`), LOT-080 (app target)

Shows a member's public profile (`/hfr/profil-<id>.htm`, HFR-PROTOCOL R9) in a sheet: avatar, pseudo, status, figures, the page's
sections and fields, personal smileys and the page's link rows. Legacy parity, no FEAT.

## Legacy sources
`master` of ezzz/HFRnow at `2440d79` (line ranges re-checked there).

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/UserProfileView.swift:113-135` (`UserProfileService.fetchProfile`: `URLSession.shared`, so the shared cookies) | `LiveUserProfileSource` (the account's session, difference 1) |
| `HFRswift/Swift/UserProfileService.swift:23-48`, `UserProfileLoadingError.swift:10-30` @ `bb58131d` (`master`, #1349, 2026-11-26: the main account's cookies set on the request, no request without an account, `loginRequired`, 401/403 `accessDenied`) | `LiveUserProfileSource` login check, `ListLoadError.profileLoginRequired` / `.profileAccessDenied` (#1363) |
| `UserProfileService.swift:43-47`, `UserProfileLoadingError.swift:16-18, 30-32`, `MultisManager.m:228-262` @ `5c0f10db` (`master`, #1349, 2026-11-27: a 403 without `md_id` is `reloginRequired`, account cookies merged instead of replaced, login sent with `login.php`'s fields) | `LiveUserProfileSource` `md_id` check, `ListLoadError.profileReloginRequired`, `HFRSession.holdsMemberID`, `adoptSyncedCredentials` keeping `md_id` (#1420) |
| `UserProfileView.swift:464-490` (`UserProfileViewModel`: load, `isLoading`, `errorMessage`) | `UserProfileModel` over `ContentLoader` |
| `UserProfileView.swift:492-616` (`UserProfileView`: sheet, "Fermer", "Actualiser", loading and error views, `openLink` by the default-browser setting) | `UserProfileView`, `UserProfileModel.action(forLink:defaultBrowser:)` |
| `UserProfileView.swift:631-736` (`UserProfileHeaderView`, `UserProfileQuickActionsView`: avatar, pseudo, status, figures, MP / WL / BL buttons) | `ProfileHeaderSection`; MP through `UserProfileModel.onPrivateMessage` (hook) |
| `UserProfileView.swift:738-780` (`UserProfileAvatarView`, `AsyncImage`) | `ProfileImage` through `ReaderImageFetcher` (difference 3) |
| `UserProfileView.swift:782-805` (`UserProfileActionsView`, opened by `openLink`) | `ProfileActionRow`, section "Liens" |
| `UserProfileView.swift:807-892` (`UserProfileSmiliesView`, with a favourite toggle) | `ProfileSmileysSection`, no toggle (difference 4) |
| `UserProfileView.swift:894-958` (`UserProfileSectionView`, `UserProfileFieldRow`: "Non renseigné" for an empty value, a field link opens outside) | `ProfileFieldRow` |
| `UserProfileView.swift:54-86` (`UserProfileAction.systemImage`), `:245-252` (summary titles and symbols) | `UserProfileAction.Kind.symbol`, `UserProfileSummaryItem.Kind.shortTitle` / `.symbol` (LOT-027 difference 2) |
| `HFRswift/Swift/MessagesView.swift:3578-3608, 4352-4354` (`openProfile`, `userProfileQuickActions`: sheet from the avatar / message actions, MP hidden for one's own message) | entry from a reader link (below); the avatar and message menu entry is LOT-087's |
| `Classes/OnlineMessagesTableViewController.m:1917-1918, 1953-1964` (a tapped `forum.hardware.fr/hfr/profil-<n>.htm` link opens `ProfilViewController` as a form sheet) | `ReaderLinkAction.profile(memberID:)` → `UserProfileView` sheet |
| `Classes/ProfilViewController.m` (the older Objective-C screen, same page) | replaced by the same screen |

## Behaviour

| Piece | Rule |
|---|---|
| Entry | In the topic reader, a link that LOT-095's router reads as `.profile(userID:)` (`https`/`http` `forum.hardware.fr/hfr/profil-<n>.htm`) gives `ReaderLinkAction.profile(memberID:)`, whatever the browser setting; `TopicReaderView` presents `UserProfileView` in a sheet. A look-alike on another host, or a path the router does not know, stays a web link. Other entries (avatar tap, message menu) are LOT-087's and reuse `UserProfileModel(memberID:source:)` |
| Source | `LiveUserProfileSource`: without a login in the session (`HFRSession.isLoggedIn`) no request leaves and the load fails with `ListLoadError.profileLoginRequired` (« Connexion requise », « Le forum réserve les profils aux membres connectés. Connecte-toi à un compte puis réessaie. »); otherwise `PageFetcher.profile(memberID:as: .authenticated)`, then `UserProfileParser.parse`. A 401 or 403 is `.profileAccessDenied` (« Le forum a refusé l’accès au profil. Ta session a peut-être expiré : reconnecte-toi puis réessaie. »), as legacy `bb58131d` (#1363). The page must be served at `https://forum.hardware.fr/hfr/profil-<memberID>.htm` (no port, no user info), else `.unreadable`; a parser failure is `.unreadable`; transport failures map through `ListLoadError`. Built once in `AppEnvironment` and carried by `ReaderServices.profiles` |
| Model | `UserProfileModel`, `@Observable @MainActor`, `ContentLoader` rules: `onAppear` loads once; "Actualiser", pull to refresh and "Réessayer" reload; the profile stays on screen while a reload runs and after it fails (banner). `loadGeneration` counts finished loads; the images' task restarts with it, and `ProfileImageState` keeps an image that loaded (a failed or cancelled retry never blanks it, an unchanged URL is not downloaded again) while retrying one that did not |
| Title | the pseudo once loaded, "Profil" before |
| Header | avatar (placeholder without one), pseudo, status, then the figures as printed by HFR (Messages, Arrivée, Dernier message) |
| Fields | one section per page section; an empty value reads "Non renseigné" (legacy); a field link (a member's website) opens in a browser |
| Smileys | grid of image and code, code selectable; header "Smilies persos (N)" |
| Links | the page's link rows (MP, all messages, transactions, configuration) in a "Liens" section, opened in a browser like legacy `openLink`: Safari's view, or the default browser when "Navigateur par défaut" is on. Never in the app with the session (LESSONS 43) |
| MP button | "Écrire un MP" only when a composer hook is set (`onPrivateMessage`) and the page named the pseudo; it hands the pseudo to the hook. Nothing sets the hook in this lot; the reader sets it on a profile opened from a message's author (#652), from that message's private-message link and never on one's own post, as legacy |
| Lists | blacklist / whitelist buttons are LOT-118's (#209): it adds its own hook next to `onPrivateMessage` |
| Text | every member-written text goes through `Text(verbatim:)`: never read as Markdown or HTML |

## Edge cases
- A page that is not a profile, or a profile served at another URL (a redirect): "Page illisible" with "Réessayer".
- Avatar or smiley on a host the image policy does not call a forum host, or a failed download: the placeholder stays; third-party images
  are never loaded here.
- A member without avatar (`R56a`): placeholder. Without smileys or link rows: the section is absent.

## Pending capture (#124)
Nothing is inferred for these; the screen shows what the parser returns, or "Page illisible".
- ~~A profile seen **logged in**~~: captured (`R716b`, `R124p1`, `R1363b`): the same page plus an "ajouter à la liste de contacts"
  row (legacy `addContact`), parsed by `UserProfileLoggedInTests` (#1363).
- An **expired or refused session** on a profile: HFR's 403 or the stale-session `.hop` (HFR-PROTOCOL §6c LOT-044) is not captured;
  the first is `.profileAccessDenied`, the second `.unreadable` (capture issue #1383).
- A **banned or deleted** member, and an unknown id: the answer (page, redirect, status) is not captured.
- A **real birth date and signature** (HTML or BBCode in a value cell), a status other than "Membre", a smiley file name with an
  apostrophe or a space, a non-`jpg` avatar.

## Intentional differences from legacy
1. **The current account's session.** Legacy at `2440d79` sent whatever `URLSession.shared` held; since `bb58131d` (#1349) it sets the
   main account's cookies on the request and sends nothing without an account. SwiftHFR fetched without cookies until #1363 (the
   parser was verified on logged-out pages only), but HFR answers a profile without cookies 403 since 2026-11-26 (`R1363a`), so the
   profile now goes through the current account's `HFRSession` (`R1363b`), never without a login. The account is the current one,
   not legacy's main one, like every other page of the app.
2. **Served URL checked.** A page served at another URL than the profile asked for is refused, never parsed as a profile. A 401 or
   403 is its own state (legacy `accessDenied`); another error status keeps the app's « Erreur du forum » (legacy `httpStatus`).
3. **Images through the reader's fetcher** (cookie-less, image policy, forum hosts only), not `AsyncImage` on any URL.
4. **No smiley favourite toggle**: the smiley favourites UI is LOT-104's (store LOT-064); the code is selectable instead.
5. **A grouped list** instead of cards and a grid of figures; same content, Dynamic Type and the app's type scale.
6. **Opened from a profile link in a topic** (legacy Objective-C reader) rather than only from the avatar menu (legacy Swift reader):
   the avatar and message menu are not ported yet (LOT-087).
7. **`md_id` checked before sending** (#1420). HFR refuses a profile without `md_id` (`R1420c`), which only the login sets, for 30 days
   (`W1420a`, `R1420g`). Legacy `5c0f10db` sends the request and, on a 403 without `md_id`, says `reloginRequired`; SwiftHFR sends
   nothing when the session lacks it (an account imported from legacy, a login past 30 days) and shows the same state,
   `profileReloginRequired`; a 403 to a session that lost it meanwhile is that state too, a 403 with `md_id` stays
   `profileAccessDenied`. The message points to « Se reconnecter » (SwiftHFR re-logs an account in place) where legacy asks to
   remove and add the account again. The login field set is not changed: SwiftHFR's legacy fields still set `md_id` (`W1420a`, the
   same three cookies as `login.php`'s fields, `W1420b`). Legacy's cookie merge (`MultisManager` `cookies:mergedWith:`) is already
   SwiftHFR's (`HFRSession.mergeCookies`, #383); the iCloud account sync (LOT-173) now keeps this device's `md_id` when a newer copy of
   the same login lacks it, in the store, the shared copy and the session (`AccountSyncMerge`, `adoptSyncedCredentials`).

## Tests
`App/SwiftHFRTests/Profile/`:
- `ProfileImageStateTests`: an image that loaded is kept when a reload fails or is cancelled and is not fetched again for the same URL; a failed image is retried; another URL drops the old image.
- `UserProfileSourceTests` (#1363): `R1363b` and `R56b` are fetched once through the session only (the cookie-less mock gets no request)
  and equal the parser's output; without a login nothing is sent on either client (`profileLoginRequired`), also through a real
  logged-out `HFRSession`, and a logged-in one sends; 401 and 403 (`R1363a`) are `profileAccessDenied`, 500 stays `server`; a page served at another member's, the home, another host, `http` or another port is `.unreadable`; a topic page
  (`R20`) is `.unreadable`; `offline` maps.
- `UserProfileMemberIDTests` (#1420): a session without `md_id` is `profileReloginRequired` and sends nothing, then sends once a login
  sets it; a real `HFRSession` with an imported legacy account's cookies (no `md_id`) or an expired `md_id` reports none; a 403 is
  `profileAccessDenied` with `md_id` and `profileReloginRequired` when the session lost it during the request; the avatar lookup
  sends nothing without `md_id`. `SyncedCredentialsMemberIDTests`: adopting a synced copy without a live `md_id` keeps the jar's for
  the same member, a copy's own `md_id` wins, another member's copy takes none. `AccountsModelMemberIDSyncTests`: a newer copy of the
  same login without `md_id` leaves it in the session, the store and after a relaunch, app running or not, with no new check
  (#1385). Engine: `HFRSessionMemberIDTests` (loopback only), `AccountSyncMemberIDTests` (merge, convergence, live rule).
- `UserProfileModelTests`: one load on repeated appearances, title; a failed load then "Réessayer"; a failed reload keeps the profile; every finished load bumps `loadGeneration`;
  the MP button exists only with a hook and after load, and hands the pseudo; links open in a browser, `javascript:` does nothing.
- `TopicReaderModelTests.aProfileLinkOpensTheProfileSheet`: `https` and `http` profile links give `.profile(memberID:)` with either
  browser setting; another host and a non-numeric id stay web links.

Each was shown to fail with the change reverted (routing line removed, `.authenticated`, URL check removed, `onAppear` guard removed).
