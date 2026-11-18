# LOT-132 — Bookmarks

- **Module:** App (`MPStorage/`: `BookmarkList`, `BookmarksModel`, `BookmarksView`; `Reader/Actions/`: `BookmarkActionModel`, `ReaderBookmarkFlow`; hooks in `MessageMenuContext`, `TopicReaderModel+Menu`, `TopicReaderView`, `RootNavigationView`, `RootModel`, `RootSidebarView`, `PlusView`, `RootTab`)
- **Difficulty / model:** medium (Opus 5.5 author → Fable 5.2 reviewer)
- **Issue:** [#222](https://github.com/ezzz/HFRnow/issues/222)
- **Depends on:** LOT-130 (`MPStorageSyncModel`: `writeConsent`, `edit`, `document(for:)`, `start`, `resync`), LOT-062 (`addBookmark`, `removeBookmark`, merge), LOT-087 (the message menu and its registry), LOT-095/137 (`ReaderTarget(link:)`), #1089 (the three-column Bookmarks on the regular-width iPad), all done.

## Legacy sources
`https://github.com/ezzz/HFRnow` @ `87fe0d1c`.

| Legacy | Behaviour |
|---|---|
| `Classes/ObjCMessageActionsBuilder.m:17-18, 54` | `canBookmark` = `mpstorage_active` and the topic is not a private message (`cat != prive`) |
| `HFRswift/Swift/MessagesView.swift:4545-4566` (`askBookmarkPrompt`) | missing topic, category or numeric message number → toast « Données bookmark incomplètes »; already bookmarked (same `post` and `numreponse`, `MPStorage.m:583-591`) → « Post déjà dans les bookmarks »; else the prompt |
| `HFRswift/Swift/MessagesView.swift:5475-5496` | the prompt: title « Bookmark », message « Créer un bookmark sur le post de <author> ? », placeholder « Ajoutez un titre », button « Créer »; success « Bookmark créé », failure « Erreur à la création du bookmark » |
| `HFRswift/Swift/MessagesView.swift:453-530` (`MessagePopupPromptSheet`) | a sheet; « Créer » disabled while the trimmed title is empty (`:492`); the trimmed title is sent |
| `Classes/MPStorage.m:313-357` (`addBookmarkSynchronous:`) | GET, refuse a `numreponse` already listed, insert `{createDate, post, author, numreponse, cat, label}` at index 0, save; any failure → NO |
| `Classes/MPStorage.m:359-397` (`removeBookmarkSynchronous:`) | GET, remove the **last** entry with that `numreponse`, save |
| `Classes/MPStorage.m:594-620` (`parseBookmarks`) | the list sorted by `createDate`, newest first |
| `Classes/Bookmark.m:17-19` (`getUrl`) | `/forum2.php?config=hfr.inc&cat=<cat>&post=<post>&numreponse=<n>#t<n>` |
| `HFRswift/Swift/BookmarksPlusView.swift:139-149` (`makeTopic`) | the row's topic: title = trimmed label, « Bookmark » when empty; URL = `getUrl` |
| `HFRswift/Swift/BookmarksPlusView.swift:168-236` | rows: title, author (bottom left), date `dd/MM/yyyy 'a' HH:mm` fr_FR (bottom right, « - » without a date); « Aucun bookmark »; « Stockage MP désactivé » + « Activez "Activer le stockage MP" dans Réglages pour récupérer vos bookmarks. » when off; « Erreur : <message> »; swipe to delete; « Actualiser » in the toolbar and pull to refresh reload the document |
| `HFRswift/Swift/MainWindow.swift:1976-1981, 2266-2271` | iPad: the row opened is selected; deleting it clears the detail column |

## Legacy counterpart (app lots)
- `App/SwiftHFR/MPStorage/BookmarksModel.swift`: `HFRswift/Swift/BookmarksPlusView.swift (BookmarksPlusViewModel)` and `Classes/MPStorage.m (parseBookmarks, removeBookmarkSynchronous:)` @ `87fe0d1c`, GAP-040, GAP-183.
- `App/SwiftHFR/MPStorage/BookmarksView.swift`: `HFRswift/Swift/BookmarksPlusView.swift (BookmarksPlusView)` @ `87fe0d1c`, GAP-040.
- `App/SwiftHFR/MPStorage/BookmarkList.swift`: `Classes/Bookmark.m (getUrl)`, `Classes/MPStorage.m (parseBookmarks, getBookmarkForPost:numreponse:)` @ `87fe0d1c`.
- `App/SwiftHFR/Reader/Actions/BookmarkActionModel.swift`: `HFRswift/Swift/MessagesView.swift (askBookmarkPrompt, the bookmark sheet)` and `Classes/MPStorage.m (addBookmarkSynchronous:)` @ `87fe0d1c`, GAP-068, GAP-183.
- `App/SwiftHFR/Reader/Actions/ReaderBookmarkFlow.swift`: `HFRswift/Swift/MessagesView.swift (MessagePopupPromptSheet)` @ `87fe0d1c`, GAP-068.

## UX evolutions (app lots)
- **GAP-183** (`a`, ported with changes): the bookmark is written in the device copy first and sent by LOT-130's sync; a forum failure no longer refuses the bookmark: « Bookmark créé sur cet appareil. » followed by LOT-130's sentence for that failure (it says whether the next sync retries).
- **First write asks** (ADR 0013 §7, `b·needed`, as LOT-131): an account that never chose (`unasked`) is offered « Bookmark » too; picking it asks « Activer le stockage MP pour ce compte (un message privé sur le forum) ? Il garde les bookmarks et la liste noire partagée. » (« Activer » / « Annuler »): legacy's switch is single, so the shared blacklist syncs too (LOT-131's reconciliation writes the device list). « Activer » → `setEnabled(true, from: .write)`: an existing thread turns the account `on` and the title prompt follows; none → the creation question at the root (LOT-131's), and the member picks « Bookmark » again once it exists. « Annuler » records nothing: bookmarks have no device-only list, so there is nothing to « keep on this device » (legacy hid the entry until the switch was on).
- The date reads `dd/MM/yyyy à HH:mm` (legacy's literal `'a'` was a missing accent).

## Behaviour
- **Where bookmarks live.** Only in the account's MPStorage document (ADR 0013 table: « MPStorage (unchanged) + device-only cached copy »): the list shows `document(for: .bookmarks)`, the device copy LOT-130 keeps (pending local edits included), so it is readable offline and follows every sync. No other store.
- **Menu entry** (`BookmarkActionModel.canBookmark`): a public topic (`TopicID.category` is `.forum`, never `.privateMessages`), a message number above 0, the session's `MPStorageSyncModel`, the bookmarks function on (`isEnabled(.bookmarks)`) and a record `on` or `unasked`. The record is read as it stands (no reload while the menu is built); `declined`, `off` and an unreadable record hide the entry, as legacy hid it while `mpstorage_active` was off. The saved-copy reader has no session model and offers nothing.
- **Topic of the message**: `MessageMenuContext.topic`, from the page (`ReaderPage.topicID`), else the target shown.
- **Picking « Bookmark »** (`start`): consent read again (`writeConsent(for: .bookmarks)`, another window may have decided). `.deviceOnly` → « Activez le stockage MP dans Réglages pour créer un bookmark. »; `.ask` → the question above; `.sync` → `offer`.
- **`offer`**: the device copy is shown first (`MPStorageSyncModel.loadCopyIfNeeded()`, no request); when the document was never read on this device, one `resync()` (LOT-130's `edit` refuses `notLoaded`); still nothing read (offline, logged out) → LOT-130's sentence and no prompt; then a bookmark of the same category, topic and message (`MPStorageBookmark.id`) → « Post déjà dans les bookmarks »; else the prompt.
- **The prompt** (`ReaderBookmarkFlow`): a sheet, legacy's texts; « Créer » disabled while the trimmed title is empty or holds a character outside the BMP (most emoji, refused by LOT-062, HFR-PROTOCOL §6), the latter said under the field (« Les emoji ne peuvent pas être enregistrés dans le stockage MP. ») so the title is never lost to a refused write; the trimmed title is the label.
- **One pick at a time** (`isWorking`): while a pick or a consent answer runs (a forum read, the switch-on), another pick does nothing and the reader keeps the model, so the prompt it ends with is shown.
- **Consent answer**: « Activer » that leaves the account undecided without the creation question (offline, logged out, search at its limit) says LOT-130's sentence; a decision taken in another window meanwhile (`off`, `declined`) says « Activez le stockage MP dans Réglages pour créer un bookmark. »
- **Creation** (`create`): one `edit(.bookmarks)` adding `{post, cat, numreponse, author, label}` (the date is the edit's stamp, LOT-062). Changed → « Bookmark créé », or « Bookmark créé sur cet appareil. » + LOT-130's sentence when the sync after it failed (the edit stays pending, LOT-130); not changed and the document now holds it → « Post déjà dans les bookmarks »; the account no longer syncs (another window) → « Activez le stockage MP dans Réglages pour créer un bookmark. »; else LOT-130's sentence (a refused document: size), « Erreur à la création du bookmark » without one.
- **List** (`BookmarksModel`, `BookmarksView`, Plus › Bookmarks on every layout): newest first (`createdAt`, undated last, then the document order), a message another client listed twice once (rows are identified by `MPStorageBookmark.id`; a deletion removes every copy, LOT-062); row title = trimmed label or « Bookmark », author, date. Appearance runs `MPStorageSyncModel.start()` (once per model, as the Messages tab); « Actualiser » and pull to refresh run `resync()`; `working` shows a spinner in the button. States: logged out → « Connectez-vous pour voir vos bookmarks. »; the account does not sync → legacy's « Stockage MP désactivé »; on and the list empty → « Aucun bookmark »; a failed call → « Erreur : <LOT-130's message> » above the list (no pseudo, no document text).
- **Opening** (bug #106): `BookmarkList.link` is legacy's `getUrl`, read by `ReaderTarget(link:)` (LOT-095's router): the target names the message (`numreponse`, so HFR serves the page that holds it, R25) and scrolls to `#t<n>`. On the regular-width iPad the row opens beside the list (`OpenTopicInDetail`, #1089) and stays selected; elsewhere it is pushed on the Plus stack.
- **Shown at once**: `MPStorageSyncModel.edit` shows the device copy right after the local edit, before the forum exchange (a change to LOT-130's model; the merge's "before" is still the document shown when the call began, so LOT-131's reconciliation diffs the same documents): a swiped row leaves the list at once, a created bookmark is listed before the sync ends.
- **Selection**: the bookmark open in the detail column is the window's (`BookmarkSelection`, held by `RootModel` next to `detailReaders`, legacy `bookmarksTopicTarget`), so a list built again (the sidebar left Bookmarks and came back) still selects it and its deletion still closes the detail.
- **Delete**: swipe « Supprimer » → the consent read again (`writeConsent`: a window whose account was switched off elsewhere writes nothing), then one `edit(.bookmarks)` removing that `id` (a tombstone is written when the section allows it, LOT-062). Deleting the bookmark open in the detail column closes it (`OpenTopicInDetail.close`), only when the edit removed it.
- No HFR request of its own: every forum access is LOT-130's `MPStorageSync` over LOT-052's transport; the document shape is HFR-PROTOCOL §3.3.

## Edge cases
- Two bookmarks of the same `numreponse` in different categories are two bookmarks (the id is category, topic and message); legacy compared `numreponse` only.
- A bookmark written by another client with `cat` = `prive` opens through the router like any `numreponse` link; a `cat` the router cannot read gives no target, the row is shown and does nothing (no dead link followed).
- A bookmark whose label is blank is listed as « Bookmark ».
- A delete or creation while the account is `on` but offline: the edit is kept pending and written at the next sync (LOT-130); the list shows it at once.
- The account switched off in another window between the menu and the pick, or the prompt and « Créer »: « Activez le stockage MP dans Réglages pour créer un bookmark. », nothing written.
- A title with an emoji: « Créer » stays off and the sheet says why (the storage message is cut at a non-BMP character, LOT-062).
- Undecodable bookmark entries of another client are kept by LOT-062 and not listed.

## Fixtures
None: no new HFR state. The tests drive LOT-130's scripted `FakeMPStorageRemote` (no `HFRSession`: no request can leave the process) with synthetic `0.1` documents (HFR-PROTOCOL §3.3). No pending capture.

## Tests
`App/SwiftHFRTests/MPStorage/BookmarksTests.swift`
- `BookmarkListTests`: the link is legacy's `getUrl`; its target names the message and its anchor (bug #106); a `prive` bookmark routes, an unreadable `cat` gives none; newest first, undated last, a duplicate once; blank label reads « Bookmark »; the date format.
- `BookmarksModelTests`: the list follows the document; nothing listed while the account does not sync; delete writes the removal and drops the row; refresh reads the forum; logged-out and off states; deleting the bookmark open beside the list closes it; a deletion shows before the forum answers (`ReadGate`); the selection outlives the list screen; a deletion is not written once another window switched off; a deletion that removes nothing keeps the detail; no error shown while the account does not sync.
- `TopicReaderMenuTests.theContextNamesTheTopicOfThePage`, `RootModelDetailColumnTests.closingADetailColumnShowsItsPlaceholderAgain` (app-hosted).
- Run on Linux (the SwiftUI-free models and their tests compiled against HFRKit in a scratch package), and shown failing with each guard reverted: the private-topic refusal, the record states offered, the duplicate check, the copy shown before it, the blank title, the « prochaine synchronisation » sentence, the decision taken elsewhere, the link naming the message, the undated order, the selection cleared by a delete, the off state; after Fable round 1 also the one-pick-at-a-time guard, the « déjà » branch of `create`, the not-syncing sentences, « Données bookmark incomplètes », the topic above 0, the error hidden while off, the consent re-read before a delete, the close only on a removal, the emoji refusal, the unread document without prompt, the failed switch-on sentence.
- `BookmarkActionModelTests`: entry offered on a public topic of an `on` or `unasked` account, hidden on a private message, a `declined` / `off` account, without a session model or topic; a bookmark is created with the trimmed label and the message's author and written to the forum; an empty title creates nothing; a duplicate is refused; an unread document is read before the duplicate check; a failed write still keeps the bookmark and says so; an `unasked` account asks first and « Activer » with a thread turns it on then prompts; « Annuler » records nothing; a second pick while the first reads is ignored (`ReadGate`); incomplete data; switched off before the pick or before « Créer »; a bookmark added meanwhile; an emoji title; a refused document; a document that cannot be read opens no prompt; « Activer » offline says why; a pick while « Activer » switches on is ignored (`ReadGate`); the creation question adds no message. (`App/SwiftHFRTests/MPStorage/BookmarkActionModelTests.swift`)

## Intentional differences from legacy
1. Local first: a forum failure no longer refuses the bookmark (`MPStorage.m:313-357`, GAP-183).
2. Identity is category, topic and message; legacy compared `numreponse` only (`MPStorage.m:332, 381`), and removed the last match only.
3. An undecided account is asked at the first bookmark (ADR 0013 §7) instead of the entry being hidden.
4. The date's « à » (legacy `'a'`).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A menu's availability check runs while the menu is built: read the state as it stands, never through a method that writes observed state (`writeConsent` reloads the record).
