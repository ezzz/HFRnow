# LOT-041 — HFRNetwork endpoint catalogue

- **Module:** HFRNetwork
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** none

## Legacy sources
Audit [A](../audit/A-network-sessions.md) §3.1 and lot NET-02; protocol [R1–R9, S1–S3](../HFR-PROTOCOL.md#1-read-endpoints) and §7 E1; legacy repo <https://github.com/francoisgn/hfrnow>.

| Endpoint | Legacy |
|---|---|
| R1 home, R8 background check | `ObjCForumsLoaderWorker.m:20`, `MPBackgroundService.swift:80-135` |
| R2 topic list | `ObjCForumTopicsLoaderWorker.m:36-89, 128-141` (path built by `ForumCatalogue.topicListPath`, LOT-014) |
| R3 favourites | `ObjCFavoritesLoaderWorker.m:46-48` |
| R4 private messages | `ObjCMPTopicsLoaderWorker.m:9` |
| R5 topic page | `ObjCTopicPageWorker.m:14-43, 86-94`; canonical shape observed live (HFR-PROTOCOL §6) |
| R6 profile editor | `IdentificationViewController.m:246`, `MultisManager.m:281`, `LoginService.swift:87-113` |
| R7 smiley search | `SmileySearchService.swift:12-42`, `AnswerView.swift:1308-1326` |
| R9 public profile | `UserProfileView.swift:113-430` |
| S1 global search | `ObjCForumSearchWorker.m:141-181`, `ForumSearchService.swift:10-127` |
| S3 intra-topic search | `ObjCTopicSearchWorker.m:24-52`, `TopicSearchService.swift:11-62` |
| E1 REST | redface2, HFR-PROTOCOL §7 (unverified) |

## Behaviour
All in `Packages/HFRKit/Sources/HFRNetwork/Endpoints/`. `HFREndpoint` is a namespace of static, pure builders returning `HTTPRequest` (LOT-040); no networking, cookies or state.

- `home()`, `privateMessageCheck()` (5 s), `topicList(category:filter:page:)`, `favorites(filter:)`, `privateMessages(page:)`, `topicPage(topic:page:anchor:)` / `topicPage(post:page:)`, `editProfile(page:)`, `publicProfile(memberID:)`, `smileySearch(_:requireAll:)`, `rest(uri:page:resultsPerPage:)`, `globalSearch(_:hashCheck:)`, `topicSearch(_:hashCheck:)`, `absoluteURL(href:)`.
- Query order is fixed and tested for every endpoint. Topic list: `config, cat, page, subcat (empty), owntopic`.
- **Topic page**: always `forum2.php?config=hfr.inc&cat=..&post=..&page=..`, which HFR redirects (301) to the canonical URL; the response's final URL (read by LOT-045) tells the page. The canonical path is never rebuilt: it can carry a sub-category segment (observed live 2026-10-25: `/hfr/Programmation/Divers-6/hfr-android-sujet_148745_1.htm`) that cannot be derived from the catalogue. `anchor` adds `#t<numreponse>`. Private topics use the same form with `cat=prive`.
- **Global search** (`GlobalSearchQuery`): POST `/search.php?config=hardwarefr.inc`, fields `hash_check, cat, search (lowercased), resSearch=200, orderSearch=0, titre, searchtype, pseud="", daterange`, then `jour, mois, annee` (zero padded) only for `.since`. Defaults `cat=13, titre=3, searchtype=1, daterange=2`. Timeout 15 s. The start date is an input, so the builder stays pure.
- **Intra-topic search** (`TopicSearchQuery`): POST `/transsearch.php`, fields `hash_check, p?, post, cat, word, spseudo, filter=1?, firstnum?, currentnum?` (the last two together, only for a continued search), `redirectPolicy = .doNotFollow`, timeout 60 s.
- **Smiley search**: words split on whitespace, leading `+` dropped, joined by a space, `+` prefixed on each word when `requireAll`; ≥ 3 characters after trimming. Value percent-encoded (`%20`, `%2B`).
- **REST**: `uri` keeps `/` literal, other reserved characters are percent-encoded.
- `absoluteURL(href:)` resolves relative, protocol-relative and absolute links against the forum host; other hosts and non-HTTP(S) schemes return nil.

## Edge cases
- Page below 1, private category in a forum list, `forum1f.php` with a filter other than tracked/favourites, smiley text under 3 characters, blank search text, intra-topic search without criterion or `hash_check`, invalid start date: `NetworkError.invalidRequest`, nothing built.

## Out of scope
Banned-word policy for global search (Q-7, caller), `hash_check` ownership (LOT-042 / HFRClient), meta-refresh and next-page URLs of S2 (LOT-025 / LOT-046), page number parsing from a final URL, favourite add/remove (server-given link, §3.2), write-flow URLs read from forms.

## Fixtures
None; pure functions, table-driven tests with exact URLs and bodies in `Tests/HFRNetworkTests/Endpoints/`.

## Intentional differences from legacy
- Smiley and REST query values are encoded with the strict unreserved set (legacy used `urlQueryAllowed` minus `+&=`); servers decode both identically.
- Global search bodies are UTF-8 percent-encoded and sent as `application/x-www-form-urlencoded; charset=utf-8` (legacy: no charset, raw accents), see LOT-040. Whether the server cares is unverified.
- No banned-word substitution in the builder.
