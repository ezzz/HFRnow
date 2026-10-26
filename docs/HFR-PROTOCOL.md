# HFR protocol reference

Everything we know about how forum.hardware.fr works: URLs, parameters, forms, cookies, tokens, HTML signals.
**Every entry cites its source**: a legacy `file:line` (repo <https://github.com/francoisgn/hfrnow> @ `2440d79`) and/or an audit section.
Status per fact: **code** = read from legacy code only · **live** = observed by us on the live forum (a fixture id such as `R21` points to the LOT-001 capture corpus, [`captures/MANIFEST.md`](../Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/MANIFEST.md)) · **rf2** = reported by the redface2 Android client's documentation (rewritten in our words, not copied; GPL project) · **verified** = confirmed by a committed fixture. Until Phase 2 delivers fixtures, nothing is *verified*; §7 lists the open points to settle with fixtures.

This document and the test fixtures are licensed under [CC BY 4.0](../LICENSE-docs.md) ([ADR 0009](adr/0009-open-protocol-docs-license.md)), unlike the code.

Host: `https://forum.hardware.fr` (`Classes/k.m:37-40`). Forum config `config=hfr.inc` on all pages except global search (`config=hardwarefr.inc`).

## 1. Read endpoints

| Id | Purpose | Method | URL | Notes | Source |
|---|---|---|---|---|---|
| R1 | Home: forum list, `hash_check`, MP count | GET | `/` | | `ObjCForumsLoaderWorker.m:20`, `ObjCForumsParser.m:41-42` · audit A §3.1 E1 |
| R2 | Topic list of a forum | GET | `/forum1.php?config=hfr.inc&cat={cat}&page={n}&subcat=&owntopic={0..3}` | `owntopic`: 0 all, 1 tracked (flag1), 2 read (flag0), 3 favourites. **live**: logged out, answers 301 to `/hfr/<cat>/liste_sujet-<n>.htm` and drops `owntopic` (no "not logged in" page, `R04`, `R09`); logged in, 200 without redirect, filter applied; empty filter = `.hop` text (`R08-1`, `R08-3`) | `ObjCForumTopicsLoaderWorker.m:36-89, 128-141` · A §3.1 E2 |
| R3 | Favourites across forums | GET | `/forum1f.php?owntopic={1\|3}` | `3` when setting `vos_sujets == 1`. **live**: empty or logged out = `.hop` text, logged-out `<body>` has no `id` (`R11`, `R12`) | `ObjCFavoritesLoaderWorker.m:46-48` · A E3 |
| R4 | Private messages list | GET | `/forum1.php?config=hfr.inc&cat=prive&page=1` | legacy list shows page 1 only; multi-page scan (`page=N` + long query) exists only in MPStorage | `ObjCMPTopicsLoaderWorker.m:9`, `MPStorage.m:692-736` · A E4, E §2.6 |
| R5 | Topic page | GET | `/forum2.php?config=hfr.inc&cat=..&post=..&page=..`, which redirects (301) to the canonical `/hfr/<cat>[/<sub-category>]/<slug>-sujet_<post>_<page>.htm`; the path may carry a sub-category segment, e.g. `/hfr/Programmation/Divers-6/hfr-android-sujet_148745_1.htm` (**live**, 2026-10-25, §6) | Follow redirects; the **final URL** gives the page: read it from the `sujet_<post>_<page>` segment. The legacy regex `_(\d+)\.htm` matches the same form; the older `/hfr/<cat>/<sub>/<slug>_<id>_<page>.htm` shape cited by legacy code is unverified. **live**: two 301 hops when the topic has a sub-category (`…/<cat>/<slug>-sujet_…` then `…/<cat>/<sub>/<slug>-sujet_…`), plus a 302 to the last page when `page` is past it (`R20`, `R24`) | `ObjCTopicPageWorker.m:14-43, 86-94` · A E5, §3.4 |
| R6 | Profile page | GET | `/user/editprofil.php?config=hfr.inc&page={5\|1}` | page 5: `hash_check` + avatar after login; page 1: cookie refresh. **live**: page 5 form holds `hash_check` and `page` only; page 3 holds the display settings incl. `topicpp` (posts per page); `/editprofil.php` (root) answers **500** (`R55-*`) | `LoginService.swift:87-113`, `MultisManager.m:281` · A E10 |
| R7 | Smiley search | GET | `/message-smi-mp-aj.php?config=hfr.inc&findsmilies=+w1+w2` | ≥ 3 chars. **live**: several words are OR-ed (2 words gave more results than 1); no result = 40-byte text "Désolé, aucune réponse n'a été trouvée !" (`R53a-c`) | `SmileySearchService.swift:12-42` · A E11 |
| R8 | MP unread count | GET | `/` | first integer in `.cCatTopic.red`. **live**: with no unread MP the home row "Envoyer / lire des messages privés" carries no number and no `red` class (`R03`); with unread MPs it reads "Vous avez N nouveaux messages privés" in `a.cCatTopic.red`, N = unread conversations (`R02`, §6b) | `MPBackgroundService.swift:80-135` · A E12 |
| R9 | Public profile page | GET | `/hfr/profil-{id}.htm` | `table.main` rows `profilCase2/3`, avatar, personal smileys. **live** (`R56a`, `R56b`, logged out): `body#unique__user_page__view_user_profile`, `<title>` "X - FORUM HardWare.fr", `h4` "Informations sur : X", rows label `td.profilCase2` → value `td.profilCase3` (Pseudo, Email "Vous n'avez pas accès à cette information", Date de naissance, Sexe, Ville, Profession, Loisirs, Statut, Nombre de messages postés, Date d'arrivée `dd/mm/yyyy`, Date du dernier message `dd-mm-yyyy à hh:mm`, Citation personnelle, Signature, optional Configuration matérielle); avatar `div.avatar_center img` (`mesdiscussions-<id>.jpg`, `alt` = pseudo) and personal smileys `[:code] <img …/images/perso/[N/]code.gif alt="code:N">` in `td.profilCase4`; transactions per category `transactions_reports.php?…&id_user=<id>`; links `message.php?…&dest=X` and `/hfr/recherche/pseudo-X.htm` | `UserProfileView.swift:113-430` · review F4 |

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
- Read-modify-write with no locking (lost updates possible). Legacy edits the parsed dictionary in place, so it keeps other clients' keys (`MPStorage.m:886, 908`).
- Our writes (LOT-062): only the first `0.1` entry is edited; `sourceName`/`lastUpdate` stamped on the section, the entry and the root; documents with a character outside the BMP or above 65 536 UTF-8 bytes are refused (§6, E24); a section may carry `"tombstones":[{"id":…,"deleteDate":<ms>}]`, an addition kept by the legacy iOS client (**code**, `MPStorage.m:886, 908`) and **unverified** for other writers (§7), so not written by default (`recordsTombstones` off); numbers in other clients' data are written back with their exact text; concurrent writes are merged three-way ([LOT-062](lots/LOT-062-mpstorage-merge.md)).

Source: `Classes/MPStorage.m:21-22, 152-156, 249-355, 536-666, 737-885` · D §2.10, E §2.6.

## 4. Quotes

- **Single quote**: GET the decoded `quoteURL`; the server returns the form with `content_form` prefilled `[quotemsg=a,b,c]…[/quotemsg]` (argument meaning unsettled: rf2 reports cited `numreponse`, an opaque index, cited author id — [research](research/redface2-comparison.md) §4.2 X2, open point §4.4 item 2; always reuse the server's prefill, never build it). The reply is then posted to the topic's answer URL. `ReplyService.swift:767-841` · D §2.2
- **Multi-quote** (client-side cookie, as the site's JS does): `quoteJS` = `quoter('hardwarefr', cat, post, numreponse)`; cookie `quotes<arg0>-<arg1>-<arg2>` (e.g. `quoteshardwarefr-13-42`), value = concatenated `|<numreponse>`, domain `.hardware.fr`, path `/`, expires +1 h; deleted when empty. The next quote/answer GET must carry it. Match ids **exactly** (legacy substring match is a bug, fixed in [LOT-042](lots/LOT-042-sessions.md)). `MessagesView.swift:1852-1945` · D §2.2b, C §5
- **Obfuscated URLs**: some links are stored in a CSS `class` token instead of an `href`: the token is a prefix immediately followed by the payload. Prefixes: `md_noclass_cryptlink` (20 characters; quote and edit links, the element around `<img alt="answer">`), `md_cryptlink` (12; list pager, menus) and, reported by rf2 only, `md_blank_cryptlink` (18) (E7, §7). Decode: drop the prefix, then map each pair of characters through the alphabet `0A12B34C56D78E9F` (index = nibble, high first) into one byte; the bytes are the URL. Decode only when the token is longer than its prefix and the value contains neither `/` nor `http` (otherwise it is a link in clear). Implemented by `ObfuscatedURL` (LOT-020). `RangeOfCharacters.m:92-138`, `ObjCMessageActionsBuilder.m:80-89`, `ObjCTopicListParser.m:192-245` · C §3.4, D §2.2, [user feedback](research/user-feedback-p450-510.md) §4
- **Obfuscated quote link in practice** (**live**, 2026-10-26, 13 topic pages of the LOT-001 captures R20–R32b, anonymous and logged in): every post wraps `<img alt="answer">` in `<span class="md_noclass_cryptlink<hex>">`; the 20-character prefix is exactly `md_noclass_cryptlink`. The decoded value is `/message.php?config=hfr.inc&cat=<cat>&post=<topic>&numrep=<numreponse>&ref=<rank>&page=<page>&p=1&subcat=<sub>&sondage=0&owntopic=0&new=0#formulaire`, the same URL as the visible `answer +` link of logged-in pages; `ref=0` on the "Reprise du message précédent" block that opens page 2+ (a copy of the previous page's last post, same `numreponse`). A value of odd length makes the legacy decoder raise ([LOT-003](lots/LOT-003-topic-oracle.md) Q27).

## 5. Session, cookies and tokens

- **Login**: POST `/login_validation.php?config=hfr.inc` with `pseudo, password, action=send, login=Se connecter`; success ⇔ body contains `login_redirection.php`; then GET R6 page 5 for `hash_check` and avatar. Legacy clears all cookies *before* validating (bug). `LoginService.swift:48-129` · A §4.2
  **live** (`W00`, `W01`, `W03`): HTTP 200 either way. Success body "Vérification de votre identification..." with a 1 s `<meta refresh>` to `login_redirection.php?config=hfr.inc&referer_page=…`; failure = `.hop` "Votre mot de passe ou nom d'utilisateur n'est pas valide", 2 s refresh to `/`, no `Set-Cookie`. The legacy body (`action=send`, `login=Se connecter`) is accepted; the site's own form `form1` sends `hash_check` (empty), `pseudo`, `password`, `cat`, `page`, `config`, `p`, `sondage`, `owntopic`, `post`, `referer`, `Valider`.
- **Identity cookie**: `md_user`; value `deleted` = logged out. A §4.1
  **live** (`W03`): login sets exactly `md_user` (URL-encoded pseudo, equal to the submitted one), `md_passs` (32 hex) and `md_id` (the numeric profile id), each `expires` +30 days, `path=/`, `domain=.hardware.fr`. No `md_pass` or `md_forum`. List pages also set a non-secret `p=1`.
  **live** (`W10`-`W20b`): every accepted or flood-refused `bddpost.php` / `bdd.php` answer also sets `md_data` (the rejected `W17a-c` do not) (value not analysed; treated as a secret and redacted like the session cookies).
- **`hash_check`**: anti-CSRF token required by every POST; hidden input on R1, R3 and R6 pages and in the topic page `hop` and `transsearch` forms (`name="hash_check"`). Per account; refreshed from parse results by `HFRClient`. **live**: 32 hex characters when logged in, empty value when logged out (`R01`, `R03`, `R40a`, `R40b`). The logged-in header also carries a logout link `/unlog.php?config=hardwarefr.inc&codehex=<32 hex>` (a per-session token distinct from `hash_check` and the cookies; treat it as a secret, `R21`). `ObjCForumsParser.m:41`, `ObjCFavoritesLoaderWorker.m:105`, `LoginService.swift:100`, `ObjCTopicPageWorker.m:150-179` · A §3.1, C §3.3
- **Session isolation** (decided, [LOT-042](lots/LOT-042-sessions.md)): one `HFRSession` per account with its own jar and `hash_check`; no global jar, no global token. An account session contacts only `*.hardware.fr` and does not follow a redirect leaving it or downgrading to HTTP. Prefetch and images use a cookie-less transport (§7 E25, E26). Replaces the legacy shared jar wiped and refilled on every account switch and before list loads, with `quotes*` cookies saved and restored around it, and the global `hash_check` fallback (**code**). `AccountSessionService.swift:77-110`, `MultisManager.m:155-165`, `Common.swift:1402-1406` · A §4.1, §4.3-4.4
- **Not logged in** on favourites (R3): `<body>` without `id`; message = first `<p>` or `.hop` text. `ObjCFavoritesLoaderWorker.m:87-95`

## 6. Transport behaviour

- **Encoding — UTF-8** (**live**, 2026-10-25: `Content-Type: text/html; charset=utf-8` and `<meta charset=UTF-8>` on topic 1711 pages 450–510, [user feedback](research/user-feedback-p450-510.md) §4; rf2 captures agree, [research](research/redface2-comparison.md) §4.3 E27). Legacy Latin-1 fallbacks are unnecessary for HTML pages; other endpoints still to capture. A §3.2
  **live** (LOT-001 corpus): all 99 HTML answers of the corpus are `text/html; charset=utf-8` (97 committed pages incl. forms, smiley search fragments and login, plus the two meta-only redirects `R25`, `R52a`), the 3 REST answers `application/json`; only Apache's own 404 page (not committed) is `iso-8859-1`.
- **Topic URL redirect** (**live**, 2026-10-25, request to topic 1711 page 450; rf2 agrees, [research](research/redface2-comparison.md) §4.3 E13): `forum2.php?…&page=N` answers **301** with a relative `Location: /hfr/<cat>[/<sub-category>]/<slug>-sujet_<post>_<N>.htm`; read the page from the `sujet_<post>_<N>` segment.
- **Topic slug** (**live**, LOT-001 corpus: 341 distinct title/slug pairs of the topic lists `R04`, `R05a`, `R05b`, `R06`, `R07`, `R09`, `R27-list`, `R50b`; no legacy code builds slugs, the server does): the `<slug>` of `<slug>-sujet_<post>_<page>.htm` is made of **at most 3 words** of the title, in title order (no slug has more, including titles of 5+ long words); which words are kept is not predictable (short words usually go, some long ones too). Words are lower case without accents; `_` and non-ASCII punctuation (`’`) are deleted, joining the words around them; any other character separates words. Example `R07`, topic 21064: a 7-word title `[<pseudo>] colo en cours 10-2018` gives a 3-word slug `<one word of the pseudo>-cours-2018`.
- **Emoji** (**rf2**, [research](research/redface2-comparison.md) §4.2 X9; users report the same, [user feedback](research/user-feedback-p450-510.md) p. 478; decides Q-3): HFR cuts a posted message at the first character outside the Basic Multilingual Plane (most emoji) and still answers success; everything after it is lost silently. Never send such characters. **live** (`W12`, `R43c`): "before 😀 after" answered success and was stored as "before".
- **Legacy emoji stripping** (**code**, `AddMessageViewController.m:553`, `AlerteModoViewController.m:209`, `-[NSString removeEmoji]` in `SuperHFRplus/Helpers/RangeOfCharacters.m:306`): the legacy client strips some emoji before posting (sample `form-reply-emoji`: 😀 and ☺ removed, ❤ kept); the live Swift path posts the text unchanged. The SwiftHFR policy is decision Q-3 ([audit README](audit/README.md#decisions-needed)), not yet implemented. [LOT-004](lots/LOT-004-forms-storage-oracle.md) quirk 15b.
- **Dates**: printed as `dd-MM-yyyy à HH:mm` in lists and `dd-MM-yyyy à HH:mm:ss` in message toolbars and edit trailers, French wall-clock time in `Europe/Paris` with no offset; an hour repeated by the October DST change is therefore ambiguous (SwiftHFR takes the first occurrence, LOT-020). `ObjCTopicListParser.m:421-424`, `Favorite.m:119-123`, `ParseMessagesOperation.m:398-401` · B §3.3.5, [user feedback](research/user-feedback-p450-510.md) §4
- **Form encoding** (decided, [LOT-040](lots/LOT-040-transport.md)): bodies are `application/x-www-form-urlencoded; charset=utf-8`, every non-ASCII byte percent-encoded (legacy global search sent accents raw, `ObjCForumSearchWorker.m:194-199`). Line breaks are sent as typed unless a poster chooses CRLF (open, §7 X11).
- **HTTP status**: legacy ignores it; application errors are detected from content (`.hop`, `login_redirection.php`, missing `id`, `Location`). A §3.4 The new transport throws on 4xx/5xx ([LOT-040](lots/LOT-040-transport.md)).
- **URL building** ([LOT-041](lots/LOT-041-endpoints.md)): `HFREndpoint` builds every §1–2 request with the query order shown in the tables. Topic pages are always requested through `forum2.php` (the canonical path is never rebuilt, its sub-category segment is not derivable); query values use strict percent-encoding (`%20` for space, `%2B` for `+`). Exception: the REST `uri` value keeps `/` literal (`uri=forums/hardwarefr/categories/`), never `%2F`.
- **Headers**: no custom User-Agent, Referer or Origin; gzip accepted. Whether HFR checks any is unverified. A §3.3
- **Timeouts** (legacy): lists 30 s, topic search 60 s, global search 15 s, background MP check 5 s. No retry, no backoff, no rate limiting. A §3.5

## 6b. Live observations from the capture corpus (LOT-001, 2026-10-26)

Fixture-backed (**live**) facts not covered by a row above. Ids refer to `Fixtures/captures/`.

- **Composer** (`R40a`, `R40b`): `#repondre_form`'s first link is `message.php?config=hfr.inc&cat&post&page&p=1&subcat&sondage=0&owntopic=0&new=0`; it serves `<form name="hop" action="/bddpost.php?config=hfr.inc">` with, in order: `hash_check, subcat, parents, post, stickold, new, cat, numreponse, numrep, page, verifrequet, p, sondage, sond, cache, owntopic, config, sujet, pseudo, password, MsgIcon` (radio, 1 checked), `search_smilies, ColorUsedMem, content_form, wysiwyg=0`, a submit `submit`, then checkboxes `signature`, `smiley`, `emaill` (all **unchecked** by default for this account). Logged in, `pseudo` is echoed and `password` empty; logged out, both are empty fields and `hash_check` is empty. The JS mentions an optional `codecaptcha` field, never rendered here.
- **Quote** (`R41a`, `R41b`): prefill `[quotemsg=<cited numreponse>,<ref>,<cited author's user id>]`: the second value is the `ref` (rank of the post on its page) of the quote URL, in topics as well as MPs. The form keeps `numrep=<cited>`.
- **New topic** (`R45a`): the form is at the category path `/hfr/<cat>/nouveau_sujet.htm` (the sub-category path answers 404); extra fields `sujet`, `toread1..5`, `subcat` `<select>` with no option selected. **New MP** (`R45b`): `cat=prive`, `dest` text field prefilled from the URL, `sujet`, no `subcat`, `cache` empty.
- **Moderator alert form** (`R46`): `action` relative to `/user/` with a reordered query `modo.php?cat&ref&post&numreponse&page&config=hfr.inc` (the `ref` we sent, 1); fields `hash_check, referer_page, raison, Submit`.
- **Topic pages** (`R20`-`R28`): only logged-in pages carry the multi-quote JS `quoter('hardwarefr','<cat>',<post>,<numreponse>)` (`R21`; none in `R20`, `R26`); no `listenumreponse[i] = …` assignments were found (E30 not confirmed). A middle page can hold fewer than 40 bodies (`R22a`: 33). Logged in adds `addflag.php`, `delflag.php` and two `modo.php` link shapes (`R21`).
- **Permalink** (`R25`): `forum2.php?…&page=1&numreponse=M` → 301, empty body, relative `Location: /hfr/<cat>/<slug>-sujet_<post>_<page>.htm#t<M>` (first hop without the sub-category).
- **Home** (`R01`): 19 category links, including `apple` and `ia`; the REST API lists 20 categories (`R57a`).
- **Checkbox values** (`W11`, `W13b`, `W15`, `RA2`, `RA3`): HFR reads the value, not the presence: legacy `smiley=0` kept smileys, `smiley=1` (box checked) disabled them; `delete=0` on an edit does not delete. The legacy "1"/"0" copy is therefore safe; browser semantics also work.
- **Flood** (`W20a`, `W14x`, `W13cx`): the topic's first post counts; after 3 consecutive posts the next is refused until the last post is 10 minutes old (a reply 12 min after passed, one 23 s after did not). The count is not per account: user1's first post after user2's three was refused too (same client, probably per IP). New topics: one per 60 minutes (`W11x`).
- **MP list** (`R13a`, `R13b`, `R13u1`): `[non lu]` is `<span class="red" title="Ce message n'a pas été lu par : <pseudo>">` and means the **other party** has not read it; one's own unread state is the `closedbp.gif` icon. The home count "Vous avez N nouveaux messages privés" in `a.cCatTopic.red` equals the number of unread conversations (`R02`: 10 = 10 `closedbp` rows).
- **Edit permissions** (`RU1`, `R44`): the recipient gets no edit link on the other account's posts, but a hand-built edit URL for the other account's message, requested by the thread owner, still serves a prefilled `/bdd.php` form without a delete box (never submitted).
- **Printed pseudos** (`R04`-`R13u1`, `R20`): list pages (author and last-poster columns) insert U+200B after the 10th character of a longer pseudo, topic pages keep it in some author cells but not in links; compare names without zero-width characters. Personal smiley files keep a raw apostrophe or space in their path (`/images/perso/[N/]<code>.gif`, `R53b`), with the `[:code:N]` code in `alt`/`title`.
- **Flags** (`P03a`-`P03f`): `addflag.php` (link from the post, with `ref`, `page`, `p`) answers "Favori positionné avec succès" and is idempotent; its refresh goes to the sub-forum list.

## 6c. Verified by parser tests

Facts confirmed by a committed capture **and** asserted by a test of the parser that reads it (**verified**). Ids refer to `Fixtures/captures/`.

### LOT-022 — topic lists

[LOT-022](lots/LOT-022-topic-list-parser.md), tests `TopicListDifferentialTests` and `TopicListParserTests`.

- **List body**: `<body id="category__topics_listing__listing_topic">` (forums), `…__results_search` (search), `unique__topics_listing__listing_private_thread` (MP). A bare `<body>` with a `.hop` block is a message instead of a list: empty `owntopic=1`/`3` lists (with a 1 s refresh to the forum list) and an empty search (`R08-1`, `R08-3`, `R50c`). An empty MP list keeps the list body with a `th.s2Tableau` "Aucun message posté" (`R13c`).
- **Rows**: `tr.sujet.ligne_booleen` (+ `ligne_sticky`), cells `sujetCase1`…`sujetCase9`, plus `sujetCase10` (checkbox `topic<N>` = post, hidden `valuecat<N>`) when logged in. Title link `a.cCatTopic` with `title="Sujet n°<post>"`: a canonical `/hfr/<cat>/[<sub>/]<slug>-sujet_<post>_1.htm` on anonymous lists and search results, a `forum2.php?…&cat=…&post=…` link on logged-in and MP lists (`R04`, `R08-2`, `R13u1`, `R50b`).
- **Row icons**: unread = `sujetCase1` image `alt="On"`; anonymous lists show `closedb_new.gif` "On" on every row; MP lists use `closedbp.gif` "On" / `closedp.gif` "Off" (`R04`, `R13a`, `R13b`). Poll = `…/images_forum/1/sondage.gif` in `sujetCase2` (`R04`: 14 rows); closed = `img alt="closed"` (`lock.gif`) in `sujetCase3`; flag = `sujetCase5` link to `forum2.php…&page=<p>…#t<numreponse>` with `flag0.gif` (`R08-2`).
- **Starter cell** (`sujetCase6`): plain text when anonymous, `a.Tableau` to `profilebdd.php?…&pseudo=` when logged in, `<span title="<pseudos>">Interlocuteurs multiples</span>` for MP group threads (`R04`, `R08-2`, `R13u1`). Long pseudos carry U+200B there and in the last-post `<b>`.
- **Pager** (`tr.fondForum1PagesHaut`): `div.left` = `<b>Page :</b>`, then the window (pages 1-10, tens, hundreds around the current one), current page `<b>N</b>`, others `a.cHeader` or `span.md_cryptlink<hex>`; two `div.pagepresuiv` (next, previous), disabled = `span.cFondu` (`R04`, `R05a`, `R05b`). Search results paginate with another URL shape (`page=2&…&search=<UPPERCASED>`) (`R50b`).
- **Header**: `form#fastsearch` holds a hidden `cat` (`13`, `12`, `10`, `prive`) on every list page, logged in or not; the tabs `div.cadreonglet` `#onglet1`-`#onglet4` and `#onglet9` (search, with `cat=`) appear on logged-in forum lists only, not on anonymous lists nor the MP list (`R04`, `R08-2`, `R13a`). Logged-in forum lists have `table.none` with 3 cells, the middle one "Vous avez N nouveau message privé" or just "Messages privés" (`P03f`, `R08-2`).
- **Search rows** (`R50b`): `sujetCase3` holds the title link, then a `forum2.php?…&numreponse=<n>` link around `span.s1` (the matching message, ending "[...] ").

### LOT-030 — message blocks

Source: [LOT-030](lots/LOT-030-message-blocks.md), `MessageBlockParser`, on the 20 topic oracles of LOT-003 (`R20`–`R32b`, `RA1`–`RA5`, `RU1`, `RU2`; 358 messages).

- **Block layout**: one `<table class="messagetable">` per message, holding one `<tr class="message …">` with `<td class="messCase1">` (author cell) and `<td class="messCase2">` (content cell). The author cell starts with `<a name="t<numreponse>"></a>` (MP threads add `<a name="bas"></a>` right after it on the last post), the pseudo is `<b class="s2">`; the content cell holds `<div class="toolbar">` (date and action links), then `<div id="para<numreponse>">` (the message HTML), then optionally `<div class="edited">`. No other element carries an `id` containing `para`.
- **Advertisement block** (`R20`, `R22a`, `R23`, `R27`, `R27b`, `R31`, `R32a`): the same `messagetable` with `<b class="s2">Publicité</b>`, no `<a name>` anchor and no `para` element; 3 per logged-out page (1 on single-page topics), **none logged in** (`R21`, `R32b`: 40 tables, 40 messages). Skipped by the author cell text.
- **Continuation block** (`R22a`, `R22b`, `R24`, `R26`, `R27`, `R28`): page 2 and later open with a copy of the previous page's last post (same `numreponse`), whose content starts `<p><strong>Reprise du message précédent :</strong><br />`; its quote link carries `ref=0`. Page 1, single pages and MP threads have none.
- **Toolbar date**: `Posté le dd-MM-yyyy&nbsp;à&nbsp;HH:mm:ss` (U+00A0 around `à`), one per block on all 358 messages.
- **Edit trailer** `div.edited` (`R20`, `R22b`, `R27`, `R32a`): `<a href="/forum2.php?…&numreponse=<n>&quote_only=1&new=0&nojs=0" class="cLink">Message cité N fois</a>`, then `<br />Message édité par <pseudo> le dd-MM-yyyy&nbsp;à&nbsp;HH:mm:ss`, either part alone or both in this order; the `quote_only=1` link is the only link of the trailer.
- **Avatar** (`RU2`): `<div class="avatar_center" style="clear:both"><img src="https://forum-images.hardware.fr/images/mesdiscussions-<user id>.jpg" alt="">` inside the author cell; present only on the recipient's own post of the MP thread, on no public capture.
- **Pseudos**: the author cell prints U+200B inside some pseudos (`R21` message 0, `RA1`); the legacy `LinkItem.name` of the oracle has none, so the parser drops it.
- **Deleted conversation** (`RA5`): a page without any `messagetable` is an ordinary page (`.hop` notice), not an error.
- **Pending capture**: the `messagetabledel` wrapper of a deleted post (legacy `ParseMessagesOperation.m:153`; `RA3` shows that a deleted MP post simply disappears) and the in-topic search result shape (a leading `<a>` in `messCase2`, `:365-368`).

### LOT-033 — topic page metadata

Source: [LOT-033](lots/LOT-033-topic-page-metadata.md), `TopicPageMetadataParser`, checked by `TopicPageMetadataOracleTests` on the 20 LOT-003 oracle cases `R20`, `R21`, `R22a`, `R22b`, `R23`, `R24`, `R26`, `R27`, `R27b`, `R28`, `R31`, `R32a`, `R32b`, `RA1`, `RA2`, `RA3`, `RA4`, `RA5`, `RU1`, `RU2`; `R25` is excluded (no body).

- **Title**: the `h3` of the `tr.fondForum2Title` row ("Sujet : <h3>…</h3>"), present on every page with messages; absent on "Ce message ne vous est pas destiné" (`RA5`).
- **Pager**: `tr.fondForum2PagesHaut` holds `div.left` with `Page :` in a `<b>`, numbered links, `..` for gaps; the current page is a `<b>` number (first and last page included, `R20`, `R22b`), the last child is the highest page. A single-page topic has no `div.left` (`R23`, `R27b`, `R31` and the private threads); `R23` and `R31` keep the row with only a "Bas de page" link.
- **Current page** is not in the page: it comes from the URL served. A page beyond the end is redirected to the last page (`R24`, final URL `…_2201.htm`).
- **Answer form**: `form#repondre_form` with a hidden `hash_check`, a hidden `repondre_contenu` and one `a` to `/message.php?config=hfr.inc&cat=&post=&page=&p=&subcat=&sondage=0&owntopic=0&new=0`; only logged in, and absent on the locked topic as seen by a visitor (`R31`) like on every anonymous page.
- **Quick-answer form** `form[name=hop]` (action `/bddpost.php`): 17 hidden inputs when logged in (`cache, cat, config, emaill, hash_check, new, numrep, owntopic, p, page, post, pseudo, signature, sondage, subcat, sujet, verifrequet`); `cat=prive` on private conversations; absent anonymous (`R20`) and on a conversation the owner deleted (`RU2`). `hash_check` is a secret.
- **In-topic search form** `form[action="/transsearch.php"]` exists for visitors too (empty `hash_check`); it carries `cat` and `post` when `hop` does not. Absent on `RA5`.
- **`nonlu`**: a link whose `href` contains `nonlu` exists on every private conversation page that shows messages (`RA1`–`RA4`, `RU1`, `RU2`; not on the empty `RA5`) and on no public topic page of the corpus.
- **Poll block**: `div.sondage` exists on `R32a`, `R32b`, `R33a` and `R33b` only.

### LOT-026 — poll

- **Poll vote form** (`R32a`, `R32b`, **verified**, [LOT-026](lots/LOT-026-poll-parser.md)): logged out **and** logged in (not voted) the topic page shows the voting form, never results. `<form method="post" action="/user/vote.php?config=hfr.inc"><input type="hidden" name="hash_check">` wraps `<div class="sondage">` which holds the hidden inputs `cat, p, page, sondage, owntopic, subcat, numeropost, hash_check` (in this order; `hash_check` empty logged out, so a second copy of the token sits outside the block), the question in `<b class="s2">`, `<ol type="1">` with one `<li><input type="radio" value="N" id="sondN" name="reponse"><label for="sondN">` per answer (**value = 1-based position**, single field name `reponse`, no footer, no multi-choice hint), then two submit inputs named `sondage_submit`: "Voter" and "Voir les résultats" (followed by the text warning that viewing results forfeits the vote). No `verifrequet`. Whether the vote needs `sondage_submit=Voter` is not tested (POST not made).
- **Poll results** (`R33a` closed, anonymous; `R33b` already voted, user1, **verified**): no form, no input. The block keeps `<b class="s2">` then, per answer, `<div class="sondageLeft" style="position:relative">` (`<div class="barre" style="width:N%">`, whose width is not the percentage, then `<div class="sondageTop">65.2&nbsp;%</div>` and `<div class="sondageTop">&nbsp;116 votes</div>`), `<div class="sondageRight">1.&nbsp; Hugo Lloris</div>` (printed rank, NBSP, space) and `<div class="spacer">`; it ends with `<div><b>Total : 194 votes</b>&nbsp;(16 votes blancs)</div>` (answers plus blank votes equal the total). Percentages use a decimal **point** with one decimal. A closed (locked) poll adds `<b class="s1Ext">Ce sondage est clos, vous ne pouvez plus voter</b>` right after the block; an already-voted poll shows "(Multipseudo detecté, vous ne pourrez pas voter à ce sondage avec vos autres pseudos)" as text inside the block after the question (also seen by the operator's other account, so it does not say which account voted). No `sondageFooter`. A plain "already voted" page and multi-choice polls: not captured.


## 7. Reported by redface2, to verify with our fixtures

Facts from the redface2 project documentation, rewritten here; each becomes *verified* only through a LOT-001 fixture. Source: [docs/research/redface2-comparison.md](research/redface2-comparison.md) §4 (ids X/E below).

| Topic | Reported fact | Id | Result (LOT-001, 2026-10-26) |
|---|---|---|---|
| Write constant | Every `bddpost.php` / `bdd.php` POST carries `verifrequet=1100`; the poll vote does not | X4 | **Settled**: hidden input of every write form (`R40a`, `R43a`, `R45b`, `R47b`) and present in every accepted POST body (`W10`-`W19`); not in the vote form (`R32a`) |
| Write markers | Distinct success sentences for reply, edit, create and delete; specific texts for empty body, invalid token, flood | E15 | **Settled** (MP, `W10`-`W19`): reply "Votre réponse a été postée avec succès !" (refresh `…#bas`), edit "Votre message a été édité avec succès !" (`…#t<n>`), create "Votre message a été posté avec succès !", delete "Message effacé avec succès !" (also for a post already deleted, `W16b`), empty body "Vous devez remplir tous les champs avant de poster ce message", bad token 99-byte plain text "Une erreur est survenue lors de l'envoi des données. Essayez de vider le cache de votre navigateur", flood "Afin de prevenir les tentatives de flood, vous ne pouvez poster plus de 3 réponses consécutives dans un intervalle de 10 minutes", logged out "Désolé, vous devez être enregistré pour poster sur le forum"; new-topic flood "… plus de 1 nouveaux sujets consécutifs dans un intervalle de 60 minutes" (`W11x`) |
| First post | Owner can delete it, which deletes the topic (then 404) | X1 | **MP variant settled, differs**: the owner's first-post edit form offers "Effacer l'intégralité du sujet" (`R43a`); the POST answers "Message effacé avec succès !" (`W19`), after which the owner gets 200 + "Ce message ne vous est pas destiné, désolé" (`RA5`, not 404), but the **recipient keeps the whole thread** (`R13u1b`, `RU2`). Public-topic variant not tested |
| Create topic | Success redirects to the category list; no topic id returned | E14 | Unsettled for topics. MP creation: success refreshes to the MP list, no thread id (`W10`) |
| Login | Success = `Set-Cookie: md_user` equal to the pseudo; failure and login-flood texts; cookie set may include `md_pass`, `md_forum` | X5, X12 | **Settled in part**: `md_user` = pseudo on success, exact failure text (`W01`, `W03`). **Contradicts** the cookie set: `md_user`, `md_passs`, `md_id`, no `md_pass`/`md_forum`. Login-flood text not observed |
| CRLF | No `\n` → `\r\n` conversion in rf2; whether HFR needs it is open | X11 | **Settled**: bare LF and CRLF are both accepted and stored as sent (`R43a`, `R43b`); CRLF renders as `\r<br />` (`RA2`); server prefills use CRLF (`R41a`) |
| Favourite removal | Single removal by `GET /user/delflag.php?…`; success text "Drapeau effacé…" | X6 | **Settled for a favourite**: `GET /user/delflag.php?…&owntopic=3` answers "Drapeau effacé avec succès" (`P03d`) and also removed the topic's read flag (`P03f`) |
| Global search | The POST answers a waiting page; results are a cookie-less `GET /forum1.php?recherches=1&…`; four result shapes | X7, E12 | **Settled in part**: the POST answers "Votre recherche est en cours…" with a refresh to `GET /forum1.php?recherches=1&…&config=hfr.inc` (`R50a`); that GET works without cookies, 50 rows per page despite `resSearch=200`, with `post_cat_list` (`R50b`); no result = `.hop` "Désolé, aucune réponse n'a été trouvée !" (`R50c`). Pivot shapes not captured |
| Intra-topic search | `transsearch.php` needs `hash_check`; `dep=0` + `firstnum` only on a fresh search | E28 | **Settled in part**: the page form sends `hash_check, post, cat, config, p, sondage, owntopic, word, spseudo, [filter], dep=0, firstnum`; a match answers **302** `Location: /forum2.php?…&word=<UPPERCASED>&spseudo=&currentnum=<match>#t<match>` (`R52a`), no match 200 + `.hop` "Désolé aucune réponse n'a été trouvée" (`R52b`). Stepping not tested |
| Multi-quote | Can be done without the cookie: fetch one quote form per post, concatenate prefills, submit once | X10 | Partly: the cookie route works server-side on topics (`R42`) and MPs (`R47c`, cookie `quoteshardwarefr-prive-<post>`; posted in `W14`); the cookie-less route was not tested |
| MPStorage read | JSON read from the first post's edit form `content_form`, not the rendered text; real documents hold many namespaces from other clients; 64 KiB safety cap; refuse to write non-BMP characters | X8, E23, E24 | Unsettled: an MPStorage thread exists in user1's list (`R13u1`, subject kept) but was not opened |
| MPStorage unknown keys | Whether DTCloud, redface2 and userscripts keep a key they do not know (our `tombstones`, §3.3) when they rewrite the document; legacy iOS does (code). Until verified, LOT-062 writes no tombstone (`recordsTombstones` off by default) | LOT-062 | Unsettled |
| MP | Mark unread: `GET /user/nonlu.php?…`; group MP members in `newdest` (owner only); MP quote URL shape | E6, E8, E9 | **E6 settled**: `nonlu.php` answers "Le message a été marqué comme non lu avec succès" and the list icon turns `closedbp.gif` (`W18`, `R13b`). **E8**: no `newdest` in a one-to-one MP composer, owner or recipient (`R47b`, `R47u1`). **E9 settled**: MP quote form prefill `[quotemsg=<cited>,<ref>,<author id>]` (`R47a`) |
| Read marking | Any authenticated topic GET marks flags read: prefetch anonymously | E25 | **Settled**: one authenticated GET of a topic page (`R21`) put it in the account's `owntopic=2` list (`R08-2`) |
| REST API | `GET /webservices/rest_api.php?uri=…` for categories, topics and flag buckets | E1 | **Settled**: JSON, hrefs `https://forum.hardware.fr/api/…`, 25 per page for topics, 20 categories (`R57a-c`); 404 of `/api/` hrefs not tested |
| Obfuscated links | Three prefixes: `md_noclass_cryptlink` (20), `md_blank_cryptlink` (18), `md_cryptlink` (12); intermittent; URL shape depends on auth | E7 | **Partly contradicted**: `md_noclass_cryptlink` (post action links) and `md_cryptlink` (header, list pager from page 2, also logged out) seen (`R05a`, `R20`); `md_blank_cryptlink` not seen; logged-in action links keep the anonymous `message.php?…&numrep=…&ref=…` shape, no `citer-…htm`/`editer-…htm` (`R21`) |
| Polls | Vote body order and `reponse` / `reponse<N>` fields; close and create flows | E10, E11 | Partly (E10): vote form `/user/vote.php?config=hfr.inc`, hidden fields `hash_check, cat, p, page, sondage, owntopic, subcat, numeropost` then a second `hash_check`, radio `reponse` = 1..N, shown logged out too (`R32a`, `R32b`); POST not made. A non-votable poll has no `<form>` and no input, only the results (`div.sondageLeft` bar + `sondageTop` percent and `N votes`, `div.sondageRight` option, `Total : N votes (M votes blancs)`): closed "Ce sondage est clos, vous ne pouvez plus voter" (`R33a`, locked topic), already voted from a linked account "(Multipseudo detecté, vous ne pourrez pas voter à ce sondage avec vos autres pseudos)" under the question (`R33b`) |
| Identity | `numreponse` is unique per category, not global: key posts by (cat, topic, numreponse) | E18 | Unsettled |
| Posts per page | A user setting, not a constant 40 | E19 | **Settled**: setting `topicpp` on profile page 3 (`R55-p3`) |
| Images | `reho.st` needs `Referer: https://forum.hardware.fr/`; some hosts are http-only: load images with a separate cookie-less client | E26 | Unsettled |
| `quote_only=1` | Lists posts quoting a given post | E2 | Not captured (R34 dropped) |

Points the two clients disagree on are listed in the comparison report §4.4 and must be part of the LOT-001 capture checklist.

## 8. Third-party services

| Service | Use | Notes | Source |
|---|---|---|---|
| `aq.super-h.fr` | "Alerte Qualitay" community reports | GET `/api/getAlertesByTopic.php?topic_id=`; POST `/api/addAlerte.php` (fixed field order, response `"1"` = success); RSS `/rss.php` (badge, "new since" `last_check_aq`, category 25 hidden unless pseudo `applereview`); unauthenticated, sends pseudo | D §2.7, `AQPlusView.swift:29-87` (decisions Q-4, Q-7) |
| Image rehost (Chevereto) | Image upload for posts | API key required (ADR 0007) | D §3.2 |
| Giphy | GIF picker | API key required (ADR 0007) | E §6 |
