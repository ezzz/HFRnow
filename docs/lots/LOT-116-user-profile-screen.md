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
| `HFRswift/Swift/UserProfileView.swift:113-135` (`UserProfileService.fetchProfile`: `URLSession.shared`, so the shared cookies) | `LiveUserProfileSource` (cookie-less, difference 1) |
| `UserProfileView.swift:464-490` (`UserProfileViewModel`: load, `isLoading`, `errorMessage`) | `UserProfileModel` over `ContentLoader` |
| `UserProfileView.swift:492-616` (`UserProfileView`: sheet, "Fermer", "Actualiser", loading and error views, `openLink` by the default-browser setting) | `UserProfileView`, `UserProfileModel.action(forLink:defaultBrowser:)` |
| `UserProfileView.swift:631-736` (`UserProfileHeaderView`, `UserProfileQuickActionsView`: avatar, pseudo, status, figures, MP / WL / BL buttons) | `ProfileHeaderSection`; MP through `UserProfileModel.onPrivateMessage` (hook) |
| `UserProfileView.swift:738-780` (`UserProfileAvatarView`, `AsyncImage`) | `ProfileImage` through `ReaderImageFetcher` (difference 3) |
| `UserProfileView.swift:782-805` (`UserProfileActionsView`, opened by `openLink`) | `ProfileActionRow`, section "Liens" |
| `UserProfileView.swift:807-892` (`UserProfileSmiliesView`, with a favourite toggle) | `ProfileSmileysSection`, no toggle (difference 4) |
| `UserProfileView.swift:894-958` (`UserProfileSectionView`, `UserProfileFieldRow`: "Non renseigné" for an empty value, a field link opens outside) | `ProfileFieldRow` |
| `UserProfileView.swift:26-31, 54-86` (`UserProfileAction.systemImage`, summary titles and symbols) | `UserProfileAction.Kind.symbol`, `UserProfileSummaryItem.Kind.shortTitle` / `.symbol` (LOT-027 difference 2) |
| `HFRswift/Swift/MessagesView.swift:3578-3608, 4352-4354` (`openProfile`, `userProfileQuickActions`: sheet from the avatar / message actions, MP hidden for one's own message) | entry from a reader link (below); the avatar and message menu entry is LOT-087's |
| `Classes/OnlineMessagesTableViewController.m:1917-1918, 1953-1964` (a tapped `forum.hardware.fr/hfr/profil-<n>.htm` link opens `ProfilViewController` as a form sheet) | `ReaderLinkAction.profile(memberID:)` → `UserProfileView` sheet |
| `Classes/ProfilViewController.m` (the older Objective-C screen, same page) | replaced by the same screen |

## Behaviour

| Piece | Rule |
|---|---|
| Entry | In the topic reader, a link that LOT-095's router reads as `.profile(userID:)` (`https`/`http` `forum.hardware.fr/hfr/profil-<n>.htm`) gives `ReaderLinkAction.profile(memberID:)`, whatever the browser setting; `TopicReaderView` presents `UserProfileView` in a sheet. A look-alike on another host, or a path the router does not know, stays a web link. Other entries (avatar tap, message menu) are LOT-087's and reuse `UserProfileModel(memberID:source:)` |
| Source | `LiveUserProfileSource`: `PageFetcher.profile(memberID:as: .anonymous)`, then `UserProfileParser.parse`. The page must be served at `https://forum.hardware.fr/hfr/profil-<memberID>.htm` (no port, no user info), else `.unreadable`; a parser failure is `.unreadable`; transport failures map through `ListLoadError`. Built once in `AppEnvironment` and carried by `ReaderServices.profiles` |
| Model | `UserProfileModel`, `@Observable @MainActor`, `ContentLoader` rules: `onAppear` loads once; "Actualiser", pull to refresh and "Réessayer" reload; the profile stays on screen while a reload runs and after it fails (banner) |
| Title | the pseudo once loaded, "Profil" before |
| Header | avatar (placeholder without one), pseudo, status, then the figures as printed by HFR (Messages, Arrivée, Dernier message) |
| Fields | one section per page section; an empty value reads "Non renseigné" (legacy); a field link (a member's website) opens in a browser |
| Smileys | grid of image and code, code selectable; header "Smilies persos (N)" |
| Links | the page's link rows (MP, all messages, transactions, configuration) in a "Liens" section, opened in a browser like legacy `openLink`: Safari's view, or the default browser when "Navigateur par défaut" is on. Never in the app with the session (LESSONS 43) |
| MP button | "Écrire un MP" only when a composer hook is set (`onPrivateMessage`) and the page named the pseudo; it hands the pseudo to the hook. **Nothing sets the hook in this lot**: LOT-128 (#219, PR #398) wires it, and decides then whether one's own profile hides it, as legacy hid MP on one's own message |
| Lists | blacklist / whitelist buttons are LOT-118's (#209): it adds its own hook next to `onPrivateMessage` |
| Text | every member-written text goes through `Text(verbatim:)`: never read as Markdown or HTML |

## Edge cases
- A page that is not a profile, or a profile served at another URL (a redirect): "Page illisible" with "Réessayer".
- Avatar or smiley on a host the image policy does not call a forum host, or a failed download: the placeholder stays; third-party images
  are never loaded here.
- A member without avatar (`R56a`): placeholder. Without smileys or link rows: the section is absent.

## Pending capture (#124)
Nothing is inferred for these; the screen shows what the parser returns, or "Page illisible".
- A profile seen **logged in**: the screen fetches without cookies until a capture shows what a logged-in view adds (an "ajouter à la
  liste de contacts" row, legacy `addContact`).
- A **banned or deleted** member, and an unknown id: the answer (page, redirect, status) is not captured.
- A **real birth date and signature** (HTML or BBCode in a value cell), a status other than "Membre", a smiley file name with an
  apostrophe or a space, a non-`jpg` avatar.

## Intentional differences from legacy
1. **Fetched without cookies.** Legacy used `URLSession.shared` and so sent the account's cookies. The captures are logged out and the
   parser is verified on them only; a logged-in view is not captured (#124), so the session is not sent for a page it does not change in
   any known way.
2. **Served URL checked.** A page served at another URL than the profile asked for is refused, never parsed as a profile.
3. **Images through the reader's fetcher** (cookie-less, image policy, forum hosts only), not `AsyncImage` on any URL.
4. **No smiley favourite toggle**: the smiley favourites UI is LOT-104's (store LOT-064); the code is selectable instead.
5. **A grouped list** instead of cards and a grid of figures; same content, Dynamic Type and the app's type scale.
6. **Opened from a profile link in a topic** (legacy Objective-C reader) rather than only from the avatar menu (legacy Swift reader):
   the avatar and message menu are not ported yet (LOT-087).

## Tests
`App/SwiftHFRTests/Profile/`:
- `UserProfileSourceTests`: `R56b` is fetched once through the cookie-less client only (the session mock gets no request) and equals the
  parser's output; a page served at another member's, the home, another host, `http` or another port is `.unreadable`; a topic page
  (`R20`) is `.unreadable`; `offline` maps.
- `UserProfileModelTests`: one load on repeated appearances, title; a failed load then "Réessayer"; a failed reload keeps the profile;
  the MP button exists only with a hook and after load, and hands the pseudo; links open in a browser, `javascript:` does nothing.
- `TopicReaderModelTests.aProfileLinkOpensTheProfileSheet`: `https` and `http` profile links give `.profile(memberID:)` with either
  browser setting; another host and a non-numeric id stay web links.

Each was shown to fail with the change reverted (routing line removed, `.authenticated`, URL check removed, `onAppear` guard removed).
