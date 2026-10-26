# LOT-005 — Oracle exporter: the small parsers

- **Module:** tooling (legacy app)
- **Difficulty / model:** medium (Sonnet → Fable)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

Harness, patch and run instructions: [`tooling/legacy-oracle/`](../../tooling/legacy-oracle/README.md) (shared with [LOT-002](LOT-002-list-oracle.md),
[LOT-003](LOT-003-topic-oracle.md), [LOT-004](LOT-004-forms-storage-oracle.md)). ADR 0004 requires each ported parser to reproduce the legacy
output on every fixture; LOT-002..004 did not cover the parsers of LOT-025, LOT-026 and LOT-027. This lot adds six kinds. Oracles are in
`Packages/HFRKit/Tests/HFRParsingTests/Fixtures/LOT-005/` (`oracle-map.json`, `<case>.oracle.json`, `errors.json`); pages stay in `../captures/`.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow>, commit `2440d79`. Paths from the repository root.

| Kind | Cases | Legacy code | How it runs |
|---|---|---|---|
| `search-redirect` | R50a, R50b, R50c | `Classes/ObjCForumSearchWorker.m:46-55` (decode + "no result page" error), `305-345` (`forumSearchRedirectURLFromHTML:`, absolute and relative URL) | real worker methods through the runtime; the error object is built inline in the callback, so its literals are rebuilt in the exporter |
| `profile-edit` | R55-p1, R55-p3, R55-p5, R55-p5u1 | `HFRswift/Swift/LoginService.swift:87-113` (`hash_check` regex, avatar regex, avatar fetch) | the real `LoginService.login` over a stub `URLProtocol`; the page under test is served as the page-5 answer |
| `smiley-search` | R53a, R53b, R53c | `HFRswift/Swift/SmileySearchService.swift:17-37` (`search`) and `44-75` (`parseSmileys`) (live) and `Classes/SmileyViewController.m:893-924` (legacy ObjC callback) | real `HFRSmileySearchService.search` over a stub; the ObjC step is transliterated (UI-bound) in `OracleLegacySmall.m` |
| `smiley-keywords` | R54 | `Classes/SmileyAlertView.m:162-197` (`requestSmileyComplete:`); Swift copies `HFRswift/Swift/MessagesView.swift:3317-3392` and `AnswerView.swift:762-836` | both are UI-bound (view controller / private SwiftUI method): transliterated, see below |
| `poll` | R32a, R32b, R33a, R33b | `HFRswift/Swift/PollData.swift:104-330` (`PollHTMLParser.parse`) fed by `Classes/ObjCTopicPageWorker.m:162` (`swiftPollHTML`) | real topic pipeline of LOT-003, reduced to the poll section; `PollHTMLParser` is called as is |
| `profile` | R56a, R56b | `HFRswift/Swift/UserProfileView.swift:113-430` (`UserProfileService`, `UserProfileHTMLParser`) | real service over a stub; the parser is pure and called as is |

Correction to the brief: the wiki-keywords code is not at `SmileyViewController.m:902-925` (that range is the smiley **search** callback). The keywords
parsing is `SmileyAlertView.m:162-197` and its two Swift copies; the search callback is covered by `smiley-search` (`legacy` part).

**UI-bound code.** `SmileyAlertView`, `SmileyViewController` and the two SwiftUI views are not callable from the `HFRswift` test host. Only their parsing
steps are transliterated line by line (legacy line numbers in comments) into `HFRswiftTests/OracleLegacySmall.m` (ObjC, on the real `HTMLParser` /
`NSRegularExpression`) and `OracleExportSmall.swift` (Swift copies). They live in the local patch only; hfrnow is untouched upstream. The ObjC step reads
the page as UTF-8 (the capture's `Content-Type`); `ASIHTTPRequest.responseString` would use the response charset, the same here.

## Inputs

`oracle-map.json` entry: `{"kind": ..., "path": "../captures/<page>.html", ...options}` (no `now`: nothing here depends on the date).

| Kind | Options |
|---|---|
| `search-redirect` | none (the page is the POST answer) |
| `profile-edit` | `session.pseudo` (fake login pseudo; fake password `FAKE_PASSWORD`) |
| `smiley-search` | `query`: what the user typed. The live service builds the URL from it. R53 captures used `+word` URLs; queries are `zzqxw`, `chat`, `chat noir` |
| `smiley-keywords` | `code`: the smiley code the page was fetched for (`[:user3]`) |
| `poll` | `currentURL`, `ownPseudo` as the `topic` kind. R32a, R33a anonymous; R32b user2; R33b user1 |
| `profile` | `url`: the profile URL (relative links resolve against `k.forumURL()`) |

## Output (schema 1)

Common envelope as in LOT-002 (`case`, `kind`, `schema`, `legacyCommit`, `input`, `exception`, `result`, `sideEffects`). `input.context` holds the effective inputs.

- **`search-redirect`** `result`: `{redirectURL, hasRedirect, absoluteURL, relativeURL, error}`; `error` is `null` or `{domain: "TopicsSearchViewController.search", code: -2, message: "Aucune page de résultats n'a été trouvée."}`.
- **`profile-edit`** `result`: `{outcome: "success"|"error", error?, message?, displayPseudo, pseudoKey (fake), hash, hashLength, avatarDataBytes, avatarDataIsStub, cookies[{name,domain,path}], requests[{method,url,bodyFields?}]}`.
  `hash` is the fixed placeholder `HASH_PLACEHOLDER` (never the page's value); `hashLength` is the length of the extracted value. The avatar URL is not returned by the service: read it from `requests[2].url` (the avatar fetch). POST bodies are logged as field names only.
- **`smiley-search`** `result`: `{live: {smileys[{code, imageSource: {remote: url}}], error?, requests[{method,url}]}, legacy: {items[{code, source}], noResult, exception?}}`.
- **`smiley-keywords`** `result`: `{legacyObjC: {inputFound, value, arrCodeList, enabled, commaRemovalIsNoOp, commasWouldBeRemoved, exception?}, swiftApp: {outcome, keywords, rawValue | code, message}}`.
- **`poll`** `result`: `{poll: {hasPoll, isNewVote, html, parsed: {question, footer, maxChoices, isVotable, options[], results[], hiddenFields}|null}, currentURL}`. `html` is the extracted `swiftPollHTML`, a libxml2 re-serialization of the poll block (Q9), not the raw page text.
- **`profile`** `result`: `{profile: {pseudo, status, avatarURL, summary[], sections[{id,title,fields[]}], personalSmilies[], actions[{id,title,subtitle,url,kind}]}}` or `{error, errorMessage}`.

## Cases and findings

| Case | Result |
|---|---|
| R50a | redirect found; URL already relative, so `relativeURL` equals `redirectURL`. Note: `forumSearchRelativeURLStringFromString:` (`ObjCForumSearchWorker.m:336-345`) returns `NSURL.path` (percent-decoded) + raw query + fragment, so equality holds only because this URL has no percent-encoding. For LOT-025: the legacy follows the refresh URL with a POST of the same body (`followForumSearchRedirectURL:` `:211-224`, HFR-PROTOCOL S2) |
| R50b, R50c | the real search **results** pages (no meta refresh, as served without the search cookie): `hasRedirect` false, so the POST callback gives the "no result page" error (code -2). Both are the same outcome; the results-page parse is `search` in LOT-002 |
| R53a | 0 results, page is the text "Désolé, aucune réponse n'a été trouvée !": live `[]`, legacy `noResult` true |
| R53b, R53c | 657 and 1010 smileys; live and legacy lists are identical (same order, same codes, all `https`) |
| R54 | keywords `musique guitare guitariste`, same in ObjC and Swift copies |
| R55-p1/p3/p5/p5u1 | all succeed (the page is served as page 5 whatever it is); `hashLength` 8 (the capture holds `REDACTED`) |
| R32a, R32b | vote form: 4+ options, `maxChoices` 1, `hiddenFields` (R32a `hash_check` `""`, R32b `"REDACTED"`) |
| R33a | closed poll (anonymous): results only, 3 results, `isVotable` false |
| R33b | already voted (user1): results only, 3 results; the forum's "Multipseudo detecté" notice is not part of the parsed model |
| R56a | operator profile: 2 sections (7 + 6 fields), no avatar, no personal smiley, actions: 2 transactions, private message, all messages |
| R56b | other member: avatar, 4 personal smileys, extra `configuration` action |

### Legacy quirks to know before porting (Q = quirk)

- **Q1 avatar regex grabs the first image (LoginService.swift:96-99).** `profilCase3[\s\S]*?<img[^>]*src="…"` matches the first `<img` after any `profilCase3` cell, not the avatar. On R55-p1 and R55-p3 it returns an icon (`…/themes_static/images_forum/1/aide.gif`), on R55-p5 (an account without avatar) a tracking pixel (`tracking.groupe-ldlc.com/matomo.php?…`), and only on R55-p5u1 (account with an avatar) the real one (`…/mesdiscussions-900001.jpg`). The oracle records this; the port must fix it on purpose and document the difference (a bug fixed on purpose is allowed by §5).
- **Q2 `hash_check` is the first match on the page** (`name="hash_check"[^>]*value="…"`), any page; page 1 and 3 also yield one. An empty value matches only if non-empty (`+` quantifier): a page with `value=""` gives `missingHash`.
- **Q3 live smiley search URL differs from the browser's.** The service sends `findsmilies=chat%20noir` (space percent-encoded, no leading `+`), the captured browser request was `findsmilies=+chat+noir`. The oracle records the request URL. Under 3 characters it returns `[]` without a request (not exercised: no capture).
- **Q4 live smiley search decodes as ISO-8859-1 always** (`String(data:encoding:.isoLatin1)` never fails), whereas the pages are UTF-8: non-ASCII `alt` text would be mojibake. No R53 page has a non-ASCII code; the port should decode UTF-8 (documented, not exercised).
- **Q5 the legacy ObjC search callback raises on an `<img>` without `src` or `alt`** (`dictionaryWithObjects:forKeys:` with a nil), and keeps entries the Swift service drops (empty `alt`, non-URL `src`). Equal on R53; recorded for synthetic tests.
- **Q6 the keywords steps differ in decoding and separators.** The ObjC step reads `value` through libxml2 (`HTMLNode.m:79-83`, `getAttributeNamed:` `:61-77` returns the attribute's `children->content`), which `htmlParseDoc` has already entity-decoded: ObjC decodes **all** entities. The Swift copies read the raw attribute with a regex and decode only six fixed ones (`&amp; &quot; &apos; &#39; &#x2F; &#47;`), then turn commas into spaces. The ObjC step ignores its own comma removal (`SmileyAlertView.m:185` discards the result; `commaRemovalIsNoOp`), so `a, b` gives `["a,", "b"]` in ObjC and `["a", "b"]` in Swift. R54 has no comma and no entity.
- **Q7 poll text keeps entities.** `PollHTMLParser` cleans tags but not all entities: R32a/R32b option 3 is `E85 entre 25 &amp; 40 % + SP`. The port must match or document a fix.
- **Q9 poll `html` is a libxml2 re-serialization, not the page text** (`swiftPollHTML`, `ObjCTopicPageWorker.m:162`): `&nbsp;` becomes a raw U+00A0, `/>` becomes `>`, newlines are inserted and `&amp;` is re-escaped. Consequence: `cleanedPollText` (`PollData.swift:375-383`) replaces the string `&nbsp;`, which no longer exists, so `parsed.results[].label` keeps the NBSP and the "N." prefix (`"1.  Hugo Lloris"`); `percentage` serializes as e.g. `65.200000000000003` (compare with a tolerance). LOT-026 must reproduce or document the NBSP/prefix.
- **Q8 profile parser**: the "Non renseigné" placeholder replaces empty values (`isPlaceholder` true); `Pseudo`/`Statut` are found by substring on the title.

## Determinism and privacy

- Two full runs (separate build and staging folders) are byte-identical (`diff -r`), checked by the author; see the PR description for the hashes.
- The oracles derive from anonymized captures. Walking every string of the 17 oracles: 0 hits for the real names in the local anonymizer configuration and the account credentials, 0 e-mail, 0 IP address, every `hash_check` value is `""` or `REDACTED` (from the pages) and the login hash is `HASH_PLACEHOLDER`. The only 32+ hex strings are the 17 input SHA-256 values. Login uses fake credentials; the cookie value is `FAKE_PSEUDO_KEY`.

## Open questions

- Which of the two keywords implementations does the Swift app ship? Both Swift copies are identical (`MessagesView` and `AnswerView`); the ObjC one is reachable from `SmileyAlertView` only. LOT-053 should pick the Swift one and fix Q6 consciously.
- `PollVoteSubmitter.parseVoteResponse` (`PollData.swift:79-98`) is private and has no capture of a vote response; not covered here (needs a write capture, LOT-054).
