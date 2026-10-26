# LOT-004 — Oracle exporter: write-flow forms, write responses and storage formats

- **Module:** tooling (legacy app)
- **Difficulty / model:** medium (Sonnet → Fable)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

Harness, patch and run instructions: [`tooling/legacy-oracle/`](../../tooling/legacy-oracle/README.md) (shared with LOT-002 and [LOT-003](LOT-003-topic-oracle.md)).
This lot adds three kinds: `form` (the `hop` form extraction and POST body of every write flow), `response` (the classifier of
write responses) and `storage` (MPStorage and the legacy on-device formats). They are the expected values for the write
flows in `HFRClient`, LOT-067, LOT-062 and LOT-065.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow>, commit `2440d79`. Paths from the repository root.

The composer view controllers (`QuoteMessageViewController`, `AddMessageViewController`, `AlerteModoViewController`) are compiled
only into the old SuperHFRplus target, not the test host. Their steps are **transliterated line by line** into Objective-C
(`HFRswiftTests/OracleLegacyWrite.m`) and run on the real building blocks (libxml2 `HTMLParser`/`HTMLNode`, `ASIFormDataRequest`
URL encoding, `-[NSString removeEmoji]`, RegexKitLite, `k.ForumURL`). Everything else (`MPStorage`, `BlackList`, `SmileyCache`,
`OfflineStorage`, `Topic`, `MultisManager.getComtpes`, `A0SimpleKeychain`) is the real class, called directly. The live Swift
services run unmodified over a stub `URLProtocol`, with a group-container `HTTPCookieStorage` (`oracle-lot004`): that store is
persistent (on the simulator's disk, across runs), so the exporter empties it for every case; the stubs set no cookie.

| Kind / part | Legacy code | Source |
|---|---|---|
| `form`, flavor hop (reply, quote, edit, delete, new topic, MP): fetch + input/select/textarea extraction | `QuoteMessageViewController` | `Classes/QuoteMessageViewController.m:112-533` (form part `209-290`, `459`, `532`) |
| `form`, flavor modo (alert) | `AlerteModoViewController` | `Classes/AlerteModoViewController.m:144-178` |
| `form`, POST body | `-done` (`ASIFormDataRequest` fields, `content_form` `\n` to `\r\n`) | `Classes/AddMessageViewController.m:513-570`; alert: `AlerteModoViewController.m:198-213` |
| `form`, live side | `ForumReplyPostingService`, `ForumReplyQuoteTemplateService`, `ForumMessageDeletionService`, `ForumModerationAlertService` | `HFRswift/Swift/ReplyService.swift:145-183` (reply), `311-341` (inputs), `343-365` (selects), `741-920` (quote), `922-1398` (deletion), `1400-1733` (alert) |
| `response`, reply/edit/new topic/MP | success/failure test after the POST | `Classes/AddMessageViewController.m:586-622` |
| `response`, alert | prepare (already alerted) and submit | `Classes/AlerteModoViewController.m:154-163`, `229-236` |
| `response`, live side | hop message, refresh anchor/URL, logged-out, success | `HFRswift/Swift/ReplyService.swift:579-625`, `627-668`, `670-679`, `681-695` |
| `response`, `flow: mpstorage` | `succès` check after create/update | `Classes/MPStorage.m:752-761` (create), `921-924`, `961-964` (update) |
| `storage` `mpstorage-page` | `-parseMPStorage` (JSON from the first message's `<p>`), then `-updateBlackList` | `Classes/MPStorage.m:835-903` |
| `storage` `mpstorage-op` | add/remove blacklist word and bookmark, find, create, update; POST fields | `Classes/MPStorage.m:692-736` (find), `780-833` (POST fields) |
| `storage` `keychain` | account blob (`NSKeyedArchiver` of an array of dictionaries), `getComtpes` | `Classes/MultisManager.m:44-101` |
| `storage` `blacklist` | `blackList.plist` (v0), `blackListDico.plist`, `whiteList.plist` | `Classes/BlackList.m:163-202` |
| `storage` `smileys` | `arrFavoritesSmileysApp`, favourites archive | `Classes/SmileyCache.m:18-35`, `353-439` |
| `storage` `offline` | offline topics archive | `Classes/OfflineStorage.m:88-143`, `Classes/Topic.m:101-157` |

Not covered, on purpose: the selection-quote / `textQuote` logic of `QuoteMessageViewController` (it builds the prefill client-side
from a web selection, not from a page), the hash fallback to the app delegate when no account hash exists, and the real
Keychain (see Open questions).

## Inputs

`oracle-map.json` entry: `{"kind": "form" | "response" | "storage", ...options}`. Common envelope as in LOT-002 (`case`, `kind`,
`schema`, `legacyCommit`, `exception`, `input`, `result`, `sideEffects`); `input.context` holds the effective inputs.

### `form`

| Option | Meaning | Default |
|---|---|---|
| `mode` | `reply`, `quote`, `edit`, `delete`, `newtopic`, `mp`, `alert` (flavor modo) | `reply` |
| `url` | fetch URL (the live service merges its query items into the POST, quirk 2) | a reply URL |
| `message` | text posted in `content_form` (the reason posted in `raison` in `alert` mode, default `Alert reason`); for `quote`/`edit`/`delete` the default is the page prefill | a fixed test text |
| `overrides` | `sujet`, `subcat`, `dest` overrides | none |
| `mutatePostedContent` | self-test: corrupts the text the self-check expects, the case must then fail (`exception` = `OracleSelfCheck: …`, no `result`) | off |
| `session` | `pseudo`, `hash` (fake) | `fakeuser1`, fake 40-hex |

### `response`

| Option | Meaning | Default |
|---|---|---|
| `flow` | `reply` (also edit/new topic/MP), `delete`, `alertSubmit`, `alertPrepare`, `mpstorage` | `reply` |
| `status` | HTTP status served | `200` |
| `charset` | `iso-8859-1`: the encoding the legacy decoding is told about, and the one used on the MPStorage path. The live stub always answers `utf-8` | `utf-8` |
| `urlQuote` | URL of the request the response answers (the numreponse is read from it) | a reply URL with `numreponse=1003` (alert flows: the modo URL) |

### `storage`

`storage` is one of `mpstorage-page` (input: an HTML MP page), `mpstorage-op` (input: JSON `{op, args, dData, postId, numRep, responses}`),
`keychain`, `blacklist`, `smileys`, `offline` (input: JSON spec of the synthetic data). `pseudo` defaults to `fakeuser1`.
The current pseudo and hash hooks (`MultisManager getMainCompte`/`getCurrentPseudo`) are installed for all sub-kinds, because
`BlackList.load` returns early without a current pseudo. The shared `MPStorage` is reset for every `storage` case (`dData`, `sPostId`,
`sNumRep` cleared, `listBookmarks` emptied) and, for `storage` and `response` with `flow: mpstorage`, its flags are set back to their launch
values (`bIsActive` NO, `bIsMPStorageSavedSuccessfully` YES, `MPStorage.m:71-72`), so a failed save does not leak into the next case.

## Output (schema 1)

### `form`: `result`

```json
{
  "legacy": {
    "fetchURL": "…", "formAction": "/bddpost.php?config=hfr.inc", "formSubmit": "https://forum.hardware.fr/bddpost.php?config=hfr.inc",
    "inputData": {"cat": "13", "post": "…", "subcat": "433"}, "loopOrder": ["…"],
    "contentForm": "prefill or null", "contentFormRaw": "…", "postedContent": "…",
    "isLogged": true, "username": "fakeuser1", "haveCategory": true, "haveTitle": true, "haveTo": false,
    "subcats": [{"id": "433", "title": "…"}], "smileys": [],
    "raisedInLegacy": [], "subcatException": null,
    "post": {"method": "POST", "url": "…", "contentType": "application/x-www-form-urlencoded; charset=utf-8",
             "pairs": [["ColorUsedMem", ""], ["cat", "13"]], "bodySorted": "ColorUsedMem=&cat=13&…", "bodyBytes": 444}
  },
  "live": {"composerContext": {"subject": "…", "recipient": null, "selectedSubcategoryID": "433",
                                "subcategoryOptions": [], "isSubjectEditable": false, "isSubcategoryEditable": false},
           "post": {"method": "POST", "url": "…", "contentType": "…", "pairs": [], "bodySorted": "…",
                    "bodyOrder": "unspecified (Swift Dictionary iteration)"}},
  "comparison": {"comparable": true, "sameUrl": true, "legacyUrl": "…", "liveUrl": "…", "onlyLegacy": [], "onlyLive": [], "different": []}
}
```

`legacy.postedContent` and `live.postedContent` are the text actually posted (`content_form`, or `raison` for an alert), line breaks as `\n`; `live.postedContent` is null when the live service sent no POST (anonymous form, already alerted). The harness checks each against the sorted `pairs` of its own POST and fails the case (`OracleSelfCheck`) on a mismatch.

For `alert` mode, `legacy` has `alreadyAlerted`, `hopText`, `inputData`, `formAction`, `formSubmit`, `post`, `postedContent`.
`raisedInLegacy` lists the `NSException`s raised by the legacy steps (caught and recorded; the Objective-C code would crash
the app). `bodySorted` and `pairs` are sorted by name because both stacks build the body from an unordered dictionary. Legacy
percent-encodes spaces as `%20`, the live encoder as `+`. The hash is a fake one.

### `response`: `result`

```json
{
  "legacy": {"classification": "success | rejected | …", "message": "…",
             "anchor": "#t1003", "anchorMatches": 1, "decoded": true, "hopFound": true, "hopHasLink": false, "hopHasInput": false},
  "live": {"ok": true, "refreshAnchor": "t1003", "refreshURL": "…", "statusMessage": "…"}
}
```

`live` is `{"error": "<case>", "message": "…"}` on failure (`submissionRejected`, `authenticationRequired`, `serverError`, …).
`flow: mpstorage` adds `mpSave` and `mpCreate`: the result of the real `MPStorage` save/create run on the page
(`returned`, `exception`, `bIsMPStorageSavedSuccessfully`, `alerts`).

### `storage`: `result`

| Sub-kind | Keys |
|---|---|
| `mpstorage-page` | `parse` (`returned`, `exception`), `state` (`dData`, `listBookmarks`, `blackListOfActiveAccount`, `mpstorage_active`, `sNumRep`, `sPostId`, `dicMPStorage_postid`, `bIsMPStorageSavedSuccessfully`), `updateBlackList`, `alerts`, `requests` |
| `mpstorage-op` | `op`, `returned`, `exception`, `state` (as above), `requests` (`method`, `url`, `pairs`, `contentType`), `alerts`, `unusedResponses` |
| `keychain` | `archiveBase64`, `archiveBytes`, `archiver`, `archiveTopLevelKeys`, `decoded` (array of `PSEUDO`, `PSEUDO_DISPLAY`, `HASH`, `MAIN`, `COOKIES`, `AVATAR` as `{"$data": base64, "bytes": n}`), `multisManagerGetComtpes`, `keychainRoundTrip` |
| `blacklist` | `blackListDicoPlist`, `whiteListPlist` (XML text), `loaded` (`dicBlackList`, `listWhiteList`), `v0Input`, `v0AfterLoad` |
| `smileys` | `archiveBase64`, `loadedDicFavoritesSmileys`, `arrFavoritesSmileysApp`, `realSave` |
| `offline` | `archiveBase64`, `loaded` (per post id: `aTitle`, `aURL`, `catID`, `postID`, page counters, `dDateOfLastPost`, …) |

Determinism: timestamps within 3 days of "now" (`TIMESTAMP`, `createDate`, `lastUpdate`, `dateBookmarkCreation`) are exported as
`<now-ms>` / `<now>`; cookie archives use a fixed `Created` property and a fixed expiry (`2027-03-01`), so the bytes are reproducible.
`NSHTTPCookie` caps an expiry later than now + 400 days to now + 400 days, and keeps an earlier one, past dates included, as given
(probed on macOS 27 Foundation: `2099-01-01` became now + 400 days, `2020-01-01` and `2027-03-01` were kept). A fixed date that is
within the cap today stays within it, so the sample does not change once 2027-03-01 has passed; never move it beyond now + 400 days.
Keychain bytes are those of a **synthetic** account (fake pseudo, fake hash, no password).

## Quirks observed by running

Legacy versus live (the live side is the current Swift code; "B" numbers are those of the audit):

| # | Observation | Source |
|---|---|---|
| 1 | Live `composerContext.subject` keeps HTML entities (B1); live `sujet` is then posted double-encoded (`Topic &amp; &quot;fun&quot; l&#039;ami`), legacy posts the decoded value | `ReplyService.swift:311-341` vs `QuoteMessageViewController.m:209-290` |
| 2 | Live merges the fetch URL's query items (`ref`, `subcat`, `subcatgroup`) into the POST (B3); legacy does not | `ReplyService.swift:145-183` |
| 3 | Live regex picks `data-name="decoy"` as a field `decoy` and misses `real` | `ReplyService.swift:311-341` |
| 4 | Bare `checked`: legacy `"1"`, live `"0"`. A checkbox without `value`: live `"1"`, legacy skips it. Legacy skips every input without a `value` attribute | `QuoteMessageViewController.m:209-290` |
| 5 | Modo action `&amp;` is decoded by legacy, kept by live (`sameUrl: false` on the real capture R46) | `AlerteModoViewController.m:144-178`, `ReplyService.swift:1400-1733` |
| 6 | Meta-refresh URL keeps `&amp;` in live; legacy only needs the `#fragment` | `ReplyService.swift:627-668` |
| 7 | Refresh **plus** a `.hop` link: live says success, legacy says rejected (B4) | `AddMessageViewController.m:586-622` |
| 8 | Missing `.hop` and HTTP 5xx: legacy "success" (ASIHTTPRequest has no HTTP-status error); live `serverError`/`submissionRejected`/`authenticationRequired` | `AddMessageViewController.m:586-622` |
| 9 | Legacy anchor includes `#` (`#t1003`), is `""` without one; for delete the anchor is the `numreponse` digits | `AddMessageViewController.m:586-622` |
| 10 | Anonymous reply form: legacy `formSubmit` is `https://forum.hardware.fr(null)`; an empty textarea gives `contentForm` null. The same page counts as **logged in** (`isLogged: true`, `username: ""`): any `hash_check` input with a value sets it, and the fastsearch form of an anonymous page carries one. LOT-036 must not infer the login state from `hash_check` alone | `QuoteMessageViewController.m:127-133,459,532` |
| 11 | "Pretty" selects (whitespace between `<option>`) make legacy raise (`initWithString:nil`, `setObject:nil`); real compact HFR HTML does not | `QuoteMessageViewController.m:209-290` |
| 12 | Live concatenates link text into the hop message (`… Aide`) | `ReplyService.swift:579-625` |
| 13 | `safeResponseString` iconv drops non-UTF-8 bytes: a Latin-1 response loses its accents and `succès` is never found. Live falls back to Latin-1 | `SuperHFRplus/Helpers/ASIHTTPRequest+Tools.m:40-48` (iconv in `safeResponseData`, `:14-38`) |
| 14 | Raw POST body order is random per process on both sides (`NSDictionary`, `Dictionary`) | `AddMessageViewController.m:513-570` |
| 15 | Wire: `ASIFormDataRequest` encodes spaces `%20`, live `+`; content type `application/x-www-form-urlencoded; charset=utf-8` | `AddMessageViewController.m:513-570` |
| 15b | Legacy strips emoji from the posted text (`-[NSString removeEmoji]`, `AddMessageViewController.m:553-554`; `AlerteModoViewController.m:209-211`): `😀` and `☺` are removed, `❤` is kept (sample `form-reply-emoji`). Live posts the text unchanged. `legacy.postedContent` is the text legacy really sent | `AddMessageViewController.m:553-554` |

MPStorage and on-device formats:

| # | Observation | Source |
|---|---|---|
| 16 | Bookmarks whose `post`/`cat` are JSON strings parse fine (`stringValue`); a new bookmark writes `numreponse` as a **string** (`"777"`), other clients write numbers | `MPStorage.m:835-903` |
| 17 | Adds bump the root `lastUpdate` only, not the section's; `removeBlackList` bumps no `lastUpdate` | `MPStorage.m` |
| 18 | Malformed JSON: `mpstorage_active=false`, `sNumRep` stays set | `MPStorage.m:835-903` |
| 19 | `destiné` page: cached postid cleared, a find GET is issued, an OKCancel alert is shown | `MPStorage.m:837-849` |
| 20 | `find` caches `dicMPStorage_postid = {pseudo: postId}`; create POSTs `bddpost.php` with `dest=MultiMP`, update POSTs `bdd.php` | `MPStorage.m:692-736,780-833` |
| 21 | BlackList v0 migration: `blackList.plist` is deleted, `blackListDico.plist` is **never written** (the dictionary lives in memory only). A ZWSP in a pseudo survives in the plist | `BlackList.m:163-202` |
| 22 | `arrFavoritesSmileysApp` is sorted by `dateAdded` ascending; the real save stamps `[NSDate now]` | `SmileyCache.m:353-439` |
| 23 | Keychain service `hfrplus.red.super`; the blob is a keyed archive of an array of dictionaries; `getComtpes` returns exactly the decoded blob | `MultisManager.m:44-101` |

### Real captures

Computed on the LOT-001 corpus (`Fixtures/LOT-004/`, 37 cases, read in place through the map's `path`; about 0.7 MB; `errors.json` empty; two full runs byte-identical):

| Kind | Cases (corpus ids) | Inputs taken from the capture's meta |
|---|---|---|
| `form` (16) | R40a, R40b (reply), R41a, R41b, R47a (quote), R42, R47c (quote with multi-quote cookie), R43a, R43b, R43c, R44 (edit), R45a (new topic), R45b (new MP), R46 (alert), R47b, R47u1 (MP reply) | `url` = the meta's `final_url`, `session.pseudo` = the account's alias (`user1` as placeholder for the anonymous R40b); the session hash is the harness's fake 40-hex, so `post.pairs` holds `0123...4567`; `inputData.hash_check` is the corpus `REDACTED` |
| `response` (18) | W10, W11, W11x, W12, W13b, W13c, W13cx, W14, W14x, W15, W17a, W17b, W17c, W20a, W20b (`reply` flow), W16a, W16b, W19 (`delete` flow) | `urlQuote` built from the captured POST body (`cat`, `post`, `numreponse`), `status` from the meta |
| `storage` (3) | `S-find-R13u1`, `S-find-R13u1b` (user1), `S-find-R13a` (user2): `mpstorage-op` `find` over the MP list page (spec files `S-find-*.json` beside the map) | |

Not run: the login pages W00/W01/W01b/W03 (not a write response of the classifier), the GET-only flag pages W18 and P03* (`nonlu.php`, `addflag.php`, `delflag.php`), search POSTs R50a/R52, and the storage sub-kinds that need a MPStorage **thread page**
(`mpstorage-page`, `update`, `create`) or on-device data (`keychain`, `blacklist`, `smileys`, `offline`): the corpus has no capture of them.

### Real-capture findings (`RC4.n`)
Each item contradicts or refines an assumption above.

- RC4.1 (quirks 2, 4, 5) **The legacy-versus-live differences are real, not synthetic.** Identical POST on R40a, R40b, R42, R44, R45a, R47b, R47c, R47u1. Differences: R41a, R41b, R47a `onlyLive: ["ref"]` (quirk 2, the URL's `ref` is merged by live);
  R43a, R43b, R43c `onlyLive: ["delete"]` (and `subcat` on R43a): live posts `delete` on an edit form where legacy skips the valueless checkbox (quirk 4); R45b `onlyLive: ["subcat", "subcatgroup"]` (quirk 2 said only `subcat`);
  R46 `sameUrl: false`, the action keeps `&amp;` in live (quirk 5).
- RC4.2 (quirk 10) **The real anonymous composer is not "logged in".** R40b gives legacy `isLogged: false`, `username: ""`, `contentForm: null`: its `hash_check` is empty. The quirk-10 case (anonymous page counted as logged in) needs a page whose fastsearch carries a
  `hash_check` value; it does not occur on R40b. The map runs R40b with `session.pseudo: user1` on purpose: it models an app that still has an account while the server session has expired. Real action: `/bddpost.php?config=hfr.inc` (reply), `/bdd.php?config=hfr.inc` (edit, R43a-c, R44), and the alert form posts to `modo.php?cat=...` with a **relative** action (R46).
- RC4.3 **Edit and prefill on real pages.** R43a-c carry the stored text as sent (`fixture-test 1, line 1 (CRLF)\nline 2`: legacy reads it back with `\n`, the CRLF is rebuilt on POST); the first post of an MP has the title field (`haveTitle true`, R43a), later posts do not;
  R44 (edit form requested on the other account's message) is served and parses like any edit form (`isLogged true`, no `raisedInLegacy`): the server, not the form, refuses to save. R42 and R47c show the multi-quote prefill (`[quotemsg=2666649,1,910001]...`).
  R45a has 16 `subcat` options in compact HTML: no `raisedInLegacy` (quirk 11 does not occur on real pages).
- RC4.4 (quirk 8) **Real response texts and classes.** Success: new MP "Votre message a été posté avec succès !" (no anchor), reply "Votre réponse a été postée avec succès !" with anchor `#bas` (the samples used `#t1003`), edit "Votre message a été édité avec succès !" with `#t<numreponse>`,
  delete "Message effacé avec succès !" with the bare `numreponse` as anchor (W16a, W16b, W19: a second delete and a whole-thread delete answer the same text). Rejected (legacy and live agree): flood (W11x, W13cx, W14x, W20a, W20b), empty body (W17a), logged out (W17c).
  **W17b (invalid `hash_check`, 99-byte plain text, no `.hop`)**: legacy `success` with no message, live `submissionRejected`: quirk 8 happens on a real answer, and the legacy app would report a refused post as posted.
- RC4.5 (quirk 6) The live refresh URL keeps `&amp;` on real answers (W10, W16a); the legacy side only reads the fragment. All real answers are UTF-8 (`charset` default), so quirk 13 (Latin-1) was not exercised.
- RC4.6 **MPStorage find.** user1's inbox has the storage thread (subject `MP_NAME`, `MPStorage.m:23`) on page 1 of R13u1 and R13u1b: `find` returns `true` after one GET of page 1 and caches `dicMPStorage_postid = {"user1": "3157083"}`. user2's list R13a has none: `false`, one GET (the pager has one page).
  The legacy pager reading (`lastObject` of the pager children as page count) is the same windowed pager as LOT-002 RC2.1; on a 7-page list it would only be right because the whole range is shown.

## Fixtures
`tooling/legacy-oracle/samples/`, all synthetic (fake pseudos `fakeuser1..3`, fake hash). Expected JSON is generated, not committed. Real cases: see "Real captures" above (`Fixtures/LOT-004/`).

| Files | Covers |
|---|---|
| `form-reply`, `form-reply-anon`, `form-quote`, `form-edit`, `form-delete`, `form-newtopic`, `form-newtopic-pretty`, `form-mp`, `form-quirks`, `form-alert`, `form-alert-already` | each write flow; entities, checkbox/radio/select, prefill, relative action; the quirks above |
| `response-reply-{ok,ok-noanchor,flood,empty,loggedout,nohop,hop-and-refresh,500,latin1}`, `response-delete-ok`, `response-alert-{ok,already}`, `response-mp-{success,success-latin1,failure}` | every classifier branch |
| `storage-mp-page{,-numeric,-empty-doc,-malformed,-destine}`, `storage-mp-list` | MPStorage page parse |
| `storage-op-*` (9 files) | MPStorage operations and requests |
| `storage-keychain{,-single}`, `storage-blacklist`, `storage-smileys`, `storage-offline` | on-device formats |

## Intentional differences from legacy
None: this lot records legacy behaviour. The differences above are the input of the porting lots, which decide the side to follow
(quirks 1, 2, 3, 6, 7, 12 look like live bugs; 8 and 13 legacy bugs).

## Learnings
- A view controller not compiled into the test host can still be an oracle: transliterate its steps and run them on the real libraries.
- Compare POST bodies sorted: both stacks emit fields in random order.
- Normalise "now" timestamps and fix cookie `Created` and expiry, or archive bytes change every run.
- Run the whole sample set at least twice and diff: an order-dependent flake only shows in full runs (the avatar stub race, LOT-003 Q33).
- Reset every shared legacy singleton the cases touch (`MPStorage.shared` flags included): a state leak only shows after a failing case.

## Open questions
- The real Keychain write returns `stored=false` in the simulator test host, so only the archive bytes and the `getComtpes` read (through a
  `dataForKey:` swizzle) are verified. `tryKeychain: true` (`storage-keychain`) does call the real `A0SimpleKeychain setData:forKey:` on
  the app's item (`HFR_COMPTES_KEY`, service `hfrplus.red.super`): where Keychain access works, it overwrites that item with the synthetic
  accounts, then restores the previous value or deletes it. Run it only on a simulator without a real account.
- Selection quote and the hash fallback (`QuoteMessageViewController.m`) are not exercised.
- Bare `checked` (quirk 4): the browser sends the value, which matches legacy `"1"`; unverified on the real server.
- Write **responses** are now covered by real captures (RC4.4), but only the MP flows of two throwaway accounts; a public-topic reply, a moderation alert answer and a Latin-1 answer have no real capture.
