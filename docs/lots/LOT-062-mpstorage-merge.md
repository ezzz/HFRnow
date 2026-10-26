# LOT-062 — MPStorage document edits, write guards and three-way merge

- **Module:** HFRModels (pure value logic, usable by `HFRClient` for LOT-052)
- **Difficulty / model:** medium (Opus → Fable)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [D §2.10](../audit/D-posting.md), [E §2.6, E-3](../audit/E-storage-vendors.md); [redface2 comparison](../research/redface2-comparison.md) X8, X9, E23, E24; open question Q-6 ([audit README](../audit/README.md)).

| Legacy | Behaviour |
|---|---|
| `Classes/MPStorage.m:230-268` | add a blacklisted pseudo: case-insensitive presence check (`:250`), insert at index 0 with `createDate`, root `lastUpdate`/`sourceName` only (`:259-262`) |
| `Classes/MPStorage.m:271-310` | remove a pseudo (`:293`, `:301`); no metadata update |
| `Classes/MPStorage.m:313-357, 359-400` | add/remove a bookmark, matched on `numreponse` only (`:333`, `:381`) |
| `Classes/MPStorage.m:463-525` | upsert a flag (remove the same `post`, insert at 0, `:472-487`); remove a flag (`:507-515`) |
| `Classes/MPStorage.m:26` | `MP_SOURCE_NAME = "iOS"` |
| `Classes/MPStorage.m:905-931` | whole-document write, last writer wins, `lastUpdate` written but never compared |

## Behaviour
Built on the LOT-013 types. Every function is pure and `Sendable`; no I/O.

**Edits** (`MPStorageDocument+Mutations.swift`): `addBlocklistEntry`, `removeBlocklistEntry`, `addBookmark`, `removeBookmark`, `upsertMPFlag`, `removeMPFlag`, `pruneTombstones`. They:

1. edit only the **writable entry**, the first `data` entry whose `version` is `0.1`; none → `MPStorageError.noWritableEntry`, document untouched (E23: never rewrite an unknown version blindly);
2. match items by `storageKey`: pseudo lower-cased (legacy `:250`), bookmark `cat-post-numreponse` (E18, wider than legacy's `numreponse`), flag `post`;
3. insert at the top like legacy; adding an existing pseudo or bookmark is a no-op (`false`), upserting a flag replaces it and moves it first, but upserting a flag identical to the stored one is a no-op (legacy moved it first; a reorder alone is not something the merge carries, since it keeps the forum's order); removing removes every item with that key;
4. stamp `sourceName`/`lastUpdate` with the caller's `MPStorageStamp` on the section, the entry and the root (legacy stamped the root only; E23 shows other writers stamp both levels). An edit that changes nothing returns `false` and stamps nothing, so the caller does not write;
5. refuse, before changing anything, any text outside the Basic Multilingual Plane (`nonBMPCharacter(path:codePoint:)`, Q-3, X9);
6. when the write policy `MPStorageStamp.recordsTombstones` is on, record a dated **tombstone** when removing a dated item (pseudo, bookmark); adding a key again clears its tombstone.

**Tombstones.** v0.1 has no deletion marker. **Write policy: `recordsTombstones`, off by default** until other writers are known to keep the key (HFR-PROTOCOL §7). Off, no tombstone is created and none is pruned; tombstones already in a document are still honoured by the merge and written back as they are, so with the policy off the key is never added to a document that did not have it. A section may carry `"tombstones":[{"id":<storageKey>,"deleteDate":<ms>}]`. The legacy iOS client keeps unknown keys because it edits the parsed dictionary in place (`MPStorage.m:886, 908`); whether other writers (DTCloud, redface2, userscripts) keep it on rewrite is **unverified** (HFR-PROTOCOL §7, to settle with LOT-001/LOT-004 documents). If they drop it, merges lose the deletion tie-breaker, so a deleted item can reappear. Merges with a `base` are affected only for dated items added after that base; deletions of items present in the base remain identifiable without tombstones. If another client already uses `tombstones` for something else, the value stays verbatim in `extra` and that section records none. Kept 90 days, at most 50 per section (≈ 3 KiB per section at worst).

**Write guards** (`MPStorageCodec.encodeForWriting`): compact JSON, keys sorted, slashes unescaped; refuses a document without a `0.1` entry, any non-BMP character anywhere (keys included, other clients' namespaces included, with the JSON path in the error), and more than **65 536 UTF-8 bytes** (rf2 `MAX_CONTENT_FORM_BYTES`, E24; HFR's own limit is unknown and it truncates silently). `decode` never resets: invalid JSON or no `data` throws; a `\u` escape of an unpaired UTF-16 surrogate (no Swift string can hold it) throws `unpairedSurrogate(byteOffset:)` instead of Foundation's misleading type mismatch.

**Numbers keep their exact text.** `JSONValue.number` holds a `JSONNumber` lexeme, so other clients' values come back byte for byte (`9007199254740993`, `1e17`, `-0.0`, `1.50`), where a `Double` would rewrite them (`…992`, `1e+17`, `-0`). `JSONDecoder` and `JSONEncoder` only know `Int64`/`Double`, so `MPStorageCodec` boxes every number token of the text as a string `"<U+E000 U+E001><lexeme>"` before decoding and unboxes them after encoding (`JSONNumberBox`); the lenient readers of modelled fields unbox too. A plain `JSONEncoder`/`JSONDecoder` round trip of the model still works, through `Int64` or `Double`.

**Three-way merge** (`MPStorageMerge.merge(base:ours:theirs:stamp:)`), for LOT-052's write loop: keep the document as read (`base`), apply edits to a copy (`ours`), re-read the forum copy right before writing (`theirs`), merge, write only when `needsWrite`, verify by re-reading.

| Level | Rule |
|---|---|
| Entries | only the writable entry is merged; the others are `theirs` verbatim. `theirs` or `ours` without a `0.1` entry → `noWritableEntry` |
| Root keys, namespaces, section keys this app does not model | key by key: the side that did not change since `base` takes the other side's value; both changed → ours, reported |
| Section | unchanged on one side since `base` → the other side's section as is (metadata included) |
| List items, matched by `storageKey` | same on both sides → kept. Changed on one side → that change. Changed on both → **ours** (this app is the last writer), `bothChanged`. Added on both, different → ours, `bothAdded`. Deleted on one side, unchanged on the other → deleted. Deleted on one side, **changed** on the other → the change survives, `changedAndDeleted`. Added on one side only → kept, unless the other side has a tombstone **newer than the item's date** (then removed and reported as `addedAndDeleted`) |
| Undecodable raw items | `theirs`, minus those `ours` dropped since `base`, plus those `ours` added |
| Tombstones | union, latest date per key; a key that is live after the merge loses its tombstone; pruned only when `recordsTombstones` is on |
| Order | items only `ours` has first (legacy inserts at the top), then `theirs` order |
| Metadata | stamped only on sections, entry and root whose content differs from `theirs`; no difference → `needsWrite == false` and the result is `theirs` unchanged |

Without `base` (lost or never stored): items on both sides that differ keep **theirs** (`divergentWithoutBase`), an item on one side only is kept unless a newer tombstone on the other side deletes it, opaque values keep `theirs` when present.

Conflicts are returned as `MPStorageConflict(location, key, kind, resolution)` for the app to show or log; the merged document is always consistent.

## Edge cases
- Duplicate keys inside one list (e.g. `Foo` and `foo` in the blacklist, written by another client) collapse to the first occurrence when the section has to be merged item by item.
- A `0.2` entry before the `0.1` one: the `0.1` entry is edited, the other kept. Legacy edits `data[0]` blindly; a legacy client would then write into the `0.2` entry.
- `tombstones` of a non-array or malformed shape: foreign, kept verbatim, no tombstones recorded there. An empty `"tombstones":[]` is not re-written (same harmless normalisation as `{}` sections in LOT-013).
- Unchanged tombstones in a different order are not a change (no write just to reorder).
- A `0.1` entry at a different index in `theirs` (e.g. after a `0.2` entry): merged at its index there, the other entries kept.
- `theirs` dropping a whole section: items unchanged on our side go with it, items we added stay; untouched on our side, nothing is written.
- Non-BMP text written by another client blocks every write until it is removed: the refusal names the path so the app can explain it.

## Limits of v0.1 (input for the MPStorage v2 discussion)
1. **Undated items.** Every flag, and any pseudo or bookmark written without `createDate`, has no date: deleting it leaves no tombstone (nothing to compare with), so without a `base` it can come back. With a `base` the deletion is identified; it still yields to a concurrent change of the same item on the other side (`changedAndDeleted`, the change is kept).
2. **Edits carry no date** (bookmark label, flag position): concurrent edits of one item resolve to this app's copy, not to the latest edit across clients. A v2 `updateDate` per item would make it last-edit-wins.
3. **No document version or lock**: the read-merge-write window remains; LOT-052 narrows it (re-read just before writing, verify after) but cannot close it.
4. Tombstones are an addition only this app understands, and other writers may drop them (unverified). They only help merges this app performs.
5. Non-BMP characters could be stored as `😀` JSON escapes (pure ASCII). Not done: never observed live; refusing is the rf2 behaviour.

## Fixtures
None (synthetic documents in the tests, modelled on E23). Real documents arrive with LOT-004.

## Tests
`MPStorageMutationTests`, `MPStorageMergeTests`, `MPStorageCodecTests` (HFRModelsTests): concurrent adds, delete against edit in both directions, both changed, both added, unknown namespaces / entries / root keys preserved, undecodable items preserved, base-less merges with tombstones older and newer than the item, tombstone union and pruning, foreign `tombstones` key, write policy off by default (no tombstone created, existing ones preserved and not pruned), fresh add against a newer tombstone reported, identical flag upsert is a no-op, duplicate keys collapsing, `theirs` dropping a whole section, `0.1` entry at another index, numbers written back byte for byte, unusual number spellings in modelled fields, lone surrogate escapes, size cap (inclusive limit and a > 64 KiB document), non-BMP refusal in edits and anywhere in the document (with path), no-op edits and merges produce no write.

## Intentional differences from legacy
- Metadata stamped at every level touched, and also on removals (legacy forgot them).
- Bookmark identity includes the category (E18).
- Concurrent writers no longer erase each other's items: legacy re-read then rewrote the whole document, so a write in between was lost.
- Writes are refused instead of being silently truncated by HFR (non-BMP, size).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A three-way merge needs the copy the edits were made on: keep `base` with the pending edits, not only the edited document.
