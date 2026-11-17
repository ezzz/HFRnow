# LOT-131 — Blacklist sync with MPStorage

- **Module:** App (`MPStorage/`: `BlocklistSyncPlan`, `BlocklistChangeLog`, `BlocklistSyncModel`, `BlocklistSyncQuestions`; hooks in `MPStorageSyncModel`, `PseudoListManager`, `AppEnvironment`, `RootModel`, `RootNavigationView`, `UserProfileView`)
- **Difficulty / model:** medium (Opus 5.5 author → Fable 5.2 reviewer)
- **Issue:** [#221](https://github.com/ezzz/HFRnow/issues/221)
- **Depends on:** LOT-130 (`MPStorageSyncModel`: state record, `writeConsent`, `edit`, `document(for:)`), LOT-061/072 (`PseudoListStore`, `PseudoNormalizer`), LOT-118 (`PseudoListManager`: the editors, the menu entries, the profile buttons), LOT-062 (`addBlocklistEntry`, `removeBlocklistEntry`, merge), all done.

## Legacy sources
`https://github.com/ezzz/HFRnow` @ `87fe0d1c`.

| Legacy | Behaviour |
|---|---|
| `Classes/BlackList.m:37-47` (`addToBlackList:andSave:`) | while `mpstorage_active`: `addBlackListSynchronous:` first; its failure aborts the local add |
| `Classes/BlackList.m:56-69` (`removeFromBlackList:andSave:`) | same for a removal (`removeBlackListSynchronous:`) |
| `Classes/MPStorage.m:182-200` (`loadBlackListAsynchronous`) | after `initOrResetMP:` (`:121`, `:139`), reads the thread |
| `Classes/MPStorage.m:202-225` (`updateBlackList:`) | **replaces** the active account's list by `data[0].blacklist.list[].username` (`:209`, `setBlackListForActiveCompte:` with an empty array, then one add per remote entry): an empty remote list empties the device's |
| `Classes/MPStorage.m:230-269` (`addBlackListSynchronous:`) | GET, parse, case-insensitive lookup (`lowercaseString`), insert `{createDate, username}` at index 0, save |
| `Classes/MPStorage.m:271-309` (`removeBlackListSynchronous:`) | GET, parse, remove the **last** case-insensitive match, save; returns NO when absent (so the local removal is aborted too) |

## Legacy counterpart (app lots)
- `App/SwiftHFR/MPStorage/BlocklistSyncModel.swift`: `Classes/BlackList.m (addToBlackList:andSave:, removeFromBlackList:andSave:)` and `Classes/MPStorage.m (updateBlackList:, addBlackListSynchronous:, removeBlackListSynchronous:)` @ `87fe0d1c`, GAP-182.
- `App/SwiftHFR/MPStorage/BlocklistSyncPlan.swift`: `Classes/MPStorage.m (updateBlackList:)` @ `87fe0d1c`, GAP-182.
- `App/SwiftHFR/MPStorage/BlocklistSyncQuestions.swift`: `Classes/MPStorage.m (initOrResetMP:fromView:, the creation alert)` @ `87fe0d1c`, GAP-182.

## UX evolutions (app lots)
- **GAP-182** (`a`, ported with changes): local first, merged at each sync, never emptied by an empty remote list; the device's own entries are written to the document.
- **First write asks** (ADR 0013 §7, CHANGELOG-LEGACY row 29, `b·needed`: creating the thread is a write to the forum): the first blocklist change of an account whose state is `unasked` shows « Synchroniser la liste noire de ce compte avec le stockage MP (un message privé sur le forum) ? » (« Synchroniser » / « Garder sur cet appareil »), from the root, or from the profile sheet when the change was made there. Yes → `setEnabled(true, from: .write)`: an existing thread turns the account `on` and merges at once; none → legacy's creation question (`MPStorage.m:91`), also from the root. « Garder sur cet appareil » records `declined` for this account (it covers bookmarks too: one state per account, ADR 0013 §7).

## Behaviour
- **Local first.** Every blocklist write still goes through `PseudoListManager` and the one `PseudoListStore` (LOT-118); the change is then given to the MPStorage side. A failed or unconfirmed forum write never undoes it (legacy aborted the local change, `BlackList.m:39, 57`).
- **Change log** (`BlocklistChangeLog`, one per account session, `AppEnvironment.blocklistChanges`): the manager **holds** a change before its local write and releases it after (kept when the list changed, withdrawn on a no-op or a failure), then streams it in order to `BlocklistSyncModel.run()` (the root's `.task`). Held changes are what the document may not carry yet; they are forgotten once the document shown (`pending ?? base`) carries them, or when the account does not sync. Memory only.
- **Per change** (`handle`): `writeConsent(for: .ignoreList)` — `.sync` → one `MPStorageSyncModel.edit(.ignoreList)` (LOT-130: local edit of the copy, then `sync`: LOT-052's session check, merge-write-read back, success only on HFR's own confirmation, `unconfirmed` kept pending and never re-sent blindly); a removal removes every username of the document with that comparison form (case variants, format characters). `.ask` → the question above. `.deviceOnly` (declined, off, unreadable state, function off) → nothing, the change is withdrawn.
- **Reconciliation** (`reconcile`, from `MPStorageSyncModel.afterSync`: after every successful call that found the thread and did not end in an edit that changed nothing — start, resync, switch-on, creation, edit), only while `document(for: .ignoreList)` is non-nil. The "before" document is the device copy: a write made before `start()` (from the reader or a profile) loads it first, so a remote removal is never mistaken for a first read. `BlocklistSyncPlan.make(local:before:after:held:)`, on `PseudoNormalizer.comparisonForm`, over the writable `0.1` entry:
  - remote additions (in the document read now, not on the device) are blocked on the device, except a pseudo the device holds a removal of;
  - remote removals (in the document shown before the call, gone now) are unblocked on the device **only when the document read now still lists someone, or carries a tombstone for that pseudo**: an emptied list is never "remove everything" (audit E-2, the legacy wipe); a held addition of the same pseudo wins;
  - device entries the document lacks (and not just removed remotely) are written to it, and so are held removals the document still lists; one `edit` for all; a pseudo the forum cannot store (outside the BMP, LOT-062) is skipped and stays on the device.
  - The reader's copy (`PseudoListsSnapshot`) is refreshed after a local change. The reconciliation's own write triggers a sync, which reconciles again inside it with its own diff (no diff is dropped); it ends because an edit that changes nothing triggers no sync and no merge (decided per call, never by model state: calls overlap).
- **Release of held changes**: per pseudo, on its **last** held change only, once the document shown carries it; an un-block then re-block keeps both until the re-block is in the document.
- No HFR request of its own: every forum access is LOT-130's `MPStorageSync` over LOT-052's transport.

## Edge cases
- Empty remote list, device list non-empty: nothing removed on the device; the device's entries are written back (test).
- The removed pseudo was the last one, removed by SwiftHFR on another device: tombstones are off by default (`MPStorageStamp.recordsTombstones`), so the removal is not taken and the pseudo is written back. Known limit, the price of E-2; another client that writes tombstones is followed.
- A removal not yet carried by the document when a sync runs (the consumer has not taken it, or an edit failed with `notLoaded`): held, so not imported back, and written at the reconciliation.
- Relaunch with a held change not yet written: additions come back through the union; a removal made while `on` was written in the copy's `pending` by `edit` (LOT-130) and survives; a removal made while `unasked` / `off` and then switched on is lost (the pseudo comes back from the document), as legacy's replace would have.
- The consumer `.task` ends with the root (session change): the new session gets a new log.
- Several windows (LOT-146): each window builds its own session environment, so its own log, stream and model; the **held** changes are the account's, shared by every window (`HeldBlocklistChanges.shared(for:)`, keyed by `AccountKey`), so a removal held in one window is not imported back by another window's merge. Each window's `MPStorageSyncModel` has its own sync queue over the one device copy (LOT-130/146 territory, not changed here).
- Unreadable device list (LOT-061): it reads empty and refuses writes, so the plan pushes nothing from it and its local writes fail without effect.
- Function « Liste noire partagée » off (#859, while the experimental option is on): neither read nor written; nothing deleted.

## Fixtures
None: no new HFR state. The tests drive LOT-130's scripted `FakeMPStorageRemote` (no `HFRSession` exists: no request can leave the process) with synthetic `0.1` documents; the document shape is LOT-052/062's (HFR-PROTOCOL §3.3). No pending capture.

## Tests
`App/SwiftHFRTests/MPStorage/BlocklistSyncTests.swift`
- `BlocklistSyncPlanTests`: empty remote never empties the local list; remote removal taken while the list holds entries; last entry removed with a tombstone; first read unites both lists; case and format characters match; a held removal is written and never imported back; a held addition wins over a remote removal; a non-BMP pseudo stays on the device.
- `BlocklistSyncModelTests`: start merges instead of replacing; empty remote list never empties the local one; another client's removal taken; local addition written while on (and held until then); local removal removes every case and format-character variant in one write; a write before any start merges from the stored copy; an un-block then re-block stays blocked on both sides; a missing thread merges nothing from the stored copy; a removal held in another window is not imported back; every window of an account shares its held changes; an edit that changes nothing starts no merge; a removal not yet written is not imported back by a sync; first write of an `unasked` account asks and sends nothing; yes with a thread turns on and writes the device list; yes without a thread asks the creation question from the write; no keeps the list on the device; `declined` / `off` keep writes on the device; the function off neither reads nor writes.
- The scripted forum merges on save as LOT-052's transport does (`FakeMPStorageRemote.merges`, LOT-131's tests only).
- Shown failing on Linux (the SwiftUI-free part compiled against HFRKit) with each guard reverted: the empty-list guard, the post-sync hook, the hold before the write, the union push, the question, the write per change, the copy loaded before a write, the per-pseudo release, the variant lookup, the missing-thread check, the no-merge-after-a-no-op.

## Intentional differences from legacy
1. Remote load merges (union, removals only with evidence) instead of replacing (`MPStorage.m:209`).
2. Local first: a forum failure no longer aborts the local change (`BlackList.m:39, 57`).
3. The device's entries are written to the document (legacy's reload dropped them).
4. A removal removes every case variant (legacy removed the last match only, `MPStorage.m:290-301`).
5. The question at the first write of an undecided account (ADR 0013 §7).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A merge that takes removals from a diff must refuse the diff of an emptied list: "absent" is not "deleted" without a tombstone.
- A change made locally and streamed to a consumer must be visible to a concurrent merge **before** the local write, or the merge re-imports what the user just removed.
