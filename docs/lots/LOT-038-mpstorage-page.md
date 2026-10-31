# LOT-038 — MPStorage page parsing

- **Module:** HFRParsing (`Sources/HFRParsing/MPStorage/`)
- **Difficulty / model:** medium (Opus 5.5 author → Fable 5.1 reviewer; LOTS.md routes Sonnet → Opus, and the reviewer is never the author model)
- **Issue:** [#65](https://github.com/ezzz/HFRnow/issues/65) (audit item D8; old issue francoisgn/ios-app_SwiftHFR#71). ★ Critical path: LOT-052 waits for it.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow>, commit `2440d79` (an ancestor of `origin/master`).

| Legacy | Replaced by |
|---|---|
| `Classes/MPStorage.m:23` (`MP_NAME`) | `MPStorageDocument.subject` (LOT-013, unchanged) |
| `Classes/MPStorage.m:692-736` (`findStorageMPFromPage:`: GET `forum1.php?…cat=prive&page=N` `:694`; page count = last child of `fondForum1PagesHaut` `div.left` `:704-707`; rows `sujet ligne_booleen`, title cell `sujetCase3` equal to `MP_NAME` or `[non lu] MP_NAME` `:711-713`; `post=` of the title link `:714-718`; recursion to the next page `:729-731`) | `MPStoragePageParser.findThread(in:pageURL:)`; the GET and the walk are LOT-052's |
| `Classes/MPStorage.m:769-777` (thread GET: `forum2.php?config=hfr.inc&cat=prive&post=<post>&numreponse=0&page=1&p=1&subcat=0&sondage=0&owntopic=0` `:770`) | LOT-052 (not here) |
| `Classes/MPStorage.m:835-903` (`parseMPStorage:`: `destiné` anywhere in the page `:837`; first `messagetable`, second `td`, id containing `para` → `numreponse` `:878-881`; first `<p>` text, U+00A0 removed `:882-883`; `NSJSONSerialization` `:886`; malformed JSON turns the feature off `:888-891`) | `MPStoragePageParser.readDocument(in:)` |

Oracle analysis: [LOT-004](LOT-004-forms-storage-oracle.md) rows `mpstorage-page` and `mpstorage-op` `find`, quirks 16 and 18-20, results RC4.6 and RC4.7.

## Behaviour

### `MPStoragePageParser.findThread(in:pageURL:) throws(ListPageFailure) -> MPStorageThreadSearch`
Pure. One page of the MP list, read by `PrivateMessageListParser` (LOT-023), so its failures are this parser's (login wall, maintenance, a list that is not `cat=prive`).

| Output | Rule |
|---|---|
| `.found(post:)` | the first row whose title is exactly `MPStorageDocument.subject` or `[non lu] ` + subject; `post` = the row's `topicID.topic` (the `post=` of its title link). LOT-023 already removes the `[non lu]` marker HFR prints as `span.red` (R13u1, R13u1b); the prefixed form is kept for a title cell that holds the words without the marker, as legacy compared the whole cell |
| `.notOnPage(navigation:)` | no such row; `navigation` is the LOT-022 pager of the page. The caller walks on with `nextPath` while there is one |

A title that merely contains the subject (`Re: …`, a suffix, other case) does not match. A row without a readable `post` is skipped, as legacy's loop did.

### `MPStoragePageParser.readDocument(in:) throws(MPStoragePageError) -> MPStorageThreadPage`
Pure. The storage thread's first page, in this order:

1. The page and its message blocks are read by `MessageBlockParser` (LOT-030); a failure there is `.unreadablePage(ParsingError)`.
2. No message block: a `.hop` notice holding `destiné` ("Ce message ne vous est pas destiné, désolé", `RA5`) is the result `.notAddressed` (the cached `post` is stale, legacy cleared it and searched again, quirk 19); any other page without messages (login wall, `R12`'s notice, a list) is `.noMessage`.
3. The first block is the continuation copy of a previous page (`isContinuation`, LOT-030): `.notFirstPage`.
4. The title row's `h3` (LOT-033 reader) is not the subject: `.notStorageThread`.
5. The first `<p>` of the first message's content element (`div#para<numreponse>`), its raw text (entities decoded, whitespace kept) with every U+00A0 removed, is the document text. None: `.missingParagraph`.
6. `MPStorageCodec.decode` (LOT-062) reads the text unchanged: numbers keep their lexemes (LESSONS 31). A throw is `.invalidDocument`.
7. The result is `.storage(MPStorageMessage(numreponse:text:document:))`, `numreponse` from the block (`t<numreponse>` anchor).

Error payloads never carry page text: the document holds pseudos.

## Edge cases
- Several rows with the subject (two storage threads): the first in page order wins, as legacy. Which one other clients write to is not known.
- HFR renders the stored text as a message: a smiley code, an auto-linked URL or BBCode inside a JSON string would be rewritten in the page, and the page text would no longer be the stored text. The edit form (`R60b`) holds the document byte for byte (RC4.7). Not observed: the only captured document is empty (pending capture below). LOT-052 may prefer the edit form's `content_form` for the text it writes back.
- U+00A0 is removed everywhere, inside strings too, as legacy: a stored non-breaking space is lost on read. Not observed (R60a holds none).
- The JSON paragraph in `R60a` is followed by `<div style="clear: both;">`, which the HTML parser moves out of the `<p>`: the text ends at the JSON's closing brace.

## Fixtures
| Fixture | Covers |
|---|---|
| `R13u1`, `R13u1b` + `LOT-004/S-find-R13u1(b).oracle.json` | storage row on page 1, with HFR's `[non lu]` marker: `post` 3157083, as the oracle's `sPostId` |
| `R13a` + `S-find-R13a.oracle.json` | no storage row, one page: `.notOnPage`, no next page (the oracle made one GET) |
| `R60a` + `R60a.oracle.json` | the storage thread's first page: `numreponse` = `sNumRep`, document = `dData`; the text equals the raw paragraph with `&#034;` decoded |
| `RA5` | "Ce message ne vous est pas destiné, désolé" → `.notAddressed` |
| `RA1`, `RU1`, `R20` | other threads and a public topic → `.notStorageThread` |
| `R22a` | page starting with the continuation copy → `.notFirstPage` |
| `R13a`, `R12` | pages without messages, `R12` with a `.hop` notice that is not the "destiné" one → `.noMessage` |

**Pending capture** (never hand-built, LESSONS 36):
- A document with other clients' namespaces, member pseudos, near the 64 KiB cap, with a non-BMP character, or with U+00A0 / smiley codes inside strings ([#272](https://github.com/ezzz/HFRnow/issues/272), waits for an operator decision). Until then the U+00A0 removal and `.invalidDocument` are covered by the codec's own tests, not by a page.
- A storage thread found on page 2 or later of the MP list, and the "destiné" page answered for the storage thread itself ([#333](https://github.com/ezzz/HFRnow/issues/333)); `RA5` is the same notice on another MP thread.
- An MP list page past the last page ([#114](https://github.com/ezzz/HFRnow/issues/114)).
- A storage message without a paragraph (`.missingParagraph`), and a storage thread's page 2 (`.notFirstPage` on the storage thread itself).

## Intentional differences from legacy
1. **Pager**: the next page comes from the LOT-022 pager (`navigation.nextPath`), not from the last child of `div.left`, which is a window on long lists (LOT-004 RC4.6).
2. **"destiné"**: looked for in the `.hop` notice of a page without messages only; legacy searched the whole page, so a stored or quoted text holding the word made it drop its cached thread and search again.
3. **Subject check**: the thread page must carry the storage subject; legacy read the first message of whatever thread the cached `post` named, and would have written its update over it.
4. **First page only**: a page starting with the continuation copy is refused; legacy read that copy as the document.
5. **Malformed JSON** is a typed error; legacy showed an alert and turned the feature off for every account (quirk 18). What to do is the caller's decision (LOT-052, LOT-130).
6. **No side effects**: no cached `post`, no alert, no request; those are LOT-052's and the app's.

## Learnings
- `RA5` (an MP thread the account cannot see) is HFR's "destiné" page: the capture exists before anyone asked for it under that name. Search the corpus manifest for a page's sentence before opening a capture issue.
