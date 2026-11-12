# App

The iOS app target (SwiftUI, iOS 27), `App/SwiftHFR.xcodeproj` ([ADR 0012](../docs/adr/0012-app-project-file-strategy.md), [LOT-080](../docs/lots/LOT-080-app-target.md)).

| Path | Content |
|---|---|
| `SwiftHFR.xcodeproj` | Project and shared scheme `SwiftHFR`; links the local package `../Packages/HFRKit` |
| `SwiftHFR/` | App sources and assets (folder-synchronized: add files here, the project file does not change) |
| `SwiftHFR/Accounts/` | Accounts and login ([LOT-081](../docs/lots/LOT-081-accounts-login.md)): `AccountsModel` owns every account `HFRSession`; `currentSession` is the session of the current account; `RootView` rebuilds the navigation (`AppEnvironment`) whenever `currentSessionGeneration` changes |
| `SwiftHFR/Root/` | Root navigation ([LOT-170](../docs/lots/LOT-170-tab-bar.md)): `RootModel` (one selection, Messages badge, tab-bar setting), `RootTabsView` (iPhone tab bar Catégories / Favoris / Messages / Plus), `RootSidebarView` (regular-width iPad sidebar), `PlusView` |
| `SwiftHFR/Reader/` | Topic reader ([LOT-083](../docs/lots/LOT-083-topic-reader.md)): `TopicReaderModel` (loads, pages, links), `TopicHTMLBuilder` (document), `ReaderWebController` (`WKWebView`, `hfrreader:` scheme, CSP, no page script), `ImagePolicy` + `ReaderImageFetcher` (policy C, cookie-less images), `Resources/` (`reader.css`, `reader.js`) |
| `SwiftHFR/Composer/` | Reply composer ([LOT-084](../docs/lots/LOT-084-reply-composer.md)): `ReplyComposerModel` (text, draft restore and debounced autosave, send, close choice), `ReplyComposerView` (sheet), `ReaderReplyFlow` (the reader's "Répondre" button, sheet and confirmation banner), `LiveReplyPoster` (LOT-048 through the current account's session), `ComposerServices` (poster, the app's single `DraftStore`, account), `ComposerMessages` (French texts per `PostingError`); the same sheet writes a new private message ([LOT-128](../docs/lots/LOT-128-mp-composer.md): `ComposerTarget`, `NewMessageTarget`, recipient and subject fields) |
| `SwiftHFR/Composer/` (toolbar) | Formatting toolbar ([LOT-085](../docs/lots/LOT-085-composer-toolbar.md)): `ReplyTextInsertionEngine`, `ComposerFormattingModel`, `FormattingToolbar`, `SystemClipboard`; control row and height ([#653](../docs/lots/LOT-174-formatting-toolbar.md#composer-layout-and-control-row-653-m4)): `ComposerHeader` (legacy top bar), `ComposerEditorCard` and `ComposerImageChips` (the docked card), `ComposerControlRow` (clear, undo, redo, Smileys, GIF, image, **Aa**), `ComposerHistory`, `ComposerHeight` (the card's height on iPhone) |
| `SwiftHFR/Messages/` | Private messages ([LOT-126](../docs/lots/LOT-126-mp-list.md)): `MessageListModel` (paged list, logged-out state, opens a thread in the reader), `PrivateMessageSource` (`PageFetcher` + `PrivateMessageListParser`), `MessagesRootView` (Messages tab: list, then reader), `MessagesListColumn` + `MessageReaderColumn` (iPad content and detail columns); `RootModel.messages` holds the one list model both layouts share; "Nouveau message" and "Répondre" on a conversation ([LOT-128](../docs/lots/LOT-128-mp-composer.md)) |
| `SwiftHFR/Profile/` | Member profile ([LOT-116](../docs/lots/LOT-116-user-profile-screen.md)): `UserProfileModel` (load, reload, links, MP hook for LOT-128), `LiveUserProfileSource` (`PageFetcher.profile` **without cookies** + `UserProfileParser`, served URL checked), `UserProfileView` (sheet opened from a profile link in the reader) |
| `SwiftHFR/FilteredPosts/` | Post filter ([LOT-114](../docs/lots/LOT-114-filter-posts-view.md)): `FilteredPostsModel` (run, progress, batch, "Résultats suivants"), `FilteredPostsServices` (cookie-less source of LOT-093, criteria from the settings), `FilteredPostsView` (banner, sheet, bottom bar); started from a favourite's context menu and the reader menu |
| `SwiftHFR/Settings/` (About, Maintenance) | About, static pages and Maintenance ([LOT-120](../docs/lots/LOT-120-maintenance-about.md)): `AboutModel` (version, the two HFR+ topic links read by the link router, their reader), `StaticPage` + `StaticPageView` (credits, charter: bundled HTML, no page script), `Changelog` ("Nouveautés", from `Resources/changelog-v1.json`), `MaintenanceModel` (system-settings shortcut; LOT-179 adds the cache rows); the Plus entries "Crédits" and "Charte du forum" open them |
| `SwiftHFR/Themes/` | Bundled themes ([LOT-188](../docs/lots/LOT-188-theme-engine.md), [THEMES.md](../docs/THEMES.md)): one folder per theme holding `<id>.theme.json` (resources are copied flat into the bundle: names must be unique); read by `ThemeCatalog.bundled`, chosen in Réglages › Thème (`ThemeGallery`) |
| `SwiftHFRTests/` | Unit tests (Swift Testing), hosted by the app |

Build and test on the simulator (unsigned, as CI does):

```sh
xcodebuild build test -project App/SwiftHFR.xcodeproj -scheme SwiftHFR \
  -destination 'platform=iOS Simulator,OS=27.0,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
```

A dependency change in `HFRKit` re-resolves and commits this project's `Package.resolved` in the same PR (CI never resolves packages):

```sh
xcodebuild -resolvePackageDependencies -project App/SwiftHFR.xcodeproj
```

Release to TestFlight (maintainer's Mac): `scripts/release-testflight.sh --version X.Y --build N --dry-run`, then `--upload`
([LOT-161](../docs/lots/LOT-161-release-pipeline.md); credentials stay outside the repository).

Signing is automatic with the team `QMG83DG7YP` and bundle id `hfrplus.red.super`; a device build needs that team's account in Xcode. Never commit certificates, profiles or `xcuserdata/`.

## API keys (ADR 0007)

The image-rehost key reaches the build through `App/Config/Shared.xcconfig`, which includes the untracked `App/Config/Secrets.xcconfig` when it exists, and `App/Config/Info-Keys.plist` (merged into the generated Info.plist: `RehostBaseURL`, `RehostAPIKey`, `GiphyBaseURL`, `GiphyAPIKey`). The Giphy key (`GIPHY_API_KEY`, base `GIPHY_BASE_URL`) is wired the same way, and so is the moderators' address of the "Alerter" mail fallback (`MODERATOR_ALERT_MAIL_ADDRESS` → `ModeratorAlertMailAddress`, LOT-135, Q-10: set in `Shared.xcconfig` to the public address legacy uses; `Secrets.xcconfig` can override it, and an empty value there turns it off; an old copy of `Secrets.xcconfig.example` still has an uncommented empty line: delete it).

- Local build: copy `App/Config/Secrets.xcconfig.example` to `App/Config/Secrets.xcconfig` and fill in the values (git-ignored; write `//` as `/$()/` in a URL).
- No `Secrets.xcconfig` (fresh clone, CI tests): the build works, the image-rehost and Giphy values are empty and the composer hides image upload (LOT-102) and the GIF button (LOT-155).
- CI/release builds that must upload need `REHOST_BASE_URL`, `REHOST_API_KEY`, `GIPHY_BASE_URL` and `GIPHY_API_KEY` written into `Secrets.xcconfig` from Actions secrets by the build job; the maintainer sets them.
