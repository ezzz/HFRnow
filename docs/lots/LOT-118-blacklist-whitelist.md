# LOT-118 — Blacklist / whitelist management

- **Module:** App
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** #209

## Legacy sources
All @ `2440d79`:
- `Classes/BlackListTableViewController.m`, `Classes/WhiteListTableViewController.m`: sorted list (`Sort_BL_Comparer`, case-insensitive), manual add (`addPseudoToList:`), delete row (`commitEditingStyle`). Titles "Liste noire" / "Love list".
- `HFRswift/Swift/AppSettingsView.swift`: the "Sujets" rows (`:408-419`), `ProfileFilterListKind` (`:549-579`), `ProfileFilterListEditorView` (`:581-700`).
- `HFRswift/Swift/Common.swift:885-989`: `ObjCProfileFilterListManager` (add, remove, `toggleBlacklist`, `toggleWhitelist`: the sentences).
- `HFRswift/Swift/MessagesView.swift`: the `.blacklist` / `.whitelist` entries of the popup (`:1683-1717`), the avatar and profile toggles (`:3652-3694`, each ends with `loadPage(page)`).

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `Settings/PseudoListManager.swift` | `Common.swift` `ObjCProfileFilterListManager` |
| `Settings/PseudoListEditorModel.swift`, `PseudoListEditorView.swift` | `AppSettingsView.swift` `ProfileFilterListEditorView`; the two table controllers |
| `Reader/Actions/PseudoListActionHandlers.swift` | `MessagesView.swift` `.blacklist` / `.whitelist` entries |
| `Profile/UserProfileModel.swift`, `UserProfileView.swift` (buttons) | `MessagesView.swift` `toggleProfileBlacklist` / `toggleProfileWhitelist` |
| `Settings/TopicsSettingsModel.swift` (`hidesBlocklisted`) | `AppSettingsView.swift:100,408` `blacklist_hide_pseudo` |

## UX evolutions (app lots)
- Profile: the sheet stays open after a toggle and shows the sentence under the buttons (legacy dismissed the sheet, then `loadPage`); the reader rebuilds its page when the sheet closes. GAP-209, class `b`.
- Message menu: the page on screen is rebuilt from the refreshed snapshot (`applyDisplaySettings()`), without legacy's page request. Same visible result, no network. Not a UX difference.
- An unreadable list file shows "illisibles, non modifiées" and a "Réessayer" button instead of an empty list. GAP-209, class `b·needed` (the empty list was the legacy wipe, audit E §7.2).

## Behaviour
- **One store.** Every write goes through `PseudoListsSnapshot.liveStore` (LOT-117: one actor per file). `PseudoListManager` wraps it for the current account (`AppEnvironment.reader.pseudoLists`); the snapshot is refreshed after each write.
- **Normalisation is the store's** (`PseudoNormalizer`, LOT-061/072): pseudos cleaned (zero-width characters, spaces), case kept, compared lower-cased. The editor trims the field first; messages show the cleaned pseudo.
- **Editors** (Réglages › Sujets): "Liste noire" (per account) and "Liste blanche" (global). Sorted case-insensitively as legacy; add field + "Ajouter"; swipe or "Modifier" to remove; already listed → "X est déjà dans la liste." Logged out, the blocklist editor asks for an account (the allowlist works).
- **"Masquer les pseudos blacklistés"** (`blacklist_hide_pseudo`) is the third row of legacy's blocklist group; the setting already existed (`SettingKey.hideBlocklistedPosts`).
- **Menu entries** "Blacklist" / "Whitelist" (author menu; LOT-087 policy unchanged) toggle the author: in the list → removed, else added, with legacy's sentences ("BIM! … ajouté à la liste noire", "OH NOES ! … supprimé de la love list", …). A failed write says so ("Whitelist impossible" for the allowlist, as legacy's caller). The blocklist entry is hidden logged out.
- **Profile** (LOT-116): two buttons "Ajouter à / Retirer de la liste noire" and "… la love list", with the current state.
- **The reader** shows a change at once: `PseudoListsSnapshot` is refreshed by the write, then `applyDisplaySettings()` rebuilds the shown page (LOT-117 note).
- **Avatar menu (#595).** Its PR registers Profil and MP only. The two entries need no change there: `PseudoListActionHandler.pair` registers the `.blocklist` / `.allowlist` handlers in `installMenuActions`, and the policy already lists them for `source: .avatar`. Whichever PR merges second has a trivial textual conflict in `installMenuActions` only.
- **iCloud (LOT-172).** The allowlist is written with `allow` / `disallow`, which signal `allowlistChanges()`: the iCloud copy follows. The blocklist stays out of iCloud (MPStorage carries it, LOT-067).

## Edge cases
- Removing the last entry saves an empty list (the key is dropped); a file that could not be read is never saved: every write throws until it is readable again (tested with a persistence whose `load` throws: zero saves).
- A pseudo empty once cleaned does nothing (menu) or leaves "Ajouter" disabled (editor).
- A blocked and allowlisted pseudo: the allowlist toggle looks at the allowlist itself (legacy's `isWhitelisted` is the reader's "allowed and not blocked" rule), so it removes the entry instead of failing to add a duplicate.
- The profile page names the pseudo; before it loads the buttons are hidden.

## Fixtures
None: no HFR page is read or written (the lists are local; MPStorage sync is LOT-067).

## Intentional differences from legacy
1. Writes refused on an unreadable file (see above).
2. Toggle of the allowlist as described under Edge cases.
3. Duplicates are detected by the store's rule (`PseudoNormalizer.comparisonForm`), whatever the case.

## Mac check
Light, dark, Dynamic Type XL: both editors (add, duplicate, swipe, last entry, logged out); author menu (reader, avatar once #595 lands) toggles and the page shows or unshows the blocked stub at once; profile buttons; "Masquer les pseudos blacklistés" on an open reader.

## Learnings
- A toggle that must show on the page already open: refresh the snapshot in the write path, then `applyDisplaySettings()`; no reload.
