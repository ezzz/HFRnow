# HFR protocol reference

Everything we know about how forum.hardware.fr works: URLs, parameters, forms, cookies, tokens, HTML signals.
**Every entry cites its source**: a legacy `file:line` (repo <https://github.com/francoisgn/hfrnow> @ `2440d79`) and/or an audit section.
Status per fact: **code** = read from legacy code only · **live** = observed by us on the live forum · **rf2** = reported by the redface2 Android client's documentation (rewritten in our words, not copied; GPL project) · **verified** = confirmed by a committed fixture. Until Phase 2 delivers fixtures, nothing is *verified*; §7 lists the open points to settle with fixtures.

This document and the test fixtures are licensed under [CC BY 4.0](../LICENSE-docs.md) ([ADR 0009](adr/0009-open-protocol-docs-license.md)), unlike the code.

Host: `https://forum.hardware.fr` (`Classes/k.m:37-40`). Forum config `config=hfr.inc` on all pages except global search (`config=hardwarefr.inc`).

## 1. Read endpoints

| Id | Purpose | Method | URL | Notes | Source |
|---|---|---|---|---|---|
| R1 | Home: forum list, `hash_check`, MP count | GET | `/` | | `ObjCForumsLoaderWorker.m:20`, `ObjCForumsParser.m:41-42` · audit A §3.1 E1 |
| R2 | Topic list of a forum | GET | `/forum1.php?config=hfr.inc&cat={cat}&page={n}&subcat=&owntopic={0..3}` | `owntopic`: 0 all, 1 tracked (flag1), 2 read (flag0), 3 favourites | `ObjCForumTopicsLoaderWorker.m:36-89, 128-141` · A §3.1 E2 |
| R3 | Favourites across forums | GET | `/forum1f.php?owntopic={1\|3}` | `3` when setting `vos_sujets == 1` | `ObjCFavoritesLoaderWorker.m:46-48` · A E3 |
| R4 | Private messages list | GET | `/forum1.php?config=hfr.inc&cat=prive&page=1` | legacy list shows page 1 only; multi-page scan (`page=N` + long query) exists only in MPStorage | `ObjCMPTopicsLoaderWorker.m:9`, `MPStorage.m:692-736` · A E4, E §2.6 |
| R5 | Topic page | GET | `/forum2.php?config=hfr.inc&cat=..&post=..&page=..`, which redirects (301) to the canonical `/hfr/<cat>[/<sub-category>]/<slug>-sujet_<post>_<page>.htm`; the path may carry a sub-category segment, e.g. `/hfr/Programmation/Divers-6/hfr-android-sujet_148745_1.htm` (**live**, 2026-10-25, §6) | Follow redirects; the **final URL** gives the page: read it from the `sujet_<post>_<page>` segment. The legacy regex `_(\d+)\.htm` matches the same form; the older `/hfr/<cat>/<sub>/<slug>_<id>_<page>.htm` shape cited by legacy code is unverified | `ObjCTopicPageWorker.m:14-43, 86-94` · A E5, §3.4 |
| R6 | Profile page | GET | `/user/editprofil.php?config=hfr.inc&page={5\|1}` | page 5: `hash_check` + avatar after login; page 1: cookie refresh | `LoginService.swift:87-113`, `MultisManager.m:281` · A E10 |
| R7 | Smiley search | GET | `/message-smi-mp-aj.php?config=hfr.inc&findsmilies=+w1+w2` | ≥ 3 chars | `SmileySearchService.swift:12-42` · A E11 |
| R8 | MP unread count | GET | `/` | first integer in `.cCatTopic.red` | `MPBackgroundService.swift:80-135` · A E12 |
| R9 | Public profile page | GET | `/hfr/profil-{id}.htm` | `table.main` rows `profilCase2/3`, avatar, personal smileys | `UserProfileView.swift:113-430` · review F4 |

### 1.1 Forum paths and category ids

The home page does not link `cat` ids; this table maps each forum's topic-list path to its `cat` (R2). The last row is the absolute alias of `ia`. Source for all rows: legacy `Forum.m:34-60` (`getHFRID`), mirrored in `ForumCatalogue.entries`. Paths are matched exactly; a path not in this table has no known `cat`.

| Path | `cat` |
|---|---|
| `/hfr/Hardware/liste_sujet-1.htm` | 1 |
| `/hfr/HardwarePeripheriques/liste_sujet-1.htm` | 16 |
| `/hfr/OrdinateursPortables/liste_sujet-1.htm` | 15 |
| `/hfr/gsmgpspda/liste_sujet-1.htm` | 23 |
| `/hfr/OverclockingCoolingModding/liste_sujet-1.htm` | 2 |
| `/hfr/electroniquedomotiquediy/liste_sujet-1.htm` | 30 |
| `/hfr/apple/liste_sujet-1.htm` | 25 |
| `/hfr/VideoSon/liste_sujet-1.htm` | 3 |
| `/hfr/Photonumerique/liste_sujet-1.htm` | 14 |
| `/hfr/JeuxVideo/liste_sujet-1.htm` | 5 |
| `/hfr/WindowsSoftware/liste_sujet-1.htm` | 4 |
| `/hfr/reseauxpersosoho/liste_sujet-1.htm` | 22 |
| `/hfr/systemereseauxpro/liste_sujet-1.htm` | 21 |
| `/hfr/OSAlternatifs/liste_sujet-1.htm` | 11 |
| `/hfr/Programmation/liste_sujet-1.htm` | 10 |
| `/hfr/Graphisme/liste_sujet-1.htm` | 12 |
| `/hfr/AchatsVentes/liste_sujet-1.htm` | 6 |
| `/hfr/EmploiEtudes/liste_sujet-1.htm` | 8 |
| `/hfr/Setietprojetsdistribues/liste_sujet-1.htm` | 9 |
| `/hfr/Discussions/liste_sujet-1.htm` | 13 |
| `/hfr/Blabla-Divers-back-to-life/liste_sujet-1.htm` | 24 |
| `/hfr/ia/liste_sujet-1.htm` | 32 |
| `https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm` | 32 |

## 2. Search

| Id | Purpose | Method | URL | Body / behaviour | Source |
|---|---|---|---|---|---|
| S1 | Global search | POST | `/search.php?config=hardwarefr.inc` | Fields **in this order**: `hash_check, cat, search, resSearch=200, orderSearch=0, titre, searchtype, pseud="", daterange, [jour, mois, annee]`; defaults `cat=13, titre=3, searchtype=1, daterange=2`; query lowercased; legacy replaces the query when it contains a banned word (`jailbreak`, `cydia`, `pengu`, `apple jb`); SwiftHFR refuses the search with a warning instead (Q-7); body declared without charset. Response carries a `<meta http-equiv=refresh … url=…>` | `ObjCForumSearchWorker.m:31, 141, 149-181` · A E7 |
| S2 | Global search results | POST (same body), then GET for next pages | meta-refresh URL from S1 | `&amp;` → `&`; missing meta → "no result page" | `ObjCForumSearchWorker.m:46-95, 211-240` · A E8 |
| S3 | Intra-topic search | POST | `/transsearch.php` | `hash_check, p, post, cat, word, spseudo, filter=1, [firstnum, currentnum]`. **Do not follow redirects**: the `Location` header is the result; none → no result | `ObjCTopicSearchWorker.m:24-52` · A E6 |

## 3. Write flows

### 3.1 Common pattern (reply, edit, delete, new topic, MP)
1. GET the form page (answer URL, edit URL, new-topic URL, MP URL). It contains `<form name="hop">`.
2. Copy every `<input>` (legacy: checkbox → `"1"`/`"0"`; **rf2: browsers send nothing for an unchecked checkbox or radio** ([research](research/redface2-comparison.md) §4.2 X3, open point §4.4 item 3); radio → value only if checked, others → `value`) and every `<select>` (selected or first option). Values must be HTML-entity-decoded (legacy Swift does not: bug).
3. Override `content_form` (message, `\n` → `\r\n`), `pseudo`, `hash_check`, `config=hfr.inc`; and `sujet`, `subcat`, `dest` when the form exposes them.
4. POST `application/x-www-form-urlencoded; charset=utf-8` to the form `action`, resolved against the form URL. Default `/bddpost.php` only when the form has no usable action. The edit form's action is unverified (`/bdd.php` is established only for MPStorage updates, §3.3) — **always read the action, never hard-code**.
5. Classify the response (HTTP 200 even on rejection):
   - success: a `<meta http-equiv="refresh">`, or a `.hop` block without `<a>`/`<input>`; anchor = fragment of the refresh URL;
   - rejected (incl. flood): `.hop` block containing a link or input; message = its text;
   - logged out: `identification.php` / `name="login"` / pseudo + password fields without a `hop` form.

Sources: `ReplyService.swift:145-183, 294-365, 579-719` · `AddMessageViewController.m:513-622` · `QuoteMessageViewController.m:209-285` · audit D §2.

| Flow | Form page | Specifics | Source |
|---|---|---|---|
| Reply | `href` of the first `<a>` in `#repondre_form` on the topic page | | `ObjCTopicPageWorker.m:156-157` · D §2.1 |
| Edit | decoded `editURL` of an own message | same form, `content_form` replaced | D §2.3 |
| Delete | decoded `editURL` | edit with `delete=1` and the unchanged text. Legacy UI never offers deleting the first post; **rf2: the topic owner can, and it deletes the whole topic** (§7) | `ReplyService.swift:954-1038` · D §2.4 |
| New topic | `href` of `#md_btn_new_topic` on the topic list | `sujet` (text), `subcat` (select) | `ObjCTopicListParser.m:134-135` · D §2.5 |
| New MP | author block link `/message.php?config=hfr.inc&cat=prive&…&dest=` | `dest`, `sujet` | `ParseMessagesOperation.m:389-390` · D §2.5 |
| Moderator alert | first `href` containing `/user/modo.php` in the message | form `action~modo.php`, field `raison`; `.hop` with a link = **already alerted** (inverse of reply) | `ReplyService.swift:1400-1531` · D §2.6 |
| Poll vote | poll block in the topic page | POST `/user/vote.php?config=hfr.inc`, hidden inputs + chosen options; radio value semantics unverified | `PollData.swift:44-100` · D §2.9 |

### 3.2 Topic flags
- Add to favourites: **state-changing GET** of the message's `addflag` link; toast text from `<div class="hop">`. `ParseMessagesOperation.m:383-384` · D §2.8
- Remove a favourite: POST `/modo/manageaction.php?config=hfr.inc&cat=0&type_page=forum1f&moderation=0` with `hash_check, topic1=-1, topic_statusno1=-1, action_reaction=message_forum_delflags, type_page=forum1f, topic0, valuecat0, valueforum0=hardwarefr`. `Favorites.swift:36-103` · D §2.8

### 3.3 MPStorage (bookmarks, synced blacklist, MP flags)
A private message used as a JSON document store, shared with other HFR+ clients.
- Title (`sujet`) `a2bcc09b796b8c6fab77058ff8446c34`, recipient `MultiMP`; body `{"data":[{"version":"0.1","blacklist":{…},"mpFlags":{…},"bookmarks":{…}}],"sourceName":"iOS","lastUpdate":<ms>}`.
- Find: scan the MP list for that title (or `[non lu] ` + title); topic id = `post=` of its link.
- Read: GET the topic; JSON = text of the first message's `<p>` with U+00A0 removed; `numreponse` from the `para…` div id. A page containing `destiné` means not found.
- Create: POST `bddpost.php?config=hfr.inc` with the full field list; update: POST `bdd.php?config=hfr.inc` with `numreponse` and `post`. Success = body contains `succès`.
- Read-modify-write with no locking (lost updates possible).

Source: `Classes/MPStorage.m:21-22, 152-156, 249-355, 536-666, 737-885` · D §2.10, E §2.6.

## 4. Quotes

- **Single quote**: GET the decoded `quoteURL`; the server returns the form with `content_form` prefilled `[quotemsg=a,b,c]…[/quotemsg]` (argument meaning unsettled: rf2 reports cited `numreponse`, an opaque index, cited author id — [research](research/redface2-comparison.md) §4.2 X2, open point §4.4 item 2; always reuse the server's prefill, never build it). The reply is then posted to the topic's answer URL. `ReplyService.swift:767-841` · D §2.2
- **Multi-quote** (client-side cookie, as the site's JS does): `quoteJS` = `quoter('hardwarefr', cat, post, numreponse)`; cookie `quotes<arg0>-<arg1>-<arg2>` (e.g. `quoteshardwarefr-13-42`), value = concatenated `|<numreponse>`, domain `.hardware.fr`, path `/`, expires +1 h; deleted when empty. The next quote/answer GET must carry it. Match ids **exactly** (legacy substring match is a bug, fixed in [LOT-042](lots/LOT-042-sessions.md)). `MessagesView.swift:1852-1945` · D §2.2b, C §5
- **Obfuscated URLs**: quote and edit URLs are stored in the CSS `class` of the element around `<img alt="answer">` (prefix of 20 characters); list pager links use `md_cryptlink` (prefix of 12). Decode: drop the prefix, then map each pair of characters through the alphabet `0A12B34C56D78E9F` (index = nibble) into one byte. Decode only if `length > 20` and the string contains neither `/` nor `http`. `RangeOfCharacters.m:92-114`, `ObjCMessageActionsBuilder.m:80-89` · C §3.4, D §2.2

## 5. Session, cookies and tokens

- **Login**: POST `/login_validation.php?config=hfr.inc` with `pseudo, password, action=send, login=Se connecter`; success ⇔ body contains `login_redirection.php`; then GET R6 page 5 for `hash_check` and avatar. Legacy clears all cookies *before* validating (bug). `LoginService.swift:48-129` · A §4.2
- **Identity cookie**: `md_user`; value `deleted` = logged out. A §4.1
- **`hash_check`**: anti-CSRF token required by every POST; hidden input on R1, R3 and R6 pages and in the topic page `hop` and `transsearch` forms (`name="hash_check"`). Per account; refreshed from parse results by `HFRClient`. `ObjCForumsParser.m:41`, `ObjCFavoritesLoaderWorker.m:105`, `LoginService.swift:100`, `ObjCTopicPageWorker.m:150-179` · A §3.1, C §3.3
- **Session isolation** (decided, [LOT-042](lots/LOT-042-sessions.md)): one `HFRSession` per account with its own jar and `hash_check`; no global jar, no global token. An account session contacts only `*.hardware.fr` and does not follow a redirect leaving it or downgrading to HTTP. Prefetch and images use a cookie-less transport (§7 E25, E26). Replaces the legacy shared jar wiped and refilled on every account switch and before list loads, with `quotes*` cookies saved and restored around it, and the global `hash_check` fallback (**code**). `AccountSessionService.swift:77-110`, `MultisManager.m:155-165`, `Common.swift:1402-1406` · A §4.1, §4.3-4.4
- **Not logged in** on favourites (R3): `<body>` without `id`; message = first `<p>` or `.hop` text. `ObjCFavoritesLoaderWorker.m:87-95`

## 6. Transport behaviour

- **Encoding — UTF-8** (**live**, 2026-10-25: `Content-Type: text/html; charset=utf-8` and `<meta charset=UTF-8>` on topic 1711 pages 450–510, [user feedback](research/user-feedback-p450-510.md) §4; rf2 captures agree, [research](research/redface2-comparison.md) §4.3 E27). Legacy Latin-1 fallbacks are unnecessary for HTML pages; other endpoints still to capture. A §3.2
- **Topic URL redirect** (**live**, 2026-10-25, request to topic 1711 page 450; rf2 agrees, [research](research/redface2-comparison.md) §4.3 E13): `forum2.php?…&page=N` answers **301** with a relative `Location: /hfr/<cat>[/<sub-category>]/<slug>-sujet_<post>_<N>.htm`; read the page from the `sujet_<post>_<N>` segment.
- **Emoji** (**rf2**, [research](research/redface2-comparison.md) §4.2 X9; users report the same, [user feedback](research/user-feedback-p450-510.md) p. 478; decides Q-3): HFR cuts a posted message at the first character outside the Basic Multilingual Plane (most emoji) and still answers success; everything after it is lost silently. Never send such characters.
- **Form encoding** (decided, [LOT-040](lots/LOT-040-transport.md)): bodies are `application/x-www-form-urlencoded; charset=utf-8`, every non-ASCII byte percent-encoded (legacy global search sent accents raw, `ObjCForumSearchWorker.m:194-199`). Line breaks are sent as typed unless a poster chooses CRLF (open, §7 X11).
- **HTTP status**: legacy ignores it; application errors are detected from content (`.hop`, `login_redirection.php`, missing `id`, `Location`). A §3.4 The new transport throws on 4xx/5xx ([LOT-040](lots/LOT-040-transport.md)).
- **URL building** ([LOT-041](lots/LOT-041-endpoints.md)): `HFREndpoint` builds every §1–2 request with the query order shown in the tables. Topic pages are always requested through `forum2.php` (the canonical path is never rebuilt, its sub-category segment is not derivable); query values use strict percent-encoding (`%20` for space, `%2B` for `+`). Exception: the REST `uri` value keeps `/` literal (`uri=forums/hardwarefr/categories/`), never `%2F`.
- **Headers**: no custom User-Agent, Referer or Origin; gzip accepted. Whether HFR checks any is unverified. A §3.3
- **Timeouts** (legacy): lists 30 s, topic search 60 s, global search 15 s, background MP check 5 s. No retry, no backoff, no rate limiting. A §3.5

## 7. Reported by redface2, to verify with our fixtures

Facts from the redface2 project documentation, rewritten here; each becomes *verified* only through a LOT-001 fixture. Source: [docs/research/redface2-comparison.md](research/redface2-comparison.md) §4 (ids X/E below).

| Topic | Reported fact | Id |
|---|---|---|
| Write constant | Every `bddpost.php` / `bdd.php` POST carries `verifrequet=1100`; the poll vote does not | X4 |
| Write markers | Distinct success sentences for reply, edit, create and delete; specific texts for empty body, invalid token, flood | E15 |
| First post | Owner can delete it, which deletes the topic (then 404) | X1 |
| Create topic | Success redirects to the category list; no topic id returned | E14 |
| Login | Success = `Set-Cookie: md_user` equal to the pseudo; failure and login-flood texts; cookie set may include `md_pass`, `md_forum` | X5, X12 |
| CRLF | No `\n` → `\r\n` conversion in rf2; whether HFR needs it is open | X11 |
| Favourite removal | Single removal by `GET /user/delflag.php?…`; success text "Drapeau effacé…" | X6 |
| Global search | The POST answers a waiting page; results are a cookie-less `GET /forum1.php?recherches=1&…`; four result shapes | X7, E12 |
| Intra-topic search | `transsearch.php` needs `hash_check`; `dep=0` + `firstnum` only on a fresh search | E28 |
| Multi-quote | Can be done without the cookie: fetch one quote form per post, concatenate prefills, submit once | X10 |
| MPStorage read | JSON read from the first post's edit form `content_form`, not the rendered text; real documents hold many namespaces from other clients; 64 KiB safety cap; refuse to write non-BMP characters | X8, E23, E24 |
| MP | Mark unread: `GET /user/nonlu.php?…`; group MP members in `newdest` (owner only); MP quote URL shape | E6, E8, E9 |
| Read marking | Any authenticated topic GET marks flags read: prefetch anonymously | E25 |
| REST API | `GET /webservices/rest_api.php?uri=…` for categories, topics and flag buckets | E1 |
| Obfuscated links | Three prefixes: `md_noclass_cryptlink` (20), `md_blank_cryptlink` (18), `md_cryptlink` (12); intermittent; URL shape depends on auth | E7 |
| Polls | Vote body order and `reponse` / `reponse<N>` fields; close and create flows | E10, E11 |
| Identity | `numreponse` is unique per category, not global: key posts by (cat, topic, numreponse) | E18 |
| Posts per page | A user setting, not a constant 40 | E19 |
| Images | `reho.st` needs `Referer: https://forum.hardware.fr/`; some hosts are http-only: load images with a separate cookie-less client | E26 |
| `quote_only=1` | Lists posts quoting a given post | E2 |

Points the two clients disagree on are listed in the comparison report §4.4 and must be part of the LOT-001 capture checklist.

## 8. Third-party services

| Service | Use | Notes | Source |
|---|---|---|---|
| `aq.super-h.fr` | "Alerte Qualitay" community reports | GET `/api/getAlertesByTopic.php?topic_id=`; POST `/api/addAlerte.php` (fixed field order, response `"1"` = success); RSS `/rss.php` (badge, "new since" `last_check_aq`, category 25 hidden unless pseudo `applereview`); unauthenticated, sends pseudo | D §2.7, `AQPlusView.swift:29-87` (decisions Q-4, Q-7) |
| Image rehost (Chevereto) | Image upload for posts | API key required (ADR 0007) | D §3.2 |
| Giphy | GIF picker | API key required (ADR 0007) | E §6 |
