# LOT-096 — Emoji → smiley suggestion table

- **Module:** HFRModels (`Sources/HFRModels/Smileys/`, resource `Resources/EmojiSmileys.json`); `PostingFlow` (HFRClient, LOT-048) now calls the shared check
- **Difficulty / model:** easy (Opus 5.5 author → Fable 5.1 reviewer; the plan routes Sonnet → Opus)
- **Issue:** [#188](https://github.com/ezzz/HFRnow/issues/188) · feature FEAT-012 ([#156](https://github.com/ezzz/HFRnow/issues/156)), **proposed by Bybifok** (`moust4ki`): refuse an emoji and suggest the matching HFR smiley. The other lot of the feature is LOT-151 ([#241](https://github.com/ezzz/HFRnow/issues/241), the app), which closes #156.
- **Depends on:** LOT-012 (#45, the bundled catalogue `CommonSmileys.json`, `CommonSmileyCatalog`); LOT-048 (#74, the non-BMP refusal), both done.
- **Merge:** adds HFRModels public types, so the steward or the maintainer merges it (AGENTS.md §8).

## Sources
- **Legacy** (ezzz/HFRnow at `2440d79`): no table. The ObjC composer removed emoji without a word before posting: `-[NSString removeEmoji]` (`SuperHFRplus/Helpers/RangeOfCharacters.m:306-328`) drops U+1D000-1F77F (non-BMP) and U+2100-26FF (BMP), called by `Classes/AddMessageViewController.m:553`; audit D B2, HFR-PROTOCOL §6 "Legacy emoji stripping".
- **HFR**: a post is cut at its first non-BMP character while HFR answers success (Q-3, capture `W12`, HFR-PROTOCOL §6); what happens to a BMP emoji or U+FE0F is not captured (CAP-N3, [#171](https://github.com/ezzz/HFRnow/issues/171); HFR-PROTOCOL §7b B13).
- **Catalogue**: the 59 standard smileys of `CommonSmileys.json` (LOT-012, legacy `commonsmile.plist`).

No HFR fact is added, so there is no HFR-PROTOCOL subsection; CAP-N3 will settle the BMP case.

## Behaviour

### `PostCharacterCheck` (HFRModels)
- `risk(of:) -> PostCharacterRisk?` per character (a whole grapheme: `👨‍👩‍👧`, `🇫🇷`, `👍🏽` are one):
  - `.truncates`: a scalar above U+FFFF (HFR cuts the post there). LOT-048 refuses these.
  - `.untested`: otherwise, a U+FE0F, a keycap mark U+20E3 (`1️⃣` and `1⃣` alike) or a scalar with the Unicode `Emoji` property beyond Latin-1 (`Unicode.Scalar.Properties.isEmoji` above U+00FF: `❤`, `☺`, `✌`). The property also covers text-default symbols of ordinary typography (`™`, `♥ ♠ ♣ ♦`, `↔ ↩`, `➡ ⬅`, `✔ ✖`, `⚠`, `☎`, `‼`, `ℹ`, `♀ ♂`…). Kept, replaced or cut is not captured: **never refused**. LOT-151 should warn only where `EmojiSmileyTable` has a suggestion, until CAP-N3 answers.
  - nil: anything else. `#`, digits, `©`, `®` are `isEmoji` for Unicode but stay plain text (Latin-1).
- `riskyCharacters(in:)`: each risky character once, in order of first appearance. `truncatingCharacters(in:)`: the `.truncates` ones, exactly what `PostingFlow` refuses: its private loop is replaced by this call, so the two agree by construction (and a test runs the flow on the same texts).

### `EmojiSmileyTable` (HFRModels)
- `bundled()` reads and decodes `EmojiSmileys.json` (`[{"emoji": "🙂", "smileys": [":)"]}]`, 49 emoji) at each call, like `CommonSmileyCatalog.bundled()`: load it once (LOT-151), not per keystroke. `decode(_:)` reads that format; `init(suggestions:)` builds one.
- `smileys(for:) -> [String]`: catalogue codes, best first; empty when the emoji has no entry. Keys and lookups drop U+FE0E, U+FE0F and the skin tones U+1F3FB-1F3FF, so `❤️` is `❤` and `👋🏽` is `👋`. Two keys that become one merge their codes, each once.
- **Which smileys**: only catalogue smileys whose file name says what they show (`smile`, `biggrin`, `lol`, `wink`, `tongue`, `frown`, `cry`, `mad`, `love`, `ange`, `confused`, `redface`, `sleep`, `eek`, `sweat`, `hello`, `vomi`, `miam`, `crazy`, `fou`, `bug`, `gun`, `hot`, `spookie`, `kaola`); a smiley whose name does not (`:jap:`, `:sum:`, `:24:`…) is not suggested, and neither is `:evil:`, whose file is `fou.gif`. The table is editorial: entries can be added by PR, each code checked against the catalogue by the tests.

## Edge cases
- A ZWJ sequence (`❤️‍🔥`, `👨‍👩‍👧`) is one character and truncates; it has no entry unless added whole.
- Regional-indicator flags (`🇫🇷`) are non-BMP: truncate, no entry.
- A BMP emoji with an entry (`❤`, `☺`, `☹`) gets a suggestion although it is only `.untested`: the app decides whether to offer it.
- The order of emoji in the JSON does not matter; the order of codes in an entry does (best first).

## Fixtures
None: Unicode data and the bundled catalogue. No page is read.

## Intentional differences from legacy
1. **Refuse and suggest, never strip**: legacy removed emoji silently (`removeEmoji`), including BMP ranges HFR may keep; here only non-BMP characters are refused (LOT-048, CHANGELOG-LEGACY #36) and a smiley is suggested where the table has one.
2. **BMP emoji are not touched** until CAP-N3 is captured (legacy removed U+2100-26FF).

## Tests
`EmojiSmileyTableTests` (every code in the bundled catalogue, each once; every key one emoji without selector or skin tone; lookups with and without U+FE0F/U+FE0E and skin tone; no suggestion for an unknown emoji, a letter, a digit, a family; key merging), `PostCharacterCheckTests` (truncating graphemes: emoji, skin tone, family, flag, mathematical digit, ZWJ heart; untested: `❤`, `❤️`, `☺`, `☹`, `✌`, keycaps with and without U+FE0F, `™`, `♥`, `↔`, `⚠`; plain: letters, `€`, `#`, `©`, `®`; order and uniqueness), `PostCharacterAgreementTests` (the posting flow refuses exactly `truncatingCharacters` on four texts and sends three texts with only untested emoji). Nine mutations, each applied and reverted, each failed named tests: the threshold moved to U+1F000, no untested, Latin-1 `isEmoji` counted, U+FE0F or skin tones kept in the key, an unknown code in the table, the flow refusing untested characters, no de-duplication, and after review the keycap mark U+20E3 ignored.

## Learnings
- When a rule exists in a flow (LOT-048) and a new lot needs it in a lower module, move it down and call it from the flow: "agrees on the same inputs" then holds by construction, and a test pins it.
