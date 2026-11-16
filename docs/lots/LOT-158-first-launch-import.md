# LOT-158 — Legacy data import on first launch

- **Module:** App
- **Difficulty / model:** medium (Opus 5.5 → Fable 5.1)
- **Issue:** [#248](https://github.com/ezzz/HFRnow/issues/248)
- **Depends on:** LOT-067 (#92, the importer, merged in #703 as `fddb6a37`), LOT-081 (#99, accounts), LOT-119 (#210, settings and `LegacySettingsNormalizer`)
- **Placement:** [ADR 0013](../adr/0013-storage-tiers.md) §5 and Amendment 3; appendix F (`migration.legacyImport.version`, device-only)
- **Retirement:** [#708](https://github.com/ezzz/HFRnow/issues/708) removes the import, the pending lists and the call sites listed under "Call sites"

## Legacy sources

None to port: legacy is the app this update replaces, in the same container (Q-1), and never imported its own data. The app side only places the LOT-067 importer in the app's life cycle and reads what the importer left pending. The legacy behaviours it matches, at the reference `legacy/duo-inner-cover` @ `87fe0d1c` (AGENTS.md §2):

| Behaviour | Legacy file:line @ `87fe0d1c` |
|---|---|
| The reader reads the active reply draft of `post-<topic number>`, whatever the category, so a draft follows the number alone | `HFRswift/Swift/MessagesView.swift:3309-3335` (`replyDraftContext`, `resolvedTopicDraftID`, `activeReplyDraftText`); `HFRswift/Swift/AnswerView.swift:140, 159-164` (`ReplyDraftStore.activeText`) |
| Super-favourites are topic numbers, matched against every favourites row by number | `HFRswift/Swift/Favorites.swift:132-157` (`FavoritesSuperFavoriteStore`), `:542, 774` (read when the list is built and shown) |
| No action empties the super-favourites at once (only the per-row toggle) | `HFRswift/Swift/Favorites.swift:955` (the only `save`) |

Everything about the legacy stores themselves (keys, files, formats) is in the [LOT-067 spec](LOT-067-legacy-import.md).

## Legacy counterpart (app lots)

- `App/SwiftHFR/LegacyImport/LegacyImportModel.swift`, `LegacyImportSummary.swift`, `LegacyImportSummaryView.swift`, `LegacyImportServices.swift`: none @ `87fe0d1c` (the import is new, GAP-170).
- `App/SwiftHFR/SwiftHFRApp.swift`, `RootView.swift`: the launch order and the summary sheet; none @ `87fe0d1c`.
- `FavoritesOptionsModel.placePendingSuperFavorites(from:)`: `HFRswift/Swift/Favorites.swift (FavoritesSuperFavoriteStore)` @ `87fe0d1c`, matched by number as legacy did.
- `LegacyDraftResolver`, its calls in `TopicReaderModel` and `ReplyComposerModel.start()`: `HFRswift/Swift/MessagesView.swift (resolvedTopicDraftID)` @ `87fe0d1c`.

## UX evolutions (app lots)

- **GAP-170** (`new`, `new UX: spec`, H.1 `a`): the import itself, its progress and its summary. Legacy had none (it was the app). Class `a` stands: nothing of legacy's own UX changes; the summary is the one new screen, shown only when the import did something or failed.

## Behaviour

### Launch order

1. `LegacySettingsNormalizer.run` (LOT-119), unchanged, in `SwiftHFRApp.init`.
2. **Import** (`LegacyImportModel.runAtLaunch`): `LegacyImporter.run(currentAccount: nil)`. It runs before the accounts are read, so the accounts it imports into the LOT-065 Keychain item are in the list when the app shows it. While it runs, the root screen shows `LegacyImportProgressView` (#754: an illustrated construction worker and "Import de vos données HFR+…").
3. **Accounts** (`AccountsModel.restore`, LOT-081): reads the store, now holding the imported accounts.
4. **After each change of the current account** (restore, login, switch): when the last report is not complete and an account is current, the import runs again with that account (`accountDidChange(to:)`): the global items of decision D3 wait for an account when legacy had no main account, and a step that failed with a retriable error tries again. The engine runs each step once (LOT-067 Idempotence): a complete import costs one read of the state file, and a later call is a no-op.

The importer runs every launch until it is complete; once complete, the launch run only reads its state and reports every step `alreadyDone`, and no summary shows. "First launch" is the first launch at which the import has something to do.

### Progress

The engine's `run` returns one report at the end and has no progress callback; the import is local (Keychain, `UserDefaults`, a few files, the page cache) and short. The progress is the root screen's indeterminate progress view with the label above, shown while the launch run runs. A finer progress would need an engine change (a callback per step) for a screen that shows for a fraction of a second: not done.

### Summary

`LegacyImportSummary` is built from the reports of this launch: each step keeps the most informative outcome seen (a later `alreadyDone` never hides an `imported` of an earlier run of the same launch), and `rejectedItems` add up. It is shown as a sheet over the root screen after a run when **at least one data step** (`accounts` … `drafts`) imported something or failed, or when items were rejected. A run where everything was `nothingToImport`, `alreadyDone` or `waitingForAccount` shows nothing: a fresh install of SwiftHFR, or a launch after a complete import, is silent.

The sheet, in French, counts only (no pseudo, no text, ADR 0013 Secrets):
- title "Import de HFR+", one line "Vos données de l’ancienne version ont été reprises. Rien n’a été effacé, sauf l’ancien cache des pages.";
- one row per data step that is not `nothingToImport` or `alreadyDone`, plus the page-cache row when it removed pages: the item name and its result:

| Step | Name | `imported(n)` |
|---|---|---|
| `accounts` | Comptes | "n compte(s)" |
| `pseudoLists` | Listes noire et blanche | "n pseudo(s)" |
| `superFavorites` | Super favoris | "n sujet(s), placé(s) au prochain chargement des favoris" |
| `collapsedSections` | Sections repliées des favoris | "n section(s)" |
| `smileyFavorites` | Smileys favoris | "n smiley(s)" |
| `smileySearchHistory` | Recherches de smileys | "n recherche(s)" |
| `uploadHistory` | Images envoyées | "n image(s)" |
| `drafts` | Brouillons | "n brouillon(s), rouvert(s) à l’ouverture du sujet" |
| `pageCache` | Ancien cache des pages | "n page(s) supprimée(s)" |

  Other outcomes: `waitingForAccount` "En attente d’un compte : repris à la première connexion"; `failed(.sourceUnreadable)` "Illisible : ignoré, l’original est conservé"; `failed(.sourceUnavailable)` and `failed(.destinationFailed)` "Échec : sera réessayé".
- "n élément(s) refusé(s) (pseudo vide ou invalide)" when `rejectedItems > 0`;
- a "Réessayer" button when a step failed with a retriable error: it runs the import again with the current account and refreshes the sheet; "OK" closes it.

`mpStorageSwitch` is not shown: it is not user data, it is kept in the import state for LOT-130 (ADR 0013 §7).

### Pending items (decisions D1, D2)

- **Super-favourites.** At each favourites-list load (`TopicListModel.load` of a favourites page, after the folded sections are pruned), `FavoritesOptionsModel.placePendingSuperFavorites(from:)` hands every topic of the page to `LegacyPendingStore.resolveSuperFavorites` for the current account, then reads the super-favourites again when it placed some. Nothing without an account or with an empty page. A failure (the pending store or the super-favourites store refusing) changes nothing visible: the numbers stay pending and the next load tries again; a super-favourites store that cannot be read is already shown by `reload()`.
- **Discard.** No SwiftHFR action empties the super-favourites at once, as legacy (`Favorites.swift:955`): `discardPendingSuperFavorites` has no caller here; the lot that adds such an action calls it. Pending numbers otherwise expire after 90 days (LOT-067).
- **Reply drafts.** `LegacyDraftResolver.resolve(_:)` turns the pending draft of the topic's number into the topic's reply draft (`ReplyTarget.draftContext(of:)`, the composer's own context) for the current account; an existing SwiftHFR draft wins (LOT-067). It is called when the reader delivers a page with a topic id (the topic opens) and offers a reply (it has the account's composer, `TopicReaderModel.adopt(_:composer:)`), and awaited by `ReplyComposerModel.start()` for a reply before the draft is read, so a composer opened before the reader's call ended still finds the draft. A failure keeps the draft pending, tried again at the next opening; the composer's own draft read shows a draft store failure (LOT-084). The number matches in any category, private messages included, as legacy's `post-<n>` did.

### Call sites (to remove with #708)

`SwiftHFRApp` (launch run, current account changes), `RootView` (progress label, summary sheet), `FavoritesStores.pending`, `FavoritesOptionsModel.placePendingSuperFavorites`, `TopicListModel.load`, `TopicReaderModel.adopt(_:composer:)`, `TopicReaderModel.legacyDrafts`, `ComposerServices.legacyDrafts`, `ReplyComposerModel.start`, `App/SwiftHFR/LegacyImport/`.

### Stores

One instance per file for the whole process (two actors over a file would write it at once): the importer writes through the app's existing live stores (`PseudoListsSnapshot.liveStore`, `FavoritesStores.shared`, `ComposerServices.liveSmileyFavorites`, `.liveSmileySearchHistory`, `.liveDrafts`, `ImageUploadServices.liveHistory.store`), `LiveCredentials.store`, the one `KeychainCredentialStore` over the bundle identifier that `AccountsModel.live()` also writes through (its read-modify-write lock is per instance), and `UserDefaultsSettingsStore`. Two new files under Application Support, device-only: `LegacyImport/state.json` (the import state, `migration.legacyImport.version`) and `LegacyImport/pending.json` (`LegacyImportServices.livePending`). The legacy container is the app's own `Documents`, `Library/Caches`, the standard `UserDefaults` and `KeychainLegacyAccountSource` over the bundle identifier.

## Edge cases

- Keychain locked at launch (`sourceUnavailable` on `accounts`): the summary says it will be retried; "Réessayer" or the next launch imports the accounts, and the account list is read again when a later run imported accounts (`AccountsModel.readStoreAgain`: it waits for a restore in progress, which may have read the store before the import wrote it, then reads again).
- No legacy account: the global items wait (`waitingForAccount`, no summary for that alone) and go to the first account that becomes current (D3).
- A SwiftHFR account already stored (a beta used before the update): kept as it is; the legacy main does not replace it (LOT-067).
- The app killed during the import: the engine reruns the unfinished steps at the next launch (LOT-067).
- Two runs at once (a login while the launch run runs): the engine serializes them; the model counts runs in flight.
- A pending draft for a topic opened logged out: nothing (no account, no composer).

## Secrets

The app side never reads an account record, a cookie or a token: it passes the current account's pseudo to the engine and shows counts. Nothing is logged.

## Fixtures

None: no HFR page. The model tests use a scripted importer and in-memory stores; the real-device check is a Mac check (below).

## Tests

`App/SwiftHFRTests/LegacyImport/`:
- `LegacyImportModelTests` (11): the launch run happens once and names no account; nothing to import, only waiting steps, or a complete import stay silent; an import or refused items show the summary; a retry runs with the current account, keeps what the first run imported and refreshes the same sheet; a later failure shows a closed sheet again, a later run that only finds steps done does not; an account change runs only while incomplete and with an account; a run says when it imported accounts, and a retry that finds nothing refreshes the open sheet; overlapping runs keep `isRunning` until the last ends.
- `LegacyImportSummaryTests` (9): each step's wording and order, singular and plural; failures and waiting steps; an unreadable source offers no retry; the switch is never shown; the page-cache row only with data, its failure never offers a retry; `alreadyDone` never replaces an earlier result while a later outcome does; refused items add up.
- `AccountsReadAgainTests` (1): an account written while the launch restore runs is listed after `readStoreAgain`.
- `LegacyPendingPlacementTests` (5): pending super-favourites placed in every category the loaded favourites list shows, through `TopicListModel.loadIfNeeded`, the unlisted one kept; nothing without an account; the composer starts on the legacy draft; an existing SwiftHFR draft wins; a delivered reader page makes the legacy draft the topic's reply draft.

The model and summary suites also run on Linux in a scratch package over these files and HFRKit (the app cannot build there): 20 tests green, and 9 mutations each caught (the launch guard, the completeness guard, `alreadyDone` replacing a result, the page cache or the switch counted as data, a retry offered for the page cache, the summary always shown, the accounts flag, the run counter). `LegacyImportServices` and the body of `placePendingSuperFavorites` were type-checked there against HFRKit with the app's stores stubbed. The placement suite needs the app target: CI and the Mac run it.

## Mac checks (device, with #709's samples)

1. Install the legacy build (`87fe0d1c` or the shipped 4.0.x), add synthetic accounts, lists, super-favourites, smiley favourites, a search history, an upload, an active draft and `brouillon`; then install SwiftHFR over it (same bundle id).
2. First launch: the progress label, then the summary with the expected counts; the accounts are in the list and logged in without a new login; the legacy `HFR_COMPTES_KEY` item, the `UserDefaults` keys and the `Documents` files are still there; `Library/Caches/cache/topic-*.htm` are gone.
3. LOT-067 M1: the real `HFR_COMPTES_KEY` decodes (and whether `NSHTTPCookie` decodes with secure coding).
4. Favoris tab: the legacy super-favourites appear in the "Super favoris" section of every category listing their number; open a topic with a legacy draft: "Répondre" shows it.
5. Second launch: no summary.
6. Device locked before the first launch (background launch): `accounts` retried, then imported and listed.
7. No legacy account, log in from the login sheet: the summary (if the global items imported something) shows once the login sheet is gone, not under it.

## Intentional differences from legacy

None in behaviour: legacy had no import. Super-favourites and drafts are matched by number as legacy did.

## Learnings

To copy into AGENTS.md §11 when the lot closes.
- A `KeychainCredentialStore`'s lock is per instance: every writer of the accounts item shares `LiveCredentials.store`, as every small store has one instance per file (Fable round 1 on #720).
- `AccountsModel.retryRestore()` only waits for a restore in progress: a writer that changed the store meanwhile needs `readStoreAgain()`.
