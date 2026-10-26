# LOT-030 — Message block extraction (core of the topic page)

- **Module:** HFRParsing
- **Difficulty / model:** difficult (Fable → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`; audit item C03 in [C](../audit/C-message-parsing.md) §3.1–3.2, §7.2)

Chain: LOT-003 (oracle) → **LOT-030** → LOT-034 (content normalization). Siblings on the same tree: LOT-031 (action links),
LOT-032 (quotes), LOT-033 (page metadata, done in parallel: nothing page-level is read here), LOT-035 (embeds, after 034).

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Wrapped/ParseMessagesOperation.m:136-146` (`messagetable` blocks, `firstChild` row) | `MessageBlockParser.extract(from:)`: `class="messagetable"` (whole attribute, legacy `allowPartial:NO`), one block per table |
| `:149, 168-174` (author `.s2`, trim, skip `Publicité`) | `author`, advertisement skip |
| `:153-158` (`messagetabledel` wrapper → `isDel`) | `isDeleted` (**pending capture**) |
| `:160` (`firstChild.firstChild[name]` → `postID` with its `t`) | `numreponse` (the number) from the first `<a name="t<digits>">` of the block |
| `:176-177, 452-473` (`avatar_center` first child `src`, download to the cache) | `avatarURL` (no download: C 7.1 decision 2) |
| `:324` (`rawContentsOfNode` of the first `id` containing `para` → `dicoHTML`) | `contentHTML` (inner HTML of `div#para<numreponse>`, legacy rule as fallback) |
| `:334-355` (`.edited` → `quotedNB`, `quotedLINK`, `editedTime`) | `quotedByCount`, `quotedByURL`, `editNote` (+ `editedBy`, `editedAt`) |
| `:398-405` (`.toolbar` text → `dd-MM-yyyy HH:mm:ss`) | `dateText` (+ `postedAt`) |
| `:141` (comment "Reprise de la page précédente") | `isContinuation` |

Not ported here, by design (C 7.1): the own-pseudo / blacklist / whitelist / `filter_posts_quotes` policy (`:181-189, 206-223, 319-361`,
app-side C10), quote rewriting (`:191-226`, LOT-032), video marking (`:238-317`, LOT-035), the search-result prefix (`:365-368`, pending
capture, see Edge cases), action links (`:371-390`, LOT-031), avatar cache and downloads (`:420-473`, C17), topic title and last page
(`:491-507`, LOT-033), filter mode (`:111, 141-144, 160-166, 228-237`, C10/C11).

## Behaviour

### API

| Type | Members | Rules |
|---|---|---|
| `MessageBlockParser` (public) | `blocks(in: String) throws(ParsingError) -> [MessageBlock]` | Parses the page, returns the message blocks in page order, advertisement blocks skipped. A page without any `messagetable` (a deleted conversation `RA5`, a non-topic page) gives `[]`, not an error |
| `MessageBlockParser` (internal) | `extract(from: Document) throws(ParsingError) -> [ExtractedMessageBlock]` | Same, with the DOM elements, for the next stages inside HFRParsing |
| `ExtractedMessageBlock` (internal) | `block`, `table`, `content`, `toolbar?`, `edited?` | SwiftSoup elements never leave the module (ADR 0002) |
| `MessageBlock` (public, `Sendable, Hashable, Identifiable, Codable`) | see below | the facts of one block, no policy, no rewriting |

`MessageBlock` fields:

| Field | Source and rule |
|---|---|
| `numreponse: Int` | First `<a name>` of the block whose name is `t<digits>` (document order; `<a name="bas">` of MP threads comes after it). Missing → `ParsingError.missingElement("a[name=t<numreponse>]")` |
| `author: String` | Text of the first element with `class="s2"`, trimmed, U+200B removed (`HFRText.normalizedPseudo`). Missing → `.missingElement("class=s2")`. `Publicité` → the block is skipped |
| `isDeleted: Bool` | The table's parent element has the class token `messagetabledel`. Pending capture: false on every fixture |
| `isContinuation: Bool` | First block of the page only, and its content's first element is a `<p>` whose first node is `<strong>Reprise du message précédent :</strong>` |
| `avatarURL: URL?` | `src` of the first `<img>` inside the first `class="avatar_center"` element, through `HFRURL.absolute` (http(s) only, ADR 0006 amendment 1) |
| `dateText: String` | First `dd-MM-yyyy à HH:mm:ss` (any whitespace, U+00A0 included, around `à`) of the toolbar text, written `dd-MM-yyyy HH:mm:ss`; `""` without toolbar or date |
| `postedAt: Date?` | `HFRDate.date(from:)` of that match (Europe/Paris) |
| `contentHTML: String` | Inner HTML of the first element with `id="para<numreponse>"`, else (legacy rule) the first element whose `id` contains `para`; missing → `.missingElement("id=para<numreponse>")`. Serialized without pretty-printing. **Raw**: not sanitized, not normalized; the input of LOT-034 |
| `editNote: String?` | Trailer text after `Message édité par`, whitespace-normalized and trimmed (`<pseudo> le dd-MM-yyyy à HH:mm:ss`) |
| `editedBy`, `editedAt` | Read from `editNote` (`(.+?) le <date>`); the pseudo is normalized like `author` |
| `quotedByCount: Int?` | `Message cité N fois` of the trailer text, `N` as digits |
| `quotedByURL: URL?` | First `<a>` of the trailer, absolute; only read when a count was found (legacy order) |

Per block the parser materializes the table's elements once and filters that array, instead of one tree walk per lookup
(the legacy did six `findChild…` walks per message).

### What the following lots build on

- **LOT-031 (action links)**: `ExtractedMessageBlock.toolbar` holds every action element (`img[alt=answer|edit|profil]` parents, `modo.php`,
  `addflag.php`, `quoter(…)`, `dest=` MP link) and `block.numreponse`; `ObfuscatedURL.resolvedURL(from:)` decodes the class values.
- **LOT-032 (quotes)**: `ExtractedMessageBlock.content` is the untouched content element (`.citation`, `.oldcitation`, `.Topic` headers).
- **LOT-033 (page metadata)**: independent; the orchestrating `TopicPage` parser will call `extract(from:)` on the same `Document`.
- **LOT-034 (content)**: `block.contentHTML` (or `content` for a DOM pass) is the raw input; `author`, `dateText`, `editNote`, `quotedBy*`
  go straight to `Message`; `isContinuation`/`isDeleted` to the builder's classes. Signature `<span class="signature">` and the
  `<div style="clear: both;">` HFR appends are inside `contentHTML`, as served.
- **LOT-035 (embeds)**: links are inside `contentHTML`; "not in the signature" is decidable there.

## Edge cases

Checked on the captures (`Tests/HFRParsingTests/Topic/`), facts recorded in HFR-PROTOCOL §6c "LOT-030":

- Logged-out pages carry 3 advertisement blocks (1 on single-page topics): `R20` 43 tables → 40 blocks; logged-in pages carry none (`R21`).
- Pages 2+ open with the continuation block (`R22a`, `R22b`, `R24`, `R26`, `R27`, `R28`), whose quote link has `ref=0` (checked in the
  differential test for every block of every oracle: `isContinuation` ⇔ `ref=0`); page 1, single pages and MP threads have none.
- Trailer variants: cited only, edited only, both (`R32a`), none; the `quote_only=1` link is the trailer's only link.
- Avatar only on the recipient's own post of the MP thread (`RU2`); none on public captures (LOT-003 RC3.2).
- Pseudos with U+200B in the author cell (`R21` message 0, `RA1`): the oracle's `name` has none; so has `author`.
- Deleted conversation `RA5` (no block), list page `R04` (no block), MP threads `RA1`–`RA4`, `RU1`, `RU2` (1 to 5 blocks, `bas` anchor).
- Code blocks (`R27b`): `contentHTML` keeps `</li><li></li><li>` adjacent (no pretty-printing).
- Dates resolve to the right instants across CEST/CET (`R20`: posted 09-05-2004 15:23:09, edited 11-11-2018 18:24:51).
- Error paths (inline snippets, no page state involved): block without `.s2`, without `t<n>` anchor, without `para` element → typed
  `missingElement`; the public API throws `ParsingError` only.

**Pending capture** (implemented from legacy code, no positive test until a capture exists; the corpus is checked negative):

- `messagetabledel` wrapper of a deleted post (`ParseMessagesOperation.m:153`). `RA3`, captured with a deleted MP post, shows the post simply absent (LOT-003 RC3.7).
- In-topic search results: the leading `<a>` in `messCase2` that legacy prepends to the content (`:365-368`) is **not** read; its shape is unknown.
  To add when a search-result page is captured (LOT-001 checklist).
- Moderation messages (`Modération` author), blacklist/whitelist authors: policy, app-side (C10), nothing to read here.

## Fixtures

Captures (`Fixtures/captures/`, LOT-001, anonymized) and the LOT-003 oracles (`Fixtures/LOT-003/`), read in place through `oracle-map.json`:

| Case | Capture | Covers here |
|---|---|---|
| R20, R21 | page 1, logged out / in | ads vs none, 40 posts, cited + edited trailer, U+200B pseudo |
| R22a, R22b, R24 | middle, last, redirected-last page | continuation block, 33 / 10 / 10 posts |
| R23, R27b, R31 | single-page topics | 3 / 2 / 1 posts, one ad, code blocks, cited count 12 |
| R26, R27, R28 | quotes, smileys, spoilers, videos, images | continuation, trailers, content shape with nested tables |
| R32a, R32b | poll page, logged out / in | all trailer variants |
| RA1–RA4, RU1, RU2 | MP threads, both views | `bas` anchor, own posts, avatar (RU2), 1–5 posts |
| RA5 | deleted conversation | no block |

### Oracle coverage (ADR 0004)

`MessageBlockOracleTests` compares, for the 20 topic oracles (358 messages, `exception: null` everywhere), block by block:

| Oracle field (`result.messages[]`) | Compared with | Note |
|---|---|---|
| count, order (`index`) | `blocks.count`, zip order | |
| `postID` (`t<n>`) | `"t\(numreponse)"` | |
| `name` | `author` | |
| `isDel` | `isDeleted` | false everywhere (pending capture) |
| `messageDate` | `dateText` | same `dd-MM-yyyy HH:mm:ss` string |
| `editedTime` | `editNote` | oracle keeps U+00A0 (LOT-003 Q28), compared after mapping it to a space (difference 3) |
| `quotedNB`, `quotedLINK` | `quotedByCount`, `quotedByURL` | `Int(quotedNB)`, `HFRURL.absolute(quotedLINK)` |
| `imageUI` + `sideEffects.networkRequests` | `avatarURL` | a cache path means a download happened: the URL is the next recorded request (RU2 message 4); nil otherwise |
| `urlQuoteDecoded` (`ref=0`) | `isContinuation` | legacy has no flag; `ref=0` marks the block (HFR-PROTOCOL §4) |
| `dicoHTML` | `contentHTML` | **shape** comparison (`HTMLShape`): text and the element sequence with `href`, `src`, `alt`, `title`, `id`, `style`, after parsing both. Left out: `class` (legacy serialized after rewriting `oldcitation`→`citation` and marking `embedvideo`, LOT-032/035), empty `<p></p>` and formatting elements other than `a` (tree-builder differences, see below), percent-encoding of `href` (libxml2 escapes spaces) |

Out of scope, not compared (other lots): `urlQuote`, `urlEdit`, `urlProfil`, `urlAlert`, `addFlagUrl`, `quoteJS`, `MPUrl`, `url`, `iPage`
(LOT-031), `html` / `toHTML` (LOT-034 and the app-side builder), `result.actions[]` (LOT-031 + app policy), `result.page`, `result.parser`
and `result.render` (LOT-033, app).

## Intentional differences from legacy

1. **No side effects, no policy.** No avatar download or cache path (`imageUI` is a path in `Caches/`), no `MultisManager`, `BlackList`
   or `NSUserDefaults` read; the own/blacklist/whitelist/filter decisions move to app-side code on these facts (C 7.1 decision 1).
2. **`numreponse` is a number**, the `t` of `postID` dropped (`Message.id`, LOT-011); the quote link's `ref=0` becomes `isContinuation`,
   a fact legacy only mentioned in a comment.
3. **Whitespace.** `dateText`, `editNote` and the trailer text come from a whitespace-normalized text: the U+00A0 of `Message édité par <pseudo> le
   dd-MM-yyyy&nbsp;à&nbsp;HH:mm:ss` becomes a space (legacy Q28 kept it). The toolbar date requires the `à` between day and time and takes the
   **first** date; legacy's greedy `.*(dd)-(MM)-(yyyy).*(HH):(mm):(ss).*` took the last one and, without a match, kept the whole toolbar text
   as the "date" (`dateText` is `""` then). `quotedByCount` must be digits (legacy kept any text).
4. **Pseudos** lose their U+200B (`HFRText.normalizedPseudo`), as the oracle shows legacy did; compare with `pseudoComparisonKey`.
5. **Content is the inner HTML of the `para` element**, serialized by SwiftSoup's HTML5 tree builder, not libxml2's outer `<div id="para…">`
   (audit C quirk 1; LOT-003 Q32). Visible consequences on malformed markup: a stray `</p>` after HFR's `<div style="clear: both;">` gives an
   empty `<p></p>` (libxml2 dropped it), and mis-nested inline tags (`<span><strong>x</span></strong>`, R20 message 0) are reopened by the
   adoption agency algorithm. Text and data-carrying elements are identical on all 358 messages.
6. **Selectors instead of positions.** `firstChild.firstChild[name]` becomes "first `<a name="t<n>">`"; `id="para<numreponse>"` is tried
   before the legacy "any `id` containing `para`"; the deleted wrapper is matched as a class token, not as the whole attribute.
7. **Errors are typed and specific** (`missingElement("class=s2")`, `"a[name=t<numreponse>]"`, `"id=para<numreponse>"`) where legacy
   produced a `LinkItem` with nil fields; a page without blocks is `[]` in both.

## Learnings

To copy into AGENTS.md §11 when the lot closes:

- SwiftSoup pretty-prints `Element.html()` unless `document.outputSettings().prettyPrint(pretty: false)` is set first: content handed to
  another stage must be serialized with it off, or code blocks gain newlines.
- SwiftSoup's `text()` turns `&nbsp;` into a plain space (jsoup normalization); legacy `xmlNodeGetContent` kept U+00A0. Differential tests
  on trailer texts must normalize it.
- Oracle HTML from libxml2 cannot be compared to an HTML5 tree builder's output byte for byte, nor even element for element: compare text
  plus data-carrying elements, and leave out what the two builders disagree on for malformed markup (stray `</p>`, mis-nested formatting tags).
- The LOT-003 oracle's `name` has no U+200B even where the capture prints one: the zero-width space is not a property of the pseudo.
