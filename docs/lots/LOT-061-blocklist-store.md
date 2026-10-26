# LOT-061 — Blocklist / allowlist store

- **Module:** HFRStorage
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [E §2.3, §7.2-7.6, §8 (E-2)](../audit/E-storage-vendors.md).

| Legacy | What it gives the store |
|---|---|
| `Classes/BlackList.m:37-47, 56-69` | add / remove on the active account's list; entry shape `{word, alias, mode}` |
| `Classes/BlackList.m:49-54, 71-81` | the allowlist ("whiteList") is global, add / remove |
| `Classes/BlackList.m:110-128` | `isBL`; `isWL` is false for a blocked pseudo |
| `Classes/BlackList.m:130-143` | matching: zero-width space removed, then `lowercaseString` |
| `Classes/BlackList.m:163-203` | `save` / `load` of `blackListDico.plist` and `whiteList.plist`; `load` returns early without a current pseudo, so a later `save` overwrites the files with empty lists (E §7.2) |
| `Classes/BlackList.m:187-192` | v0 `blackList.plist` migration that writes the wrong file (E §7.3) |
| `Classes/BlackList.m:93, 102` | list keyed by current pseudo for reads and by the main account's display name for `setBlackListForActiveCompte` (E §7.4) |
| `Classes/BlackList.m:39, 57` | `mpstorage_active` makes add / remove sync-first (E §7.6): not in this lot |

## Behaviour
Code in `Sources/HFRStorage/PseudoLists/`, tests in `Tests/HFRStorageTests/PseudoLists/`. Swift names say "blocklist"/"allowlist" (SwiftLint `inclusive_language`).

- **`PseudoNormalizer`**: `normalize` removes U+200B and lower-cases; `matches` compares normal forms. No trimming (legacy did not; MPStorage's `dicMPStorage_postid` key additionally trims and is a different store).
- **`PseudoListStore`** (actor): `block`, `unblock`, `replaceBlocklist(with:account:)`, `allow`, `disallow`, `blocklist(for:)`, `allowlist()`, `isBlocked`, `isAllowed`. Entries keep insertion order and the pseudo as the user typed it; adding an existing pseudo (any case, any ZWSP) returns false and does not save. `isAllowed` is false for a blocked pseudo, as in legacy.
- **Accounts**: blocklists are keyed by the account identifier passed by the caller (`Account.id`, the `md_user` pseudo), normalised so `Alice` and `alice` share a list. The caller always passes the account the list belongs to: no "current account" state lives here, which removes legacy E §7.4 and the load-before-login order dependence.
- **One document, one atomic file**: `PseudoListDocument { version, blocklists, allowlist }`, encoded as JSON, written with `Data.write(options: .atomic)`. Entries keep the legacy plist keys (`word`, `alias`, `mode`) so the LOT-067 importer is a plain mapping.
- **Persistence protocol** `PseudoListPersistence` (`load`, `save`, `quarantineUnreadableData`): `FilePseudoListPersistence` and `InMemoryPseudoListPersistence`.
- **Guard "never overwrite with empty after a failed load" (E-2)**: the first call loads the document. When that fails (unreadable, undecodable, empty file, or `version` newer than this code) reads answer "empty" and **every write throws** `PseudoListError.loadFailed` / `.unsupportedVersion`; nothing is saved. Ways out: `reload()` (data readable again) or `discardUnreadableData()`, which moves a file to `<name>.corrupt` (never deletes; an earlier `.corrupt` file is renamed with a unique suffix) and starts from empty lists. The app decides, ideally after asking the user.
- **Memory never gets ahead of the disk**: a mutation is applied to a copy, persisted, then published; a failed save throws `saveFailed` and leaves state unchanged.

## Edge cases
- Pseudos that are empty once zero-width spaces are removed are rejected (`emptyPseudo`) on both lists; `replaceBlocklist` drops them silently (the list comes from a remote document).
- A missing file is a normal first launch (empty lists), not a failure.
- Several concurrent `block` calls are serialised by the actor; all are kept.
- Removing the last entry of an account removes its key from the document.
- Unknown JSON keys of a future version are not preserved because such a document is never written (read-only guard).

## Fixtures
None: synthetic documents and temp directories. The three legacy plists (`blackListDico.plist`, `whiteList.plist`, `blackList.plist`) are LOT-067's fixtures.

## Intentional differences from legacy
- No v0 `blackList.plist` migration here (it was buggy, E §7.3); LOT-067 reads the three legacy files without touching them.
- No `mpstorage_active` coupling: syncing is the app's orchestration (LOT-052), which calls `block` after the server accepted, or `replaceBlocklist` after a successful remote load (legacy `MPStorage.m:208-215`).
- Plist (`NSDictionary.writeToFile`) becomes JSON; the legacy `kTerminator` mode stays 0.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A store that persists in-memory state must model "not loaded" and "load failed" explicitly; "empty" is a valid stored value and must not be the fallback of a failure.
