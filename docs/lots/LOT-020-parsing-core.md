# LOT-020 — Parsing core

- **Module:** HFRParsing
- **Difficulty / model:** medium (Opus → Fable)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources

Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [B §3.3.3–3.3.5, B3](../audit/B-list-parsing-models.md), [C §3.4, C02](../audit/C-message-parsing.md), D4 (decoder part only); [redface2 comparison](../research/redface2-comparison.md) §4.3 E7, E13, E20; [user feedback](../research/user-feedback-p450-510.md) §4.

| Legacy | Replaced by |
|---|---|
| `SuperHFRplus/Vendor/HTMLParser/HTMLNode.m:105-139, 232-298` (`findChildWithAttribute:matchingName:allowPartial:`, `findChildOfClass:`) | `AttributeMatch` + `Element.descendants/firstDescendant/requiredDescendant` (internal) |
| `SuperHFRplus/Helpers/RangeOfCharacters.m:92-138` (`decodeSpanUrlFromString`, `…2`) | `ObfuscatedURL.decode(classAttribute:)` |
| `Classes/ObjCMessageActionsBuilder.m:70-89` (`absoluteURL`, `absoluteDecodedURL`) | `HFRURL.absolute(_:relativeTo:)`, `ObfuscatedURL.resolvedURL(from:)` |
| `Classes/ObjCTopicListParser.m:421-424`, `Classes/Favorite.m:119-123` (`dd-MM-yyyy à HH:mm`, `DateFormatter`), `HFRswift/Wrapped/ParseMessagesOperation.m:398-401` (toolbar regex with seconds) | `HFRDate.date(from:)`, `HFRDate.firstDate(in:)` |
| `Classes/ObjCTopicPageWorker.m:14-43`, `Classes/ObjCTopicListParser.m:9-38`, `HFRswift/Swift/Common.swift:2471-2508` (page from URL) | `HFRURL.page(in:)`, `HFRURL.canonicalTopicPath(in:)` |
| `HFRswift/Swift/Common.swift:2510-2541`, `Classes/Topic.m:73-84` (replace page) | `HFRURL.replacingPage(in:with:)` |
| `RangeOfCharacters.m:253-274` (`stringByRemovingAnchor`) | `HFRURL.removingAnchor(_:)` |
| `Classes/Favorite.m:37` + `RangeOfCharacters.m:276-304` (`wordAfterString:@"cat="`), `Common.swift:2549-2575` (`numreponse`) | `HFRURL.queryValue(named:in:)`, `category`, `topicNumber`, `topicID`, `numreponse`, `anchorPostNumber` |
| `Classes/ObjCForumsParser.m:519-521`, `Classes/ObjCTopicListParser.m:88-92`, `HFRswift/Swift/MPBackgroundService.swift:113-139` (MP badge number) | `HFRText.firstInteger(in:)` |
| `Classes/BlackList.m:130-141`, `Classes/MPStorage.m:626`, `HFRswift/Swift/Common.swift:1051-1055` (U+200B in pseudos) | `HFRText.normalizedPseudo(_:)`, `HFRText.pseudoComparisonKey(_:)` |

## Behaviour

All helpers are pure functions over `String`/`URL`, Foundation and SwiftSoup only, Linux-buildable. Public API uses Foundation and HFRModels types only; the SwiftSoup helpers are `internal` (ADR 0002), so later parsers in HFRParsing use them and callers never see them.

### Public API

| Type | Members | Rules |
|---|---|---|
| `ParsingError` | `malformedDocument`, `missingElement(String)`, `missingAttribute(element:attribute:)`, `invalidValue(field:)` | `Error, Sendable, Equatable`. Payloads name the search, never page content (tokens and pseudos stay out of logs) |
| `HFRDate` | `timeZone`, `date(from:)`, `firstDate(in:)` | `dd-MM-yyyy à HH:mm[:ss]`, ASCII digits, any Unicode whitespace around `à` (U+00A0 from `&nbsp;`); `date(from:)` needs the whole trimmed string, `firstDate(in:)` scans a sentence (`Posté le …`, `Message édité par … le …`) and skips matches glued to other digits or followed by a digit or `:` (`14:07:331`, `14:07:3`, `14:07:` are refused, never read as `14:07:00`) or not on the calendar |
| `HFRURL` | `forumHost`, `base`, `decodingAmpersands`, `absolute(_:relativeTo:)`, `queryValue(named:in:)`, `page(in:)`, `canonicalTopicPath(in:)`, `category(in:)`, `topicNumber(in:)`, `topicID(in:)`, `numreponse(in:)`, `anchorPostNumber(in:)`, `removingAnchor(_:)`, `replacingPage(in:with:)` | see below |
| `CanonicalTopicPath` | `topic`, `page` | from a whole path `/hfr/<cat>[/<sub>]/<slug>-sujet_<post>_<page>.htm` (at most one subcategory, scheme and host ignored) (HFR-PROTOCOL R5, E13) |
| `ObfuscatedURL` | `decode(classAttribute:)`, `resolvedURL(from:)`, `encode(_:prefix:)` | see below |
| `ObfuscatedURLPrefix` | `noClass` (`md_noclass_cryptlink`, 20), `blank` (`md_blank_cryptlink`, 18), `plain` (`md_cryptlink`, 12) | E7 |
| `HFRText` | `firstInteger(in:)`, `normalizedPseudo(_:)`, `pseudoComparisonKey(_:)` | see below |

### Internal API (for parsers in HFRParsing)

- `HTMLDocumentLoader.document(from:) throws(ParsingError)`: `SwiftSoup.parseHTML` (never `parse`, which switches to XML on a leading `<?xml`), failures become `.malformedDocument`.
- `AttributeMatch`: `.exact` (whole attribute value equals, legacy `allowPartial:NO` and `findChildOfClass:`), `.contains` (substring, legacy `allowPartial:YES`), `.classToken` (one class among the value's tokens, split on ASCII whitespace as HTML does, so U+00A0 stays inside a token; for new code).
- `Element.descendants(attribute:matching:)`, `firstDescendant`, `requiredDescendant` (throws `.missingElement("class=…" / "class*=…" / "class~=…")`), `requiredAttribute` (throws `.missingAttribute`). Like the legacy lookups, the receiver is never part of the result and order is document order; an element without the attribute never matches. `descendants` materializes the whole subtree (`getAllElements`) before filtering: measure it on the LOT-022 list fixtures and switch to a lazy walk if it shows.

Regex literals are compiled once (`nonisolated(unsafe) static let`, justified in the code: `Regex` is not `Sendable` only because of its generic output; these capture `Substring`s).

### Dates

- Time zone `Europe/Paris`; a non-lenient `Date.ParseStrategy` reads the wall-clock fields (rejects 31-02, 29-02 of a common year, 24:00, :60), then the Paris offset is applied by hand.
- **Spring forward** (last Sunday of March, 02:00 → 03:00): a time in the gap does not exist and gives nil.
- **Fall back** (last Sunday of October, 03:00 → 02:00): a time between 02:00 and 02:59 is ambiguous and resolves to its **first** occurrence (CEST). HFR prints no offset, so this cannot be known; the rule is fixed so macOS and Linux agree.
- No relative labels ("il y a N min"): presentation belongs to the app (audit B 3.3.5).

### URLs

- `absolute`: trims, removes ASCII tab/LF/CR anywhere (browser behaviour), decodes `&amp;`, prefixes `//` with `https:`, resolves anything else relative to `relativeTo` (the forum root by default). Only `https`/`http` with a host and **no user info** survive (`https://forum.hardware.fr@evil.example/` is refused); hosts are lowercased; `http` to `forum.hardware.fr` without an explicit port becomes `https` (an explicit port is kept and blocks the upgrade) (ADR 0006 amendment 1). Every other scheme (`javascript:`, `data:`, `file:`, `blob:`, `mailto:`), in any case, gives nil.
- Query parameters match by **exact name**; values are percent-decoded, and `+` is **kept** (not turned into a space), deliberately, like legacy `NSURLComponents` reads (`ObjCTopicPageWorker.m:17-22`); HFR links carry digits, ids and slugs; numeric helpers accept positive ASCII integers only.
- `page(in:)`: `page=` (positive), then canonical `sujet_<post>_<page>.htm`, then the older `_<page>.htm` ending of the path; nil otherwise (the caller picks the default: legacy topic pages used 1, lists 0).
- `numreponse(in:)`: `numreponse=0` means "none" on HFR links and gives nil. `anchorPostNumber(in:)` reads `#t<id>`, which is what identifies a quoted post (E20).
- `replacingPage(in:with:)`: drops the fragment; replaces the first `page=` parameter, else the page of the canonical path, else the `_<page>.htm` ending, else appends `page=`; nil for a page below 1.

### Obfuscated URLs (HFR-PROTOCOL §4, E7)

- Payload = URL bytes, two characters per byte, each character the index of a nibble (high first) in `0A12B34C56D78E9F`.
- `decode(classAttribute:)` decodes when one class token (split on ASCII whitespace only) starts with one of the three prefixes and is longer than it, and the attribute contains neither `/` nor `http` (case-insensitive). Odd length, a character outside the alphabet (lowercase included) or bytes that are not UTF-8 give nil.
- `resolvedURL(from:)` is the action-link entry point (LOT-031): a prefixed value is decoded then made absolute, or gives nil when it does not decode; any other value is a link in clear and is made absolute.
- `encode(_:prefix:)` is the inverse, for tests and the LOT-001 anonymizer (decode, redact, re-encode).

### Text

- `firstInteger(in:)`: first run of ASCII digits; nil when none or when it overflows `Int`.
- `normalizedPseudo(_:)`: removes every U+200B and trims whitespace; `pseudoComparisonKey(_:)` also lowercases.

## Edge cases

Covered by `Tests/HFRParsingTests/Core/` (Swift Testing, table-driven):

- Decoder: known vectors computed outside the code (Python) for each prefix; round trip of five URLs (incl. non-ASCII) through each prefix; 14 skip cases (bare prefix, no prefix, `/`, `http`/`HTTP`, odd length, bad or lowercase character, invalid UTF-8, prefix not at token start); prefixed token among other classes; a decoded `javascript:` link refused by `resolvedURL`.
- Dates: CET and CEST offsets, leap day, last and first valid minute around both DST changes, gap, ambiguous hour, U+00A0, 18 invalid strings (incl. non-ASCII digits), first date in sentences, invalid first date skipped, date glued to digits.
- URLs: every endpoint path of HFR-PROTOCOL R1–R9, S1, S3, §3, `&amp;`, protocol-relative, `http` upgrade, foreign hosts, refused schemes (mixed case, tab/newline-obfuscated, percent-encoded), relative to a canonical page, `subpage` vs `page`, `page=0`, canonical and older shapes, `numreponse=0`, fragments, page replacement on every shape plus round trip.
- Selector helpers: exact vs substring vs token (`sujetCase1` vs `sujetCase10`, `left` vs `left nav`), receiver excluded, other attributes, missing attribute, typed errors.

## Fixtures

None. No real crypt-link sample is committed yet (review F11): the decoder is tested on vectors computed independently and on round trips. LOT-001 fixtures will add real samples; LOT-022 and LOT-031 run the decoder on them.

## Intentional differences from legacy

1. **Three prefixes, per-prefix length rule.** Legacy decodes message actions with a fixed 20-character prefix and `length > 20`, and pager links with 12 (`RangeOfCharacters.m:92-138`, `ObjCMessageActionsBuilder.m:84`); it assumes the prefix starts the class attribute. We find the prefixed class token and use its own length (E7).
2. **Invalid payloads give nil.** Legacy reads past the end on an odd length (exception caught at `ObjCMessageActionsBuilder.m:86`, then the class name itself is used as a URL) and turns unknown characters into garbage bytes (`NSNotFound * 16`); bytes above 127 are mangled by `%c`. We decode UTF-8 and return nil on any defect.
3. **Scheme allow-list in `absolute`.** Legacy concatenates any value onto the base URL. We keep only `http(s)` (ADR 0006 amendment 1), resolve relative paths against the current page instead of always the root, and strip tabs/newlines.
4. **Exact query names.** Legacy regexes `page=(\d+)` and `.*page=([^&]+).*` also match `subpage=`; `wordAfterString:` reads at most four characters after `cat=`. We parse the query.
5. **`removingAnchor` cuts at the first `#`** (URL fragment rule); legacy cut at the last `#` followed by a non-`&` character, and left a trailing `#` in place.
6. **First integer.** Legacy `[^.0-9]+([0-9]{1,})[^.0-9]+` needs text on both sides: `Vous avez 7` gives 0 there and 7 here.
7. **Dates.** `DateFormatter` was lenient (single-digit days, two-digit years) and its DST choice was platform-defined; we are strict on the shape and fix the DST rules above. Seconds are kept for messages instead of being re-serialized as a string.
8. **Selector helpers** keep legacy exact/substring semantics deliberately, so ported parsers reproduce the oracle; `classToken` is offered for new code.

## Learnings

- Swift Regex has no look-behind; check the previous character by hand.
- SwiftLint's `large_tuple` rejects typed regex outputs with more than two captures: erase to `Regex<AnyRegexOutput>` or return a two-field tuple.
- `Date.ParseStrategy` on Linux returns nil in the spring-forward gap and the **second** occurrence in the fall-back hour; do not rely on either, resolve offsets explicitly.
