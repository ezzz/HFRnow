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
| `SwiftHFR/Messages/` | Private messages ([LOT-126](../docs/lots/LOT-126-mp-list.md)): `MessageListModel` (paged list, logged-out state, opens a thread in the reader), `PrivateMessageSource` (`PageFetcher` + `PrivateMessageListParser`), `MessagesRootView` (Messages tab: list, then reader), `MessagesListColumn` + `MessageReaderColumn` (iPad content and detail columns); `RootModel.messages` holds the one list model both layouts share; "Nouveau message" and "Répondre" on a conversation ([LOT-128](../docs/lots/LOT-128-mp-composer.md)) |
| `SwiftHFR/FilteredPosts/` | Post filter ([LOT-114](../docs/lots/LOT-114-filter-posts-view.md)): `FilteredPostsModel` (run, progress, batch, "Résultats suivants"), `FilteredPostsServices` (cookie-less source of LOT-093, criteria from the settings), `FilteredPostsView` (banner, sheet, bottom bar); started from a favourite's context menu and the reader menu |
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
