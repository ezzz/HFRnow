# LOT-130 — MPStorage sync service and settings

- **Module:** HFRStorage (`MPStorage/`: the per-account state record and the device copy), HFRClient (`MPStorage/MPStorageSync.swift`: the sync loop), App (`MPStorage/`: the model, the "Stockage MP" settings section, the MP list decoration)
- **Difficulty / model:** difficult (Opus 5.5 author → Fable 5.1 reviewer)
- **Issue:** [#220](https://github.com/ezzz/HFRnow/issues/220) · implements [ADR 0013](../adr/0013-storage-tiers.md) §2, §4 and §7 for MPStorage
- **Depends on:** LOT-052 (`MPStorageTransport`), LOT-062 (`MPStorageMerge`, document edits), LOT-060 (`SettingsStore`), LOT-119 (Réglages), LOT-081 (accounts), LOT-126 (MP list), LOT-172 (`SyncedSettingsStore`, `AccountKey`), all done.
- **Followed by:** LOT-131 (blacklist sync, #221) and LOT-132 (bookmarks, #222) call this lot's edit and consent API; the reader's MP-flag write is a follow-up (see "Out of scope").

## Legacy sources
`https://github.com/ezzz/HFRnow` @ `87fe0d1c` (AGENTS.md §2). Line numbers of `Classes/MPStorage.m` are the same at `2440d79` (no change between them).

| Legacy | Behaviour | Replaced by |
|---|---|---|
| `HFRswift/Swift/AppSettingsView.swift:112-113` | `@AppStorage("mpstorage_active")` (default false), `@AppStorage("mpstorage_last_rw")` (default `-`) | per-account `MPStorageSyncRecord` (ADR 0013 §7); per-account last sync in the device copy |
| `AppSettingsView.swift:233-256` (`handleMPStorageToggle`) | switching on needs a login ("Vous devez être identifié sur le forum pour activer le MP storage."), then `initOrResetMP`; a failure switches off with "Échec de l'initialisation du MP storage." | `MPStorageSyncModel.setEnabled(true)` |
| `AppSettingsView.swift:258-270` (`reloadMPStorage`) | "Resynchroniser MP storage": `initOrResetMP` again | `MPStorageSyncModel.resync()` |
| `AppSettingsView.swift:534-545` (`mpStorageSection`) | section "Stockage MP": toggle "Activer le stockage MP", then "Dernier accès" and "Resynchroniser MP storage" while on | `MPStorageSettingsSection` |
| `Classes/MPStorage.m:81-143` (`initOrResetMP:fromView:`) | while on: cached `post` per pseudo (`dicMPStorage_postid`), else search; not found → "Le MP de stockage n'a pas été trouvé. Voulez-vous qu'il soit créé ?" (OK creates, Cancel switches off); then loads the blacklist | `MPStorageSync.detect()` / `sync()` / `create()`; the question moves to the first write (ADR 0013 §7) |
| `MPStorage.m:147-176` (`reloadMPStorageAsynchronous…`) | reload (skipped after a failed save), `updateLastSucessAcessDate` on success | `MPStorageSync.sync()` (pending edits pushed first, never skipped) |
| `MPStorage.m:969-978` (`updateLastSucessAcessDate`) | `dd-MM-yyyy HH:mm:ss` in a volatile `registerDefaults:` value | `MPStorageSyncCopy.lastSync`, persisted (ADR 0013 §4) |
| `MPStorage.m:527-545` (`getUrlFlagForTopidId:`, URL at `:539`), `:547-565` (`getPageFlagForTopidId:`) | the flag of thread `post`: `forum2.php?config=hfr.inc&cat=prive&post=<post>&page=<page>&p=<p>&sondage=0&owntopic=0&trash=0&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0#<href>`; page `-1` when none | `MPStorageSync.flag(forThread:in:)` (the link waits for the reader's flag write, Out of scope) |
| `HFRswift/Swift/MPListView.swift:354-373` (`topicsDecoratedWithMPStorageFlags`), `:376-377` | while on: group rows ("Interlocuteurs multiples") with a flag get the flag URL, its page (else the URL's page, else the row's), max page at least that page | `MessageListModel.flag(for:)` |
| `MPListView.swift:775-786` (`interlocutorLabel`) | a flagged group row reads `⚑ <page> / <max>` instead of "Interlocuteurs multiples" | `MessageRowView` |
| `Classes/HFRMPViewController.m:225-262` (`didSelectRowAtIndexPath:`), `Common.swift:2740` | while on, a group row opens its flag URL, else the latest message | not yet: comes with the reader's flag write (Out of scope) |
| `Classes/HFRMPViewController.m:32-36`, `Classes/MultisManager.m:85, 104`, `Classes/HFRplusAppDelegate.m:155-156, 508-509` | reload at each MP list load, at account change and at launch | `MPStorageSyncModel.start()` (account change rebuilds the model) |

## Legacy counterpart (app lots)
- `App/SwiftHFR/MPStorage/MPStorageSyncModel.swift`: `HFRswift/Swift/AppSettingsView.swift (handleMPStorageToggle, reloadMPStorage)` and `Classes/MPStorage.m (initOrResetMP:)` @ `87fe0d1c`, GAP-181.
- `App/SwiftHFR/MPStorage/MPStorageSettingsSection.swift`: `HFRswift/Swift/AppSettingsView.swift (mpStorageSection)` @ `87fe0d1c`, GAP-181, GAP-140.
- `App/SwiftHFR/Messages/MessageListModel.swift`, `MessageRowView.swift`: `HFRswift/Swift/MPListView.swift (topicsDecoratedWithMPStorageFlags, interlocutorLabel)` and `Classes/HFRMPViewController.m (didSelectRowAtIndexPath:)` @ `87fe0d1c`, GAP-119.

## UX evolutions (app lots)
- **GAP-181** (`b·needed`, ADR 0013 §7, operator 2026-10-28): one state per HFR account (`unasked`, `on`, `declined`, `off`) instead of one app-wide switch; on by itself when the account already has a storage thread; never a thread created without asking. The section shows the **current** account's state: switching account switches the section (the other accounts keep theirs).
- **GAP-119** (`a`, ported with changes): the flag decoration, only while the account's state is `on`; the row still opens at its latest message until SwiftHFR moves the flag itself (Out of scope). A stale or missing document never blocks the list: the rows simply show no flag.
- "Dernier accès" survives a relaunch (legacy lost it, `MPStorage.m:969-978`): CHANGELOG-LEGACY row 29's lot, recorded with LOT-060.

## Behaviour

### The state record (HFRStorage, `MPStorageSyncStateStore`)
- Key `mpstorage.<account key>` (LOT-172's `AccountKey`, ADR 0013 §7), value a JSON string `{"decidedAt":"<ISO 8601>","state":"<state>"}` (keys sorted; #859 adds `disabled`, below), in the app's `SettingsStore`: the `UserDefaults` mirror, which `SyncedSettingsStore` copies to iCloud once the key is registered (below).
- Optional `disabled` (#859): the sorted names of the functions switched off (`blacklist`, `bookmarks`, `mpFlags`); absent or empty = every function on (legacy parity), a name this build does not know is kept, and it syncs through iCloud KVS with the state. **Forward-compat limit:** a build without #859 ignores `disabled` and keeps syncing every function, and its master toggle rewrites `{state, decidedAt}`, erasing the list on every device; builds already released cannot be fixed. `setFunction(_:enabled:for:)` changes one name and keeps state and date; `set(_:for:at:)` keeps the list. App: `MPStorageSyncModel.isEnabled(_:)` gates `flag(for:)`, `edit(_:_:)`, `writeConsent(for:)` and `document(for:)` (the read accessor LOT-131/132 use); an edit queued before the switch-off is still written at the next sync (the member's earlier intent is never lost), and the section stays in the document.
- `record(for:)`: absent → `unasked`, `decidedAt` nil; a value this build cannot read (another shape, an unknown state written by a newer build) → `nil`, **unreadable**: no sync, no automatic change; only the member's explicit choice in Réglages overwrites it.
- `set(_:for:at:)` writes the state and the date; an empty account key is refused (nothing written).
- `applyLegacySwitch(_:accounts:)`: LOT-067's `LegacyMPStorageSwitch` once (ADR 0013 §7): `.active` → every listed account whose record is `unasked` becomes `on`; `.inactive` and `.notRead` change nothing. The import is not wired in the app yet (LOT-067 wiring); this is the function it calls.
- `SyncedSettingsStore.syncKeys(_:)` (LOT-172 addition): registers keys at run time (the per-account records: accounts come and go) and applies the initial-sync rule to them (cloud wins, else pushed). A key longer than `SyncedListsStore.maximumKeyLength` is not registered: that account's record stays on the device. The app's settings store is still `UserDefaultsSettingsStore` until #447 wires `SyncedSettingsStore`: #447 calls `syncKeys` with `MPStorageSyncStateStore.keys(for:)` of the accounts.

### The device copy (HFRStorage, `MPStorageCopyStore`)
One device-only file (`Application Support/MPStorage/copies.json`, `SmallStoreDocument` version 1), keyed by account key: `post` (the thread id, legacy `dicMPStorage_postid`), `base` (the document text last read: LOT-062's merge base), `pending` (the text with the local edits not yet written, nil when none), `lastSync` (the last successful read or write), `lastSearch` (the last search that found no thread). The texts hold pseudos: device-only, never in iCloud (ADR 0013 appendix B). Unreadable or newer file: reads answer nothing, writes throw (LOT-064 rule).

### The sync loop (HFRClient, `MPStorageSync`)
An actor per account over an `MPStorageRemote` (`LiveMPStorageRemote` = LOT-052's transport in the account's `HFRSession`) and an `MPStorageSyncPersistence` (the app's adapter over `MPStorageCopyStore`). It never reads the state record: the app calls it only when the record allows it.

| Call | What it does |
|---|---|
| `copy()` | the stored copy (post, base, pending, dates); `document` = `pending ?? base`, decoded |
| `detect(now:)` | read-only (ADR 0013 §7, "found → on"): the cached `post` is read; a stale one (`notAddressed`) is forgotten and the list searched (`findThread`); found → the document becomes the base, `.found`; the list ends without it → `lastSearch = now`, `.notFound`. `searchLimitReached` and every other error → `.failed`, nothing stored |
| `sync(now:)` | reads the cached thread, or, when it is unknown or `notAddressed` (deleted, another account's), the thread the MP list shows (`.noThread` when none: nothing written, the cached id dropped, the edits kept). With no pending edit: base = the document read. With a pending edit: `save(pending, base: <stored base>, at:)` (LOT-052 merge-write-read back, the base being the copy the edits were made on); success → base = the copy read back, pending cleared. `notVerified(readBack: nil)` (a concurrent write) → saved again once. Any failure keeps `pending` and `base` as they were (a failed sync never undoes a local edit, ADR 0013 §2, §4); `posting(.unconfirmed)` keeps `pending` too: the next save re-reads, and the merge writes nothing when the edit is already stored. A thread deleted between the read and the write (`posting(.formUnavailable)`) is a failure; the next sync's read finds it gone. `lastSync = now` on success only |
| `create(now:)` | the member agreed: `create(stamp:)` (LOT-052: finds first, never a second thread); then `sync` when edits are pending |
| `edit(_:)` | local first (ADR 0013 §2): applies a LOT-062 mutation to `pending ?? base`, stores the result as `pending`; `false` (nothing changed) stores nothing. Throws `notLoaded` without a base (never read), and the LOT-062 refusals (`noWritableEntry`, non-BMP) before storing anything. The app then calls `sync` |
| `flag(forThread:in:)` | the `mpFlags` item of thread `post` in a document's writable entry (`MPStorage.m:527-565`), the first with that number; `document()` decodes the copy shown (`pending ?? base`) |

One call at a time: each call waits for the one queued before it (an actor alone would interleave them at every `await`), so an edit never lands between a sync's read and its write. A call saves the copy before it returns or throws: a failure still keeps the thread id it found; a copy that cannot be saved is `storage`.

### The app (`MPStorageSyncModel`, `@MainActor @Observable`, one per account session)
Built by `RootModel` with the current account (nil logged out, LOT-081: a new account is a new model, so no account's state or document is ever shown under another).
- `start()` (Messages tab and Réglages appearing, once per model; after a network failure it runs again at the next appearance, as legacy reloaded at each MP list load, `HFRMPViewController.m:32-36`, but never after a search that hit its limit or found no thread, which would walk the MP list again at each appearance; the list's own load never waits for it): the copy is shown, then, logged in, record `on` → `sync`; `unasked`, unless the last search that found nothing is younger than `searchInterval` (24 h: the search walks the MP list) → `detect`, `.found` → record `on` (decided now) and the flags appear; `declined`, `off`, unreadable → nothing.
- `setEnabled(true)` (Réglages): needs a session ("Connectez-vous pour activer le stockage MP."); `detect` (the cached thread, else the list) `.found` → `on`, then `sync` (edits already pending are written); not found → `asksCreation`, the question "Le MP de stockage n'a pas été trouvé. Voulez-vous qu'il soit créé ?" (legacy sentence, `MPStorage.m:91`); `answerCreation(true)` → `create`, `on` when it succeeds, else the record is unchanged and the reason shown; `answerCreation(false)` → `declined`. `setEnabled(false)` → `off`: nothing is deleted, on the forum or on the device.
- `resync()` → `sync` (only while `on`).
- `writeConsent()` for LOT-131/132, before the first bookmark or blacklist write: `.sync` (record `on`), `.deviceOnly` (`declined`, `off`, unreadable), `.ask` (`unasked`: the caller asks, then calls `setEnabled(true)`, which finds an existing thread or asks to create one, or records `declined` through `answerCreation(false)`). `edit(_:)` applies a LOT-062 edit and syncs, only while `on`.
- `status`: `idle`, `working`, `failed(<French message>)`; `lastSync`; `threadMissing` after a sync that found no thread ("Le MP de stockage est introuvable."). Messages never hold document text or pseudos: network, search limit, unreadable forum document, unconfirmed write, login, refused write, unreadable device copy, and a generic failure.
- `flag(for:)`: a group thread's flag, only while the record is `on` and the flag has a page above 0.

### Settings ("Stockage MP", after "Messages")
Logged out: the section says "Connectez-vous pour utiliser le stockage MP." and has no toggle. Logged in: toggle "Activer le stockage MP" (on = record `on`), the state in words under it ("Activé pour ce compte", "Désactivé pour ce compte", "Refusé pour ce compte", "Pas encore choisi pour ce compte", "État enregistré illisible"), then while on "Dernier accès" (date, or "Jamais") and the button "Resynchroniser" (disabled while working), a progress row while working, and the failure message in red. The creation question is an alert ("Créer", "Annuler").

### MP list decoration
While the record is `on`, a group row (`PrivateMessageThread.isGroup`) whose thread has a flag reads `⚑ <page> / <max>` instead of "Interlocuteurs multiples" (`MPListView.swift:775-786`), max = the larger of the row's page count and the flag page (`:368`). A one-to-one row is never decorated (`MPListView.swift:359`). A flag without a page above 0 is skipped (legacy's URL would hold `(null)`). The row still opens at its latest message: legacy opened the flag's URL (`MPStorage.m:539`) because it also moved the flag while reading; SwiftHFR does not yet (Out of scope), and a flag nobody moves would open an old page forever after the in-place update (Fable review, round 1). The list never waits for MPStorage: the decoration reads the copy in memory, and appears when `start()` has read it.

## Edge cases
- Two devices: the record syncs through iCloud (once #447 wires it); the document merges (LOT-062).
- A thread deleted from another device while `on`: `sync` searches again; not found → `.noThread`, the section says "Le MP de stockage est introuvable."; switching off then on searches again and asks before creating one.
- `searchLimitReached` (more than 50 MP pages without the thread): `failed`, never "not found", so nothing is ever created from it (LOT-052).
- The device copy unreadable (or written by a newer build): "La copie locale du stockage MP est illisible.", nothing is synced (nothing could be stored) and nothing overwrites it.
- An edit while a sync runs: queued after it, never inside its read-merge-write.
- Account removed: its record and copy stay (ADR 0013: nothing deleted); logging in again finds them.

## Out of scope (follow-ups)
- **Writing MP flags from the reader and opening a group row at its flag** (`MessagesView.swift:3582-3606`, `OnlineMessagesTableViewController.m:1797-1811`, `HFRMPViewController.m:228-251`, link `MPStorage.m:539` @ `87fe0d1c`: after a group MP page loads, the flag moves forward to the page's last message; a tap opens the flag). They ship together: a per-page write to the forum needs the reader's page and anchor plumbing and its own review; follow-up issue (decision of cloud/orch). Until then the label shows the flags other clients write (DTCloud, legacy iOS).
- LOT-131 and LOT-132: the blacklist and bookmark edits, with the consent question in their screens.
- #447: `SyncedSettingsStore` in the app and `syncKeys` for the records; LOT-067 wiring: `applyLegacySwitch`.

## Fixtures
No new capture. The engine tests use LOT-052's `MPStorageCapture` text (`R60b`'s `content_form`) and LOT-062-style synthetic documents; `MPStorageSyncTests` drives a scripted `MPStorageRemote`, so no request can leave the process (HFRSession is never built there). Every HFR fact used here is LOT-052's (HFR-PROTOCOL §3.3, §6c LOT-052) or legacy code cited above.

## Tests
- HFRStorageTests: `MPStorageSyncStateStoreTests` (absent = unasked, round trip, unreadable value, unknown state, empty key refused, key form, legacy switch), `MPStorageCopyStoreTests` (per account, unreadable file refuses writes, newer version), `SyncedSettingsStoreSyncKeysTests` (registered key pushed, cloud wins, too long refused, server change applied).
- HFRClientTests: `MPStorageSyncTests` (detection: cached thread, stale thread searched, another read failure keeps it without searching, not found dated, search limit is a failure, pending base kept; sync: no edit, pending written on the stored base and cleared, four failures keep the edits, `notVerified` merged once more, a second one reported, an unreadable read-back not written again, no thread, thread id kept after a failed read, unsaved copy; creation: new thread, then pending edits, failure changes nothing; edits: local first, built on each other, no-op, before any read, refused; an edit queued behind a sync in flight; flag lookup in the `0.1` entry only). The forum side is a scripted `MPStorageRemote`: no session exists, so no request can leave the process.
- App (`App/SwiftHFRTests/MPStorage/`): `MPStorageSyncModelTests` (start per state, detection turns `on`, one search per day, start once, a start that failed on the network runs again, a search at its limit and a missing thread are not run again at each appearance, resync only while on, logged out, unreadable state left alone; toggle on with and without thread, decline for this account only, failed creation, off deletes nothing, logged out, missing thread, network failure; consent per state; edit only while on; flags only on group rows while on, flag without page; state in words), `MPStorageFlagTests` (label, opening still at the latest message, no label off or without a page). Their SwiftUI-free part (the model, the copy adapter) also compiled and passed on Linux against HFRKit.

## Intentional differences from legacy
1. Per-account state, on by itself when a thread exists, the creation question moved to the first write (ADR 0013 §7; CHANGELOG-LEGACY row 29).
2. Edits are local first and merged on the next sync; a failed save no longer blocks reloads (`MPStorage.m:156-167` skipped every reload after one failed save, forever in that process).
3. "Dernier accès" is persisted and per account.
4. Cancelling the creation question records `declined` for that account instead of switching off the app-wide setting.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- An actor serialises calls only between suspension points: a read-merge-write that awaits the forum needs its own queue, or an edit made during the read is saved over.
- Porting a read of shared state (an MP flag) without its write freezes it: a position nobody moves any more must not drive navigation.
