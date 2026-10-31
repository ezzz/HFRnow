# LOT-072 — Shared pseudo normaliser

- **Module:** HFRStorage (`Sources/HFRStorage/Pseudos/PseudoNormalizer.swift`)
- **Difficulty / model:** easy (Opus 5.5 author → Fable 5.1 reviewer)
- **Issue:** [#96](https://github.com/ezzz/HFRnow/issues/96) (old issue francoisgn/ios-app_SwiftHFR#92)
- **Builds on:** LOT-061 (blocklist), LOT-063 (drafts), LOT-065 (accounts), LOT-064 (`AccountKey`), all done; ADR 0013 §7 (frozen account key).

## Sources
- Legacy francoisgn/hfrnow at `2440d79`: `Classes/BlackList.m:130-143` (`findIndexFor:`: U+200B removed, lower-cased, exact compare). No other legacy code compares pseudos for these stores.
- The three copies this lot replaces: `PseudoNormalizer` (LOT-061: U+200B removed, lower-cased), `DraftNameNormalizer` (LOT-063: the same), `AccountBook.normalized` + `samePseudo` (LOT-065: every format character removed, white space trimmed, compared lower-cased).
- ADR 0013 §7: the account key is frozen at "U+200B removed, then lower-cased, nothing else"; LOT-064's `AccountKey.make` is that function and stays as is.
- No HFR page is involved: no capture, no protocol fact (nothing for HFR-PROTOCOL §6c).

## The rule
**Two pseudos designate the same member when their comparison forms are equal** (`PseudoNormalizer.matches`). The comparison form (`comparisonForm`) is the pseudo with:

1. every Unicode format character removed (general category Cf: U+200B, which HFR inserts against impersonation; U+FEFF, U+2060, U+200C, U+200D, U+00AD…),
2. surrounding white space and newlines trimmed (U+00A0 included), inner spaces kept,
3. lower-cased (`String.lowercased()`, locale-independent).

Steps 1-2 alone are `cleaned` (case kept), the form `AccountBook` stores. `String` equality is canonical, so `É` and `E` + U+0301 are equal; diacritics stay significant (`Élodie` ≠ `Elodie`, as LOT-065 decided).

**Stored keys are not comparison forms.** Every key written to disk keeps the frozen account key of ADR 0013 §7 (`AccountKey.make`: U+200B removed, lower-cased, nothing else), so no stored key changes. For a `cleaned` pseudo, which every account pseudo is (`AccountBook.add` cleans it), the account key equals the comparison form (tested over the whole table).

## Callers
| Caller | Before | After | Stored data |
|---|---|---|---|
| `PseudoListStore` account key (`blocklists[…]`) | `PseudoNormalizer.normalize` | `AccountKey.make`: same output | keys unchanged |
| `PseudoListStore` entry matching (`block`, `unblock`, `allow`, `disallow`, `isBlocked`, `isAllowed`, `replaceBlocklist`, empty check) | U+200B + case | the rule | entries are stored as typed and compared at run time: every old entry is still found |
| `PseudoListStore.unblock` / `disallow` | removed the first match | removes **every** match | a list stored before can hold two spellings the rule now merges (`Marc`, `Marc` + U+FEFF); both go |
| `PseudoListStore` new entries (`block`, `allow`, `replaceBlocklist`) | stored as typed | stored `cleaned` (case kept) | old entries are not rewritten; a new entry carries no invisible character or stray space into MPStorage (LOT-062), whose legacy readers remove U+200B only |
| `DraftStore` account key (`Draft.account`) | `DraftNameNormalizer` | `AccountKey.make`: same output | keys unchanged |
| `DraftContext.privateMessage` recipient (`storageKey`) | U+200B + case | the rule | `storageKey` is never stored: a draft keeps its recipient as typed and the key is recomputed, so an old draft is found under the new rule |
| `AccountBook` (`add`, `account(matching:)`, `remove`, `replace`, `init` dedupe, `md_user` check) | private `normalized` + `samePseudo` | `cleaned` + `matches`: same rule | unchanged behaviour |
| `AccountKey` (LOT-064, LOT-172) | — | untouched (comment only) | frozen |

`PseudoNormalizer.normalize` (public, no caller outside HFRStorage) is removed: its only remaining role, the account key, is `AccountKey`'s.

## Edge cases
- A pseudo that is empty once cleaned (`" "`, U+FEFF alone) is now refused by both lists (`emptyPseudo`); before, a blank pseudo was accepted.
- An account string that is not cleaned (`" Bob"` + U+FEFF) keeps its old account key (`" bob"` + U+FEFF): keys never change, so its lists and drafts stay where they were. The app passes `AccountBook` pseudos, which are cleaned.
- Inner white space is significant (`Ma rc` ≠ `Marc`): HFR's pseudo rules are not captured, so only what surrounds a pseudo is dropped.
- `AvatarCache.fileName(forPseudo:)` (LOT-066) also removes U+200B and lower-cases: it is a file-name key, so it stays frozen like `AccountKey` (a change would orphan every cached avatar) and is not unified.
- ADR 0013 §7 still says the account key "coincides with LOT-061's `PseudoNormalizer.normalize`": true when written, and that function is now gone; the ADR is not edited by this lot, `AccountKey` is the key.
- Not covered here: `HFRText.normalizedPseudo` / `pseudoComparisonKey` (HFRParsing: U+200B removed and trimmed; HFRStorage cannot import HFRParsing) and `MPStorageBlocklistEntry.storageKey` (HFRModels, the MPStorage document's own merge key, LOT-062). Pseudos parsed from pages are already trimmed, so the blocklist rule is a superset of the parser's.

## Fixtures
None: pure logic, synthetic strings and documents (a blocklist and a draft document as stored before this lot).

## Intentional differences
1. **Blocklist and allowlist matching** ignore every format character and surrounding white space, not only U+200B and case (legacy `BlackList.m:130-143`): a pseudo copied with a U+FEFF or a trailing space is the same member. CHANGELOG-LEGACY #49.
2. **`unblock` removes every matching entry**, so no spelling stored under the narrower rule stays blocked.
3. **MP draft recipients** follow the same rule.
4. **New list entries are stored cleaned** (case kept), not as typed: legacy stored the typed string.

## Tests
`PseudoNormalizerTests` (table: U+200B, U+FEFF, U+2060, U+200C/U+200D, U+00AD, tabs and newlines, U+00A0, inner space, accents composed and decomposed, empty; account key = comparison form on a cleaned pseudo), `PseudoListStoreTests` (format characters and white space on both lists, new entries stored cleaned, blank pseudos refused, a document stored before this lot found and fully unblocked, keys stored in the frozen form), `DraftContextTests` (recipient), `DraftStoreTests` (a draft stored before this lot found; account keys in the frozen form), and the existing `AccountBookTests`. Nine mutations, each applied and reverted, each failed named tests: the old U+200B-and-case rule, format characters kept, no trimming, new entries stored as typed (review), `unblock` removing the first match only, blocklists or drafts keyed by the comparison form, recipients keyed by the account key, `AccountBook` comparing exactly.

## Learnings
- A key and a comparison are two contracts: freeze the key (it is on disk, possibly on several devices), and let the comparison change only where both sides are recomputed at run time.
