# LOT-052 — MPStorage transport

- **Module:** HFRClient (`Sources/HFRClient/MPStorage/`), plus two endpoint builders in HFRNetwork
- **Difficulty / model:** difficult (Opus 5.5 author → Fable 5.1 reviewer)
- **Issue:** [#78](https://github.com/ezzz/HFRnow/issues/78) (audit D8; old issue francoisgn/ios-app_SwiftHFR#80). ★ Critical path.
- **Builds on:** LOT-038 (`MPStoragePageParser`, plus `locateMessage` added here), LOT-048 (`PostingFlow`), LOT-062 (`MPStorageCodec`, `MPStorageMerge`), LOT-031 (`MessageActionsParser`), LOT-041 (endpoints).

Find, read, create and write the account's MPStorage document, the JSON first message of the private thread titled
`MPStorageDocument.subject`. Caching the thread id, the per-account on/off state, when to sync and what to show are the
app's (LOT-130).

## Legacy sources
Legacy repository <https://github.com/ezzz/HFRnow> at `2440d79`, `Classes/MPStorage.m`.

| Legacy | Replaced by |
|---|---|
| `:692-736` `findStorageMPFromPage:` (GET of the MP list page N with the main account's cookies, row match, recursion to the last page of the pager window) | `MPStorageTransport.findThread(in:)`: LOT-038 per page, `PageNavigation.nextPath` to walk |
| `:769-777` `GETRequest` (`forum2.php?config=hfr.inc&cat=prive&post=<post>&numreponse=0&page=1&p=1&subcat=0&sondage=0&owntopic=0`; its callers do not follow redirects, `:841, 943`) | `HFREndpoint.privateThreadFirstPage(post:)` |
| `:835-903` `parseMPStorage:` (document from the rendered page; `destiné` clears the cached id and searches again, or offers to create) | `read(post:in:)`: the page only locates the message (`MPStoragePageParser.locateMessage`, no decode), the document comes from its edit form; `notAddressed` is returned, the re-search is the caller's |
| `:738-767` `createEmptyMPStorage` (hand-made POST to `bddpost.php`, `dest=MultiMP`, `sujet=MP_NAME`, success = "succès" anywhere) | `create(stamp:in:)`: the new-MP form (`R45b`) posted by LOT-048 |
| `:780-833` `POSTRequestWithData:newMessage:` (hand-made field list, main account's `hash_check` or the global one) | the forms' own fields and token, through the account's session (LOT-048, Q-8) |
| `:905-930` `saveMPStorageSynchronous` (whole document, last writer wins, "succès" anywhere) | `save(_:base:at:stamp:in:)`: merge, LOT-048 edit, read back |
| `:932-967` `saveMPStorageAsynchronous` (POST, then a GET of the thread page checked for "succès", which a thread page never holds: always reported failed) | same `save` |

## Behaviour

`MPStorageTransport`, public entry points on `HFRSession`; every request goes through that session (the account whose
storage it is; legacy used the main account's cookies, `:696-698, 772-774`).

1. **Find** — GET `HFREndpoint.privateMessages(page: 1)`, then each page's `nextPath`, read by
   `MPStoragePageParser.findThread`. `.found(post)` returns the id; a page without next page returns nil. A final URL
   off the forum, a next link off the forum (`https`, forum host, default port), or a pager whose current page does not
   grow is `unexpectedPage`. After `maximumListPages` (50) pages without an end: `searchLimitReached`, never nil, so
   the app never creates a second thread because the search stopped early. A parser failure is `list(ListPageFailure)`.
2. **Read** — GET `privateThreadFirstPage(post:)`, redirects not followed (a 3xx or an answer off the forum is
   `unexpectedPage`); `MPStoragePageParser.locateMessage` (LOT-038's checks up to the subject, without reading the
   message text, so a document HFR renders unlike its stored text still reads): `.notAddressed` (`RA5`) is
   `notAddressed` (stale id: find again), its errors are `threadPage(_)`. The first message's toolbar edit link
   (LOT-031) must be `https://forum.hardware.fr/message.php` with exactly one
   `cat=prive`, `post=<post>` and `numreponse=<first message>` (`editLinkMissing` otherwise). That form is loaded by
   LOT-048 (`R60b`) and must be an edit form of a private thread with `post`, `numreponse` and `sujet` equal to the
   expected values (`notStorageForm`). The document is its `content_form`, decoded by LOT-062 (`invalidDocument`).
   Result: `MPStorageSnapshot(location, text, document)`.
3. **Save** — `save(ours, base:, at: location, stamp:)`: load the edit form again (theirs, checked as in 2), merge
   `MPStorageMerge.merge(base:ours:theirs:stamp:)`. `needsWrite == false`: nothing is sent, `wrote == false` with the
   forum copy. Otherwise `MPStorageCodec.encodeForWriting` (refusals: `document(MPStorageError)`, nothing sent), LOT-048
   `edit` with the form's fields as served (the `delete` box never sent), then the edit form is read once more: its
   `content_form` must equal the text sent, byte for byte, else `notVerified(readBack: nil)`; a read-back that fails
   is `notVerified(readBack: <its error>)`. Either way, save again: `save` re-reads and merges. LOT-048's errors are
   `posting(_)`; `posting(.unconfirmed)` may have been stored. A stale location (thread deleted from another device) is
   `posting(.formUnavailable)` here, not `notAddressed` (the edit form's answer for it is not captured): find again.
4. **Create** — `create(stamp:)`: find first, and an existing thread is read and returned as `.existing` (no POST: a
   retry after an unconfirmed creation, or another device's thread). Otherwise GET
   `HFREndpoint.newPrivateMessageForm(to: "MultiMP")` and LOT-048 `newPrivateMessage(to: "MultiMP", subject:, text:)`
   with legacy's empty document (`:740`: one `0.1` entry, three empty sections, every level stamped with `stamp`).
   HFR's answer names no thread (`W10`): find again, then read (`.created`); not found is `notFoundAfterCreation`.

Errors (`MPStorageTransportError`) never carry the document text: it holds pseudos. In `findThread`, `read` and `save`, only
`posting(.unconfirmed)` and `notVerified` may follow a write. In `create`, an error of the search or read after HFR
confirmed the thread (and `notFoundAfterCreation`) leaves a thread on the forum; calling `create` again finds it.

## Edge cases
- **Concurrent writer** between our form read and our POST: the merge cannot see it; the read-back detects it
  (`notVerified(readBack: nil)`) and the caller saves again, which merges with that copy. LOT-062 limit 3: narrowed, not closed.
- **Another account's location**: the app keys `post` per account; an edit form of another account's message is served
  (`R44`) but carries no `delete` box and HFR's answer to its POST is not captured: the subject and thread checks pass
  only on a storage thread, so the remaining risk is the app passing another account's location.
- **Rendered page that does not decode** (a stored block tag or smiley code rendered by HFR, not observed): the page is
  only used to locate the message, so the edit form's text is still read. Pending #272.
- **Flood**: a refused creation (`W11x`, one new thread per 60 min) is `posting(.rejected)`.
- **Cancellation**: checked before each GET (`network(.cancelled)`); LOT-048 checks it before the POST.

## Fixtures
Shared corpus, no new file: `R13a`, `R13u1` (list without / with the thread), `R60a` (thread page), `R60b` (edit form,
its content = the LOT-004 oracle's `contentForm`), `RA5` and `R96b` (not addressed; `R96b` is another account's storage thread at the URL this lot sends), `RA1` (another thread), `R43a` (another
edit form), `R45b` (new-MP form) → `W10` (create answer), `W15` (edit answer), `W17a` (refusal). Tests that need the
stored copy after a write serve `R60b` with its `content_form` replaced by the text sent: HFR stores an edit's text as
sent (`R43a`, X11). One test renames `R60b`'s `sujet` to reach the subject check alone.

**Pending capture** (never hand-built, LESSONS 36):
- An MP list with the storage thread on page 2 or later (#333, not reachable with the kit's accounts): the walk is
  tested with pager values (`MPStorageListWalkTests`), not with pages.
- A non-empty document from other clients, near the 64 KiB cap, with U+00A0 or smiley codes (#272).

**Captured since** ([#440](https://github.com/ezzz/HFRnow/issues/440), 2026-11-10; HFR-PROTOCOL §6c LOT-052): the storage creation
answer `W440a` (the `W10` answer) and the storage write answer `W440b` (the `W15` answer); the edit-form GET of the storage message
by another account (`R440a`) and after the thread was deleted, by its owner (`R440b`) and by another account (`R440c`): all three are
`RA5`'s "Ce message ne vous est pas destiné, désolé" page, no form; the edit POST of another account's message (`W440c`): refused,
"Vous n'avez pas les droits pour éditer ce message !" (a link-less `.hop` with no refresh, so `save` reports it
`posting(.unconfirmed(.unrecognizedAnswer))`, never a success; `rejected` is [#756](https://github.com/ezzz/HFRnow/issues/756)).
Tests in `MPStorageTransportWriteTests`, one per state.

## Tests
`MPStorageTransportReadTests`, `MPStorageTransportWriteTests`, `MPStorageListWalkTests` (HFRClientTests),
`HFREndpointReadTests` (HFRNetworkTests): find on page 1 / not found in one GET / a non-list page / a list served
from another host; `locateMessage` on `R60a` (oracle `numreponse`, edit link), `RA5`, other pages, a broken paragraph; read through page and form (URLs, no-redirect policy, edit link = `R60b`'s URL, no POST); `RA5`
stale; `R96b` (another account's storage thread) stale; another thread; a redirect; a page answered from another host; a rendered text that is not JSON read from the form; another edit form; another subject; an unreadable stored document; a timeout;
edit-link checks (other message, thread, category, path, `http`, a repeated `post`); save with nothing to write (no
POST), with an edit (body fields, `bdd.php`, GET-POST-GET), with a concurrent write merged, with a non-BMP value
refused before the POST, with a read-back that differs or fails, a lost answer (one POST, unconfirmed) and a refusal;
create with an existing thread (no POST), a new thread (request order, new-MP URL, `dest`, `sujet`, empty document), a creation the
list does not show; the empty document equals legacy's (`R60b`); the walk to page 3, its end, a pager that does not move,
next links off the forum, the page limit; the two endpoints.

Shown to fail without: the read-back comparison, the subject check, the find before creating, the pager progress check; after the Fable review, a locate that decodes the page text.

## Intentional differences from legacy
1. **The document is read from the edit form**, not the rendered page (HFR-PROTOCOL §7 X8): what is written back is
   what was stored.
2. **Writes merge** with the copy re-read just before writing (LOT-062) instead of overwriting it, and are read back.
3. **Success needs HFR's sentence for that write** (LOT-048), not "succès" anywhere in the page; the asynchronous
   save no longer reports every save as failed (`:956-967` looked for "succès" in a thread page).
4. **The account's own session and form token**, not the main account's cookies and a stored or global `hash_check`.
5. **No create without a full search**: the search stops with an error at its limit instead of "not found", and
   `create` searches first.
6. **No side effects** (alerts, `mpstorage_active` off, cached ids): reported as errors for the app (LOT-130).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A write whose answer names nothing (MP creation) is found again by the same search the read uses; search before
  creating, so a retry after an unconfirmed creation cannot make a second thread.
