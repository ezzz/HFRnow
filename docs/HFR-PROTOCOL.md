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
| R3 | Favourites across forums | GET | `/forum1f.php?owntopic={1\|3}` | `3` when setting `vos_sujets == 1`. **live**: logged out = `.hop` text, `<body>` without `id` (`R12`); logged in with no favourite on `owntopic=3` = list body without row (`R11`, `P03e`); `owntopic=1` with nothing flagged not captured | `ObjCFavoritesLoaderWorker.m:46-48` · A E3 |
| R4 | Private messages list | GET | `/forum1.php?config=hfr.inc&cat=prive&page=1` | legacy list shows page 1 only; multi-page scan (`page=N` + long query) exists only in MPStorage | `ObjCMPTopicsLoaderWorker.m:9`, `MPStorage.m:692-736` · A E4, E §2.6 |
| R5 | Topic page | GET | `/forum2.php?config=hfr.inc&cat=..&post=..&page=..`, which redirects (301) to the canonical `/hfr/<cat>[/<sub-category>]/<slug>-sujet_<post>_<page>.htm`; the path may carry a sub-category segment, e.g. `/hfr/Programmation/Divers-6/hfr-android-sujet_148745_1.htm` (**live**, 2026-10-25, §6) | Follow redirects; the **final URL** gives the page: read it from the `sujet_<post>_<page>` segment. The legacy regex `_(\d+)\.htm` matches the same form; the older `/hfr/<cat>/<sub>/<slug>_<id>_<page>.htm` shape cited by legacy code is unverified. **live**: two 301 hops when the topic has a sub-category (`…/<cat>/<slug>-sujet_…` then `…/<cat>/<sub>/<slug>-sujet_…`), plus a 302 to the last page when `page` is past it (`R20`, `R24`) | `ObjCTopicPageWorker.m:14-43, 86-94` · A E5, §3.4 |
| R6 | Profile page | GET | `/user/editprofil.php?config=hfr.inc&page={5\|1}` | page 5: `hash_check` + avatar after login; page 1: cookie refresh. **live**: page 5 form holds `hash_check` and `page` only; page 3 holds the display settings incl. `topicpp` (posts per page); `/editprofil.php` (root) answers **500** (`R55-*`) | `LoginService.swift:87-113`, `MultisManager.m:281` · A E10 |
| R7 | Smiley search | GET | `/message-smi-mp-aj.php?config=hfr.inc&findsmilies=+w1+w2` | ≥ 3 chars. **live**: several words are OR-ed (2 words gave more results than 1); no result = 40-character text "Désolé, aucune réponse n'a été trouvée !" (`R53a-c`) | `SmileySearchService.swift:12-42` · A E11 |
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
4. POST `application/x-www-form-urlencoded; charset=utf-8` to the form `action`, resolved against the form URL. The legacy app defaulted to `/bddpost.php` when the form had no usable action; SwiftHFR must not use that fallback: `HopFormParser` returns `ForumForm.action` resolved and restricted to the forum origin ([LOT-036](lots/LOT-036-hop-form-parser.md)), and when it is `nil` (absent, empty or off-origin) [LOT-048](lots/LOT-048-post-form-engine.md) rejects the write (`missingAction`) and substitutes no default. **live**: edit forms post to `/bdd.php?config=hfr.inc`, on private messages (`R43a`–`R44`) and on public topics, later post (`R62a`, `R62b`) and first post (`R63b`) — **always read the action, never hard-code**.
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
- **Legacy emoji stripping** (**code**, `AddMessageViewController.m:553`, `AlerteModoViewController.m:209`, `-[NSString removeEmoji]` in `SuperHFRplus/Helpers/RangeOfCharacters.m:306`): the legacy client strips some emoji before posting (sample `form-reply-emoji`: 😀 and ☺ removed, ❤ kept); the live Swift path posts the text unchanged. The SwiftHFR policy is decision Q-3 ([audit README](audit/README.md#decisions-needed)): [LOT-048](lots/LOT-048-post-form-engine.md) refuses a text, subject or recipient holding a character above U+FFFF before sending, and strips nothing. [LOT-004](lots/LOT-004-forms-storage-oracle.md) quirk 15b.
- **Dates**: printed as `dd-MM-yyyy à HH:mm` in lists and `dd-MM-yyyy à HH:mm:ss` in message toolbars and edit trailers, French wall-clock time in `Europe/Paris` with no offset; an hour repeated by the October DST change is therefore ambiguous (SwiftHFR takes the first occurrence, LOT-020). `ObjCTopicListParser.m:421-424`, `Favorite.m:119-123`, `ParseMessagesOperation.m:398-401` · B §3.3.5, [user feedback](research/user-feedback-p450-510.md) §4
- **Form encoding** (decided, [LOT-040](lots/LOT-040-transport.md)): bodies are `application/x-www-form-urlencoded; charset=utf-8`, every non-ASCII byte percent-encoded (legacy global search sent accents raw, `ObjCForumSearchWorker.m:194-199`). Line breaks: HFR accepts LF and CRLF and stores them as sent (§7 X11, settled); [LOT-048](lots/LOT-048-post-form-engine.md) always sends CRLF, as a browser does.
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
- **Home** (`R01`): 20 category rows, including `apple` and `ia` (anonymous too; the legacy app hid Apple itself); the REST API lists the same 20 categories (`R57a`). See §6c LOT-021.
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

### LOT-024 — favourites page

[LOT-024](lots/LOT-024-favourites-parser.md), tests `FavoritesDifferentialTests` and `FavoritesParserTests`.

- **List body**: `GET /forum1f.php?owntopic={1|3}` logged in answers the topic list markup, `<body id="category__topics_listing__listing_topic">`, title "Vos sujets"; with no favourite on `owntopic=3` it has no row (`R11`, `P03e`), and `owntopic=1` with nothing flagged is not captured. Logged out it answers a bare `<body>` with `.hop` "Aucun sujet que vous avez lu n'est connu" (`R12`); the parser returns an empty page with that `notice`, as for LOT-022 lists (a logged-in empty `owntopic=1` may be the same page: pending capture), and the caller decides from its session.
- **Sections**: each category is a `tr.cBackHeader.fondForum1fCat` whose `th` holds a "reset flags" link (`suppressflag.php…&codehex=<token>`, a secret) then `a.cHeader` to `/forum1.php?…&cat=<id>…`; its `tr.sujet.ligne_booleen` rows follow, in the same table (`R10`).
- **Rows**: same cells as a forum list; the flag cell links to the last read position (`…&page=<n>…#t<post>`) with `flag1.gif` on `owntopic=1` and `favoris.gif` on `owntopic=3`; the checkbox cell `sujetCase10` holds `topic<N>` and `valuecat<N>`.
- **Not captured**: favourites across several categories (`R10` has one category with two topics), a row without flag link, `owntopic=1` with no flagged topic.

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

### LOT-032 — quote analysis

Source: [LOT-032](lots/LOT-032-quote-analysis.md), `MessageQuoteAnalyzer`, checked by `MessageQuoteOracleTests` and `MessageQuoteAnalyzerTests`
on the 20 LOT-003 oracle cases (358 messages) and `R33b`.

- **Quote markup**: `div.container > table.citation > tr.none > td > b.s1 > a.Topic` (`<pseudo> a écrit :`), then `<br><br>` and `<p>`; anonymous
  quotes are `table.quote` with `<b class="s1">Citation :</b>` and no link. Corpus: 126 citations and 9 anonymous quotes in 135 quotes (`R20`,
  `R26`, `R27`, `R28`), none in `RA5`.
- **Header link**: `<a href="/hfr/<cat>/<slug>-sujet_<topic>_<page>.htm#t<numreponse>" class="Topic">`: the fragment is the cited message's
  `numreponse`, whole attribute `class="Topic"` (a spoiler's `div.Topic.masque` is another element). The page number in the path differs from the quote's own page.
- **Nesting**: depth 2 only once in the corpus, an anonymous quote in an authored one (message 27 of `R28`, `R32a`, `R32b`, citing `75481731`,
  `26360875`, `26360875`); deeper and authored-in-authored nesting is not captured.
- **`oldcitation`** (`R33b`, poll page, 11 quotes): `<table class="oldcitation">`, same cells as `citation`, the header link is
  `/forum2.php?config=hfr.inc&cat=…&numreponse=0&quote_only=0&new=0&nojs=0#t<numreponse>` and an `<hr size="1" />` follows the header. Legacy renamed it to
  `citation` before reading (`ParseMessagesOperation.m:191-194`).
- **Pending capture**: nested authored quotes, quotes of a deleted or unknown account, a header whose fragment is not `t<n>`.

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


### LOT-027 — public profile

Source: [LOT-027](lots/LOT-027-profile-parser.md), `UserProfileParser`, checked in full against the LOT-005 oracles by `UserProfileOracleTests` on `R56a` (own profile as a visitor, user2) and `R56b` (another member, user3, with avatar and smileys).

- **Page**: `<body id="unique__user_page__view_user_profile">`, `h4.Ext` "Informations sur : <pseudo>", then `h6` "(Etat inconnu)" or "(En ligne dans la catégorie … du forum …)", then one `table.main`. Sections are `tr.cBackHeader` > `th[colspan=3]` ("Informations générales", "Informations relatives au forum", then "Historique des transactions" and "Informations complémentaires" which hold link rows only).
- **Field rows**: `tr.profil` with `td.profilCase2` (label ending `&nbsp;: `) and `td.profilCase3` (value). A third cell `td.profilCase4` is the side column: it holds the label "Avatar :" / "Smilies persos :" in the first row of a section, then the avatar or smiley list in a cell with a `rowspan` (6 or 5). The rows after the first four of "Informations générales" are written on one line without whitespace (`Sexe`, `Ville`, `Profession`, `Loisirs`).
- **Values**: empty = nothing in the cell (`Ville`), or `&nbsp;` alone (date of birth and quote on `R56b`), or a space and `&nbsp;`. "Profile field removed." is printed text for fields the member removed (`Sexe`, `Signature`, and `Profession`/`Loisirs` on `R56b`). Email prints `<i>Vous n'avez pas accès à cette information</i>`. Dates: arrival `dd/MM/yyyy`, last message `dd-MM-yyyy&nbsp;à&nbsp;HH:mm`; the nbsp characters are real U+00A0.
- **Avatar**: `td.profilCase4 > div.avatar_center > img src="https://forum-images.hardware.fr/images/mesdiscussions-<user id>.jpg" alt="<pseudo>"`, only for a member who has one (`R56b`); the cell is empty without (`R56a`). The user id is the one in the profile URL (`profil-910001`) and in the `id_user` of the transaction links.
- **Personal smileys**: in the `rowspan` cell of the second section, `[:pseudo] <img src=".../images/perso/pseudo.gif" alt="smilie perso" />` then, each after a `<br />`, `[:pseudo:N] <img src=".../images/perso/N/pseudo.gif" alt="pseudo:N" title="pseudo:N" />` (N = 1, 2, 3 on `R56b`). The first one has an `alt` and no `title`. A member without any has the cell with `&nbsp;` only (`R56a`).
- **Link rows** (`td.profilCase3[colspan=3][align=center]`): transactions per category "Jeux Video -> <a>Transactions (0)</a>" (`/transactions_reports.php?config=hfr.inc&cat=<5|6>&id_user=<id>`, with an `onclick` popup), "Envoyer un message privé à <pseudo>" (`/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=<pseudo>&subcatgroup=0`, `rel="nofollow"`), "Accéder à la liste de tous ses messages" (`/hfr/recherche/pseudo-<pseudo>.htm`). Identical for a visitor on both captures. "Configuration matérielle" is a value row with `<a href="/configuration.php?config=hfr.inc&pseudo=<pseudo>" class="cLink">Lien vers la configuration de cet utilisateur</a>`, present on `R56b` only.
- **Not seen**: a logged-in view of a profile, an "ajouter à la liste de contacts" row, a status other than "Membre" (see "Pending capture" in the lot spec).

### LOT-025 — small parsers

- **Search waiting page** (`R50a`, **verified**, [LOT-025](lots/LOT-025-small-parsers.md)): the `POST /search.php?config=hardwarefr.inc` answer is an HTML page with several `<meta http-equiv>` (Pragma, Cache-Control, Expires, Imagetoolbar, Refresh); the redirect is `<meta http-equiv="Refresh" content="1; url=/forum1.php?recherches=1&amp;cat=…&amp;config=hfr.inc&amp;…">`, a **relative** URL with `&amp;`, delay 1 s. The results page `R50c` carries no refresh.
- **Profile edit pages** (`R55-p1`, `R55-p3`, `R55-p5`, `R55-p5u1`, **verified**): each page holds `hash_check` **twice** (header search form `#fastsearch` and `form[name=ONSENFOU]`, `action="editprofil_validation.php?config=hfr.inc"`), and a hidden `page` field equal to the page number. Page 5 rows are `tr.profil` with `profilCase2` labels "Avatar", "Smilies persos", "Smilies favoris"; an account without avatar only shows the link `upload.php?config=hfr.inc` "Créer un avatar" (no `<img>`). With an avatar (`R55-p5u1`, user1) the cell holds `<img src="https://forum-images.hardware.fr/images/mesdiscussions-<id>.jpg" alt="" />` followed by "Modifier votre avatar" (`upload.php`) and "Effacer votre avatar" (`clearimage.php?…&codehex=<token>`); the "Smilies persos" row then lists the personal smileys as `<img src="/images/perso/[N/]name.gif" alt="name[:N]">` followed by their code. The legacy avatar regex returned another image on every other page (an icon on p1/p3, a tracking pixel on p5). Page 3 holds the text input `topicpp`.
- **Smiley search** (`R53a-c`, **verified**): the answer is a bare fragment (no `<html>`), one `<img src alt title onclick="putSmiley(this.alt,this.src)" />` per smiley, all personal smileys: code `[:name]` with image `/images/perso/name.gif`, or `[:name:N]` with image `/images/perso/N/name.gif` (the suffix `N` is the folder). Counts: one word 657, two words 1010 (OR); the same smiley can be served twice (`R53c`). No result: the 40-character text "Désolé, aucune réponse n'a été trouvée !" with no markup.
- **Smiley wiki detail** (`R54`, **verified**): `GET /wikismilies.php?config=hfr.inc&detail=%5B%3Aname%5D` (the code percent-encoded) works logged out. The entry row holds `<img src alt title>` with `<input type="hidden" name="smiley0" value="[:name]">` and `<input type="text" name="keywords0" value="word word word">` (space-separated keywords), followed by the contribution history (member profile link, date `dd-MM-yyyy à HH:mm`, keywords).

### LOT-037 — write responses

[LOT-037](lots/LOT-037-hop-response-classifier.md), tests `HopResponseParserTests` (oracles `W10`-`W20b`, `W17b`/`W17c` included).

- **Shape**: every answer to a write is HTTP 200 with a `div.hop` message, except the invalid-token reply (`W17b`, plain text, below); a refusal that offers a way back adds `<br /><br />` and either `<a href="javascript:history.back(1)" class="Topic"><b>Retour à la page précédente</b></a>` or a replay form (`<form action="/message.php…">` of hidden inputs ending in `<input type="submit" value="Retour à la page précédente">`) (`W11x`, `W13cx`, `W17a`, `W17c`, `W20a`). A success has neither.
- **Success** = `<meta http-equiv="Refresh" content="1; url=/forum…">` in the head, a `.hop` without link or input **and** an affirmative sentence containing "avec succès" (no `ne`/`pas`/`aucun`/`erreur`… word) and a refresh target that resolves to an `https` `forum.hardware.fr` URL (port absent or 443) (the only discriminator: login failure `W01`, empty lists `R08-1`/`R08-3`, the search waiting page `R50a` and login success `W01b`/`W03` also refresh with a link-less `.hop`): reply (`…#bas`), edit (`…#t<numreponse>`), create (refresh to the MP list), delete (no fragment), mark unread and flags (`W10`-`W16b`, `W18`, `W19`, `P03a`, `P03b`, `P03d`). `P03a`/`P03b` refresh to a canonical `/hfr/…/liste_sujet-1.htm` path, `W18` to `/forum1.php`.
- **Refusals**: flood, empty body and logged out are `.hop` + link/input (`W11x`, `W13cx`, `W14x`, `W17a`, `W17c`, `W20a`, `W20b`); invalid `hash_check` is **plain text without any HTML** (`W17b`, 99 bytes). A write refusal carries no refresh (`W11x`-`W20b`); other refusals do (`W01` refresh to `/`).
- **Read pages with a `.hop`**: `R12` (empty favourites) and `RA5` (message not addressed to the account) have the back link and no refresh; the empty lists `R08-1`/`R08-3` refresh to the forum list with a link-less `.hop`. None is a write answer and none classifies as success (corpus sweep test).
- Not captured: alert already sent, alert submitted, other logged-out write answers (see the lot's Pending capture).

### LOT-021 — forum list

[LOT-021](lots/LOT-021-forum-list-parser.md), tests `ForumListParserTests`.

- **Rows** (`R01`-`R03`, **verified**): the home page is `<body id="unique__home__listing_category">`; forums are `tr.cat` with `id="cat<N>"` where `<N>` is the `cat` id (all 20 agree with the §1.1 table and with the `select[name=cat]` of the list page `R07`). The category cell is the second `td`: `<b><a class="cCatTopic" href="/hfr/<Slug>/liste_sujet-1.htm">title</a></b>` then `a.Tableau` sub-forum links. The anonymous page lists Apple too.
- **Achats & Ventes** (`R01`-`R03`): its `cCatTopic` link points to `/hfr/AchatsVentes/Hardware/liste_sujet-1.htm` (its Hardware sub-forum); the category list is `/hfr/AchatsVentes/liste_sujet-1.htm`.
- **Private messages row** (`R02`, `R03`): `tr.cat` without `id`, link `forum1.php?config=hfr.inc&cat=prive&page=1…`; text "Vous avez N nouveaux messages privés" with class `cCatTopic red` (N = 10 on `R02`) or "Envoyer / lire des messages privés" without number (`R03`). Absent when logged out (`R01`).
- **Sub-forums missing from the page**: the home page lists only some sub-forums. The legacy completion table adds real forums: with it the sub-forum counts equal the REST `number_of_subcategories` (`R57a`) for Hardware 15, Photo numérique 10, Windows & Software 12, Graphisme 10, Achats & Ventes 11; Overclocking (REST 7) stays at 6 and Programmation (REST 27) reaches 14, so REST is the complete source.

### LOT-043 — login

[LOT-043](lots/LOT-043-login.md), tests `LoginResponseTests`, `LoginFlowTests` and `HFREndpointLoginTests`.

- **Answer** (`W01`, `W01b`, `W03`, **verified**): `POST /login_validation.php?config=hfr.inc` with the legacy body `pseudo, password, action=send, login=Se connecter` answers HTTP 200 either way. Success pages contain `login_redirection.php` (the `<meta http-equiv="Refresh" content="1; url=login_redirection.php?config=hfr.inc&referer_page=…">`, relative); the refusal holds "Votre mot de passe ou nom d'utilisateur n'est pas valide" and does not. The legacy substring test and the port agree on every capture.
- **Cookies** (metas of `W01`, `W01b`, `W03`, **verified**): success sets `md_user`, `md_passs`, `md_id`; the refusal sets none.
- **Profile page 5 after login** (`R55-p5` meta, **verified**): the page sets `md_user` and `md_passs` again (each twice in the answer), so the session cookies are read after it. Its `hash_check` is the token a new session posts with.


### LOT-023 — MP list and unread badge

[LOT-023](lots/LOT-023-mp-list.md), tests `PrivateMessageListParserTests`, `PrivateMessageBadgeParserTests`.
- **MP row** (`R13a`, `R13b`, `R13u1`, **verified**): own state is `sujetCase1` (`closedbp.gif` `alt="On"` title "Nouveau message. Message privé pour <others>", `closedp.gif` `alt="Off"`); the `[non lu]` marker is `<span class="red" title="Ce message n'a pas été lu par : <pseudos>">` before the title link in `sujetCase3`, the pseudos joined with `, ` (the group tooltip of `sujetCase6` with `,`). The two states are independent: `R13u1` has read threads marked `[non lu]`. `sujetCase2` holds a message icon and the ignore link `/user/ignore.php?…&auteur=<pseudo>` (`ignore0.gif`).
- **Group thread** (`R13u1`): `sujetCase6` is `<span title="<pseudos>">Interlocuteurs multiples</span>` with no profile link; one-to-one threads link `profilebdd.php?…&pseudo=`.
- **Unread count** (`R02`, `R03`, `P03f`, `R08-2`, **verified**): the home page announces it in the `tr.cat` row linking `cat=prive` (`a.cCatTopic.red` "Vous avez 10 nouveaux messages privés"; "Envoyer / lire des messages privés" with no number and no `red` class when none is unread), logged-in forum lists in the middle cell of the 3-cell `table.none` ("Vous avez 1 nouveau message privé" in `a.red`, else "Messages privés"). The MP list, anonymous pages and the topic page have neither.
### LOT-047 — MP unread poll
[LOT-047](lots/LOT-047-mp-unread-poll.md), tests `MPUnreadPollTests`.
- **Poll page** (`R01`, `R02`, `R03`, **verified**): `GET /` carries the unread count in the `cat=prive` row (see LOT-023), 200 for anonymous and logged-in visitors, served at `https://forum.hardware.fr/` (no redirect, meta `final_url`). The poll reads only that page; no topic page, so no flag is marked read (§7, E25). The logged-in answer sets `md_user` and `md_passs` (each twice, R02/R03 metas), so the poll sends from a probe jar and does not write them back.
- **Pending capture:** the home page answered to a logged-in session with expired cookies; until captured a poll reads it as `nil` (no information) whichever form HFR serves.
### LOT-036 — write forms
Source: [LOT-036](lots/LOT-036-hop-form-parser.md), `HopFormParser`, checked by `HopFormOracleTests` against the LOT-004 oracles and by `HopFormParserTests` on `R40a`, `R40b`, `R41a`, `R41b`, `R42`, `R43a`–`R43c`, `R44`, `R45a`, `R45b`, `R46`, `R47a`–`R47c`, `R47u1`.
- **Form**: `<form name="hop" id="hop" action=… method="post">` holds the inputs, the selects and the `<textarea id="content_form" name="content_form">`. Reply, quote and MP-reply forms post to `/bddpost.php?config=hfr.inc`; the **edit forms** post to `/bdd.php?config=hfr.inc`: private messages (`R43a`–`R44`) and public topics, later post (`R62a`, `R62b`) and first post (`R63b`). The public reply composer (`R61b`, cat 13) is the `R40a` form, field for field. The `action` is always read from the page.
- **Reply form** (`R40a`, logged in, 43 inputs): hidden `hash_check, subcat, parents, post, stickold, new, cat, numreponse, numrep, page, verifrequet (1100), p, sondage, sond, cache, owntopic, config, sujet`; text `pseudo` (the account's), `password` (hidden row), 16 `MsgIcon` radios (the first `checked`), `search_smilies`, hidden `ColorUsedMem` and `wysiwyg`, the `submit` input ("Valider votre message") and three checkboxes `signature`, `smiley`, `emaill` (value `1`, unchecked). No `<select>`.
- **Anonymous composer** (`R40b`): the same form, with an **empty** `hash_check` and an empty `pseudo`. `hash_check` also sits in the header search form of every page, so its presence says nothing about the session.
- **Edit form** (`R43a`–`R44`; public later post `R62a`, `R62b`: the same fields as `R43b`, `stickold` `0`, hidden `sujet` holding the topic title, delete label "Effacer ce message"; public **first post** `R63b`: visible `sujet` (`maxlength` 70), a `subcat` select (12 options, the topic's one `selected`), `toread1`..`toread5`, the poll block `have_sondage` (unchecked), `textreponse0`..`textreponse10`, `allowvisitor`, a `max_votes` select with no `selected` option, `jour`, `mois`, `annee`, `heure`, `minute`, the boxes as stored (`signature` checked here) and delete label "Effacer l'intégralité du sujet", as on `R43a`): `stickold` empty, `pseudo` and `sujet`; `sujet` is a visible text input on the first post of a conversation and hidden on a later one; a `delete` checkbox (value `1`, unchecked) except on `R44` (another account's message, served without it); the text is the stored one, with `\r\n` as sent (`R43a`, bytes) or `\n` (`R43b`).
- **Quote prefill** (`R41a`, `R41b`, `R47a`): `[quotemsg=<numreponse>,<ref>,<author id>]<text>[/quotemsg]` plus a trailing newline, line breaks `\r\n` in the HTML bytes; `&` of cited links is written `&amp;` and decoded by the parser. A multi-quote cookie gives one block per cited message (`R42`, `R47c`: two).
- **New topic** (`R45a`): visible `sujet`, `toread1`..`toread5`, `<select name="subcat">` of 16 options, the first `value=""` "Aucune", none `selected`. **New MP** (`R45b`): visible `dest` (prefilled) and `sujet`, no select. **MP reply** (`R47b`, `R47u1`): hidden `sujet`, no `dest`, no `newdest`.
- **Leading newline**: verified, every captured prefill starts right after the `<textarea>` tag, so HFR adds no newline of its own. **Pending capture**: a stored text that begins with `\n` (a browser's HTML parser would drop one newline after the tag; the parser keeps it, no capture has one).
- **Favourite smileys** (`R47u1`, user1): `#dynamic_smilies` holds `<img src=".../images/perso/[N/]<name>.gif" alt="[:name[:N]]" title=… onclick="putSmiley(this.alt,this.src)">`, 8 of them; empty or absent for the other accounts (`R40a`, `R47b`).
- **Moderator alert form** (`R46`): `<form method="post" action="modo.php?cat=13&amp;ref=1&amp;post=…&amp;numreponse=…&amp;page=1&amp;config=hfr.inc">` (relative to `/user/`, not a `hop` form) with `hash_check`, `referer_page` (empty), the `raison` textarea (no id) and `Submit`; the page also has the `#fastsearch` form (`action="/forum1.php"`, its own `hash_check`).
### LOT-048 — posting
[LOT-048](lots/LOT-048-post-form-engine.md), tests `PostingCaptureTests`, `PostingBodyOracleTests`, `PostingRefusalTests`, `PostingInputTests` and `HopFormLayoutTests`.
- **Body order** (`W10`-`W19` `request_fields`, **verified**): every captured write sends the `hop` form's controls in document order, `content_form` in place between `ColorUsedMem` and `wysiwyg`, the submit input, then the checked boxes; the new-topic `subcat` select sits between `toread5` and the tone radios (`R45a`). The engine rebuilds `W13b`'s body byte for byte from `R47b`, and the other captured bodies once legacy's `"0"` boxes are dropped and line breaks written CRLF.
- **Fields sent** (`R40a`-`R47u1`, LOT-004 oracle, **verified**): the form's own `hash_check`, `pseudo` and `verifrequet=1100`, every hidden input, the checked tone radio, `submit=Valider votre message`; the same names and values as legacy apart from unchecked boxes.
- **Composer shapes** (`R40a`-`R47u1`, **verified**): only edit forms carry a non-empty `numreponse`; new-thread forms show `sujet` (`R45a`), with `dest` for a private one (`R45b`); the first post's edit form shows `sujet` and labels its box "Effacer l'intégralité du sujet" (`R43a`), a later post hides `sujet` and says "Effacer ce message" (`R43b`).
- **Per-write sentences** (`W10`, `W11`, `W15`, `W16a`, `W19`, **verified** on private messages): see §7 E15; `W18` (mark unread) is also a confirmation, of another action. Public-topic answers are not captured (lot's Pending capture).
### LOT-034 — message content
Source: [LOT-034](lots/LOT-034-content-normalization.md), `MessageContentNormalizer`, checked by `MessageContentOracleTests`,
`MessageContentNormalizerTests` and `MessageContentSanitizationTests` on the 20 LOT-003 oracle cases (358 messages).
- **Content element**: `div#para<numreponse>` holds the message HTML, then HFR's layout trailer `<div style="clear: both;"> </div>`
  (closed by a stray `</p>`), then the LOT-030 edit trailer `<div class="edited">…</div>` when the message was edited or quoted, then
  `<br /><span class="signature">…</span>` when the author has one. Measured on the 358 messages: 119 clear only, 92 clear > edited,
  80 clear > signature, 45 clear > edited > signature, 22 none of them (private threads `RA1`–`RU2`); never another order
  (`R20` message 1 `para2666682`, 0 `para2666649`, 2 `para2666695`, `para3182834`). 125 messages carry a signature.
- **Smileys**: `<img src alt title>` on `forum-images.hardware.fr`, standard ones under `/icones/` (`/icones/smilies/ange.gif` with
  `alt=":ange:"`, `/icones/redface.gif` with `alt=":o"`, `/icones/biggrin.gif` with `alt=":d" title=":D"`), personal ones under
  `/images/perso/` with `alt="[:<code>]"` (`R20`, `R26`, `R27`); 103 messages hold a personal smiley. Every smiley of the corpus is `https`.
- **Images**: `<img src alt title onload="md_verif_size(this,'Cliquez pour agrandir','2','250')" style="margin: 5px">`, `alt` and `title`
  equal to the URL, `style` sometimes with `width`/`height`; bare (`R20`, `R28`) or inside `<a rel="nofollow" href target="_blank"
  class="cLink">` (16 pairs on `R28`); 36 messages hold an image. Image hosts may stay `http`.
- **Links**: external `<a rel="nofollow" href="…" target="_blank" class="cLink">`; forum links written `http://forum.hardware.fr/hfr/…`
  (`R20`); quote headers `<a href="/hfr/<cat>/<slug>-sujet_<post>_<page>.htm#t<numreponse>" class="Topic">` (relative). One `R20` link
  has raw spaces in its host (`http://G3Ferrari / Optima`): not a URL.
- **Quotes**: `<div class="container"><table class="citation"><tr class="none"><td><b class="s1"><a class="Topic">…a écrit :</a></b>
  <br /><br /><p>…</p></td></tr></table></div>` (126 on the corpus), `table.quote` with `<b class="s1">Citation :</b>` for anonymous
  citations (9); `oldcitation` never seen.
- **Spoilers** (`R27`, `R28`, 4 blocks): `<table class="spoiler" onclick="javascript:swap_spoiler_states(this)" style="cursor:pointer;">`
  with `<b class="s1Topic">Spoiler :</b><br /><br /><div class="Topic masque">…</div>`.
- **Code** (`R27b`): `<table class="code">` (or `fixed`) with `<b class="s1" style="font-family: Verdana, Helvetica, Arial, Sans-serif;">
  Code :</b><br /><ol id="code1" class="olcode">`, one `<li>` per line (`<li></li>` for blank lines), `<span style="color:blue">`
  keywords, `<span style="color:green"><i>` comments ending with a raw CR, entities `&#034;`, `&lt;`, `&nbsp;` for indentation.
- **Formatting seen**: `strong`, `em`, `i`, `strike`, `span.u`, `span[style="color:#0055aa"]` (and `#e2001c`), `ul`/`li`, `br`,
  `&nbsp;` lines; no `script`, `iframe`, `on*` attribute other than the spoiler's `onclick` and the images' `onload`, no `id` other
  than `code<N>`.
- **Not in the corpus**: `hfr-rehost.net` or `reho.st` URLs, the `---------------` separator, `oldcitation`.

### LOT-056 — image hosts

[LOT-056](lots/LOT-056-image-hosts.md), tests `RehostClientTests`, `RehostClientLoopbackTests`, `MultipartBodyTests` and `ImageHostTableTests`. No capture backs
the upload, answer, `Referer` and thumbnail facts below: they are the **legacy code** (`ReplyService.swift:1958-2093`, `MessagesView.swift:5748-5762` @ `2440d79`) reproduced by tests, not **verified** against HFR or the hosts. Only the plain-HTTP host list comes from captures (as read by LOT-071).

- **Upload** (**code**): `POST <base>/api/1/upload/?key=<key>`, `multipart/form-data` with `imageCaption` (`Some Caption`) then `source` (`image/jpeg`, `snapshot_<random>.jpg`), no cookie, 60 s. The body is reproduced byte for byte (`matchesTheLegacyUploadLayout`).
- **Answer** (**code**): JSON with `status_code`, `error.message` or `success.message`, `image.url`, `image.width`, `image.height`, `image.medium.url`, `image.thumb.url`; numbers may be strings. No real answer is captured (pending capture).
- **`reho.st` `Referer`** (**code**, E26 still unsettled): legacy sends `Referer: https://forum.hardware.fr` (no trailing slash) for `reho.st` and its subdomains only; the table keeps that value as data until the cookie-less capture settles it.
- **Thumbnails** (**code**): `img3.super-h.fr/images/<name>.th.<ext>` loses `.th.`; `reho.st/thumb/` becomes `reho.st/`; `rehost.diberie.com/Picture/Get/t/` becomes `…/f/`.
- **Plain-HTTP hosts** (captures `R20`, `R21`, `R22a`, via LOT-071): every reference to `hostingpics.net`, `casimages.com`, `free.fr`, `photorapide.com`, `camif.fr` and `hn.org` images is `http://`; whether `https` works is not measured (pending capture).

### LOT-051 — flags and favourites

[LOT-051](lots/LOT-051-flag-writes.md), tests `FlagLinkWriteTests`, `FlagLinkValidationTests` and `FavoriteListAndReadTests`.

- **Flag links** (`R21`, `P03a`, `P03d`, **verified**): every message of a logged-in topic page carries `/user/addflag.php?config=hfr.inc&cat=<cat>&post=<post>&numreponse=<n>&page=<p>&ref=<rank>&p=1&sondage=0&owntopic=0&subcat=<sub>` (40 on `R21`, the first one is `P03a`'s request); the page has one `/user/delflag.php?config=hfr.inc&cat=<cat>&subcat=<sub>&post=<post>&page=<p>&p=1&sondage=0&owntopic=<n>&new=0` (`owntopic=0` on `R21`, `1` on `R33b`). No token in either link.
- **Flag answers** (`P03a`, `P03b`, `P03d`, **verified**): 200 in place, no redirect, no cookie set; a link-less `.hop` "Favori positionné avec succès" (again on a second `addflag`: idempotent) or "Drapeau effacé avec succès", and a 1 s refresh (sub-forum list after `addflag`, `forum1.php…&owntopic=3` of the category after `delflag`).
- **Flag action form `form1`** (**verified**), the same shape on the favourites lists and on a forum's flag list: on `forum1f.php` (`P03c` `owntopic=3`, `R10` `owntopic=1`) it posts to `/modo/manageaction.php?config=hfr.inc&cat=0&type_page=forum1f&moderation=0`, on `forum1.php` (`R08-2`, `owntopic=2`) to `/modo/manageaction.php?config=hfr.inc&cat=<cat>&type_page=forum1&moderation=0`; per row a checkbox `topic<i>` (value = topic number) with hidden `valuecat<i>` and `valueforum<i>=hardwarefr`, then `hash_check`, the end marker `topic<N>=-1`, `topic_statusno<N>=-1` with `N` = number of rows, the `action_reaction` select (only option `message_forum_delflags`), hidden `owntopic` and `type_page`. Legacy's body (`FavoritesTableViewController.m:1846-1858`) always writes the marker at index 1.
- **Browser body of `form1`** (`P03h`, `P03l`, **verified**, 2026-10-28): in DOM order, an unchecked row sends its hidden `valuecat<i>`/`valueforum<i>` but not its checkbox, and the marker stays at index `N`. Two rows, the first checked (`P03g` → `P03h`): `hash_check, topic0=<post>, valuecat0, valueforum0, valuecat1, valueforum1, hash_check, topic2=-1, topic_statusno2=-1, action_reaction=message_forum_delflags, owntopic=3, type_page=forum1f`. Only the checked topic left the list (`P03i`). Three rows, all checked (`P03k` → `P03l`): all three left the list.
- **`manageaction.php` delflags answer** (`P03h`, `P03j`, `P03l`, **verified**): 200 in place, no redirect, no cookie set, a link-less `.hop` and a 1 s refresh. The sentence depends on the body. With the browser body (`owntopic=3`), one row or several: "Favoris supprimés avec succès", refresh `/forum1f.php?config=hfr.inc&owntopic=3&new=0&nojs=0`. With legacy's body (no `owntopic`, marker at index 1, one topic, sent when the list had one row, `P03i` → `P03j`): "Drapeaux effacés avec succès", refresh `/`. The topic was removed in both cases (list read afterwards). These bodies differ in `owntopic` and in the marker index, and the capture does not show which of the two selects the sentence. After these removals the topics were in neither `forum1f.php?owntopic=2` nor `owntopic=3`, so their read flags were gone too (lists read, not published).
- **`delflag.php` answers by `owntopic`** (`P03d`, `P03n`, `P03p`, **verified**): always "Drapeau effacé avec succès", 200 in place, no cookie set. `owntopic` chooses the refresh. With `0` (the header link of a logged-in topic page, `P03m`), the refresh goes to the sub-forum list `/hfr/<cat>/<sub>/liste_sujet-1.htm`. With `1` (the same link on a topic page opened from a `forum1f.php?owntopic=1` row; HFR copies the page's `owntopic` into it), it goes to `/forum1.php?config=hfr.inc&cat=<cat>&page=1&subcat=<sub>&sondage=0&owntopic=1&trash=0&trash_post=0&moderation=0&new=0&nojs=0&subcatgroup=0`. With `3` (`P03d`), it goes to the list of the category with `owntopic=3`. After `P03n`, the topic was in neither the `owntopic=2` list nor the `owntopic=3` list.
- **Repeated `delflag`** (`P03o`, **verified**): the same request on a topic with no flag left answers the same bytes as `P03n`. It is not a refusal, so the sentence does not prove that a flag existed.
- **`addflag.php` logged out** (`P03q`, **verified**): a GET without any cookie answers the same bytes as the logged-in success `P03a`, with "Favori positionné avec succès" and the same refresh. No cookie is set, and there is no account to store it in (inferred, not observed). **The `addflag` sentence therefore does not prove the write**: an expired session gets the success page.
- **Header flag link on a topic page** (`R21`, `P03m`, **verified**): the topic page has one `a.cHeader` link to `/user/delflag.php?…`. When the account only read the topic, its image is `flagn0.gif` with alt and title "Effacer le drapeau associé" (`R21`). When the topic is a favourite, it is `favorisn.gif` with alt and title "Ne plus considérer ce sujet comme favori et repasser en mode &#034;drapeau&#034;" (`P03m`). Despite that title, sending the link removed the read flag as well (see above).

### LOT-031 — message action links

Source: [LOT-031](lots/LOT-031-message-actions.md), `MessageActionsParser`, checked by `MessageActionsOracleTests` against the legacy actions dictionary of the 20 LOT-003 topic oracles (358 messages) and by `MessageActionsParserTests`.

- **Where**: every per-message action is inside the block's `div.toolbar`: `div.left` after the date holds profile, `viewbbcode`, edit, quick edit (`edit_in(…)`), quote, multi-quote, MP, contact and favourite links; `div.right` holds the alert link (logged in, public topics). Page-level links sit outside the blocks: the header's `/user/delflag.php?…` (`a.cHeader`, logged in) and a topic-level `/user/modo.php?cat=…&ref=0&post=…` (`R21`, `R32b`).
- **Quote**: `<span class="md_noclass_cryptlink<hex>"><img … alt="answer" /></span>`, decoding to `/message.php?config=hfr.inc&cat=<cat>&post=<post>&numrep=<n>&ref=<i>&page=<p>&p=1&subcat=<sub>&sondage=0&owntopic=0&new=0#formulaire`; on every block, logged out too (`R20`).
- **Edit**: `<span class="md_noclass_cryptlink<hex>"><img … alt="edit" /></span>`, decoding, in private conversations (the only edit links of the corpus; the public-topic shape is pending capture), to `/message.php?config=hfr.inc&cat=prive&post=<post>&numreponse=<n>&page=1&p=1&subcat=0&sondage=0&owntopic=0#formulaire`; only on the viewer's own posts (`RA1`–`RA4`, `RU2` message 4; none for the recipient on the other account's posts, `RU1`).
- **Multi-quote**: `<a rel="nofollow" onclick="quoter('hardwarefr','<cat>',<post>,<numreponse>); return false;" href="/message.php?…&numrep=<n>…">` holding `img alt="answer +"` and `alt="answer -"`; logged in only, `<cat>` is `prive` in conversations; its `numreponse` is the block's own on every message.
- **Profile**: `<a href="/hfr/profil-<id>.htm" target="_blank" rel="nofollow"><img … alt="profil" /></a>`; absent on some blocks (`R22a`: 3 posts of one member, quote link only).
- **MP**: `<a rel="nofollow" href="/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=<pseudo>&subcatgroup=0"><img … alt="MP" /></a>`, logged in, on other members' posts only (`R21`, `RA4` message 4, `RU1`, `RU2`).
- **Favourite**: `<a href="/user/addflag.php?config=hfr.inc&cat=<cat>&post=<post>&numreponse=<n>&page=<p>&ref=<i>&p=1&sondage=0&owntopic=0&subcat=<sub>">` (`img alt="Favoris"`), logged in on public topics only (`R21`, `R32b`).
- **Alert**: `<a href="/user/modo.php?config=hfr.inc&cat=<cat>&post=<post>&numreponse=<n>&page=<p>&ref=<i>" title="Prévenir les modérateurs en cas d'abus" target="_blank">`, logged in on public topics only.
- **Not read** (no legacy use): `viewbbcode.php`, `edit_in(…)` quick edit, `/user/contactlist.php?adduser=<id>`.
- **Pending capture**: the viewer's own post on a public topic (edit link shape and which other links remain), a quote or edit link printed in clear instead of obfuscated.

### LOT-044 — session refresh

[LOT-044](lots/LOT-044-session-health.md), asserted by the capture-backed flow tests `SessionRefreshFlowTests` (the pages are read by `ProfileEditPageParser` and `HopResponseParser`, already verified above).

- **Profile page 1 logged in** (`R55-p1`, **verified**): `GET /user/editprofil.php?config=hfr.inc&page=1` answers 200 with a non-empty `hash_check`, no `.hop`, and sets `md_user` and `md_passs` (each name twice in the meta; attributes not recorded). A refresh is confirmed only by that shape with the same `md_user` afterwards.
- **Token echo** (`W17c`, **verified**): a `.hop` refusal can hold a non-empty `hash_check` in its replay form although the POST carried no cookies, so a non-empty token is evidence of a logged-in session only on the expected profile-page GET, after its URL and `.hop` checks.
- Not captured: page 1 with stale cookies, `md_user=deleted` sent by HFR, attributes of the doubled `Set-Cookie` (see the lot's Pending capture).

### LOT-095 — link shapes

[LOT-095](lots/LOT-095-link-router.md), tests `HFRLinkRouteTests`, `HFRLinkRouteCorpusTests`, `HFRLinkRouteOracleTests`.

- **Shapes in the corpus** (all captures, every `href` of a forum page): topic `/hfr/<cat>[/<sub>]/<slug>-sujet_<post>_<page>.htm` with `#t<numreponse>` or `#bas`, absolute `http://` and `https://` as well as relative; `forum2.php?config=hfr.inc&cat&[subcat&]post&page&p&sondage&owntopic&trash&trash_post&print&numreponse&quote_only&new&nojs`; topic lists `/hfr/<cat>[/<sub>]/liste_sujet-<page>.htm` and `forum1.php?config=hfr.inc&cat&page&subcat&sondage&owntopic&trash&trash_post&moderation&new&nojs&subcatgroup`; `forum1f.php?config=hfr.inc&owntopic=<0..3>&new&nojs`; `/hfr/profil-<id>.htm`; `search.php?config=hardwarefr.inc&cat=&subcat=0`; `/hfr/<forum>/nouveau_sujet.htm`, `nouveau_sondage.htm`; `/hfr/recherche/pseudo-<pseudo>.htm`; the old `forum2.php3?post=<n>&cat=<n>` (`R06`, meaning unknown).
- **`numreponse` overrides `page`** (`R25`, and 50 links of the corpus): the topic list rows and the quote-only links carry `forum2.php?…&page=1&…&numreponse=<message>` with no fragment; `R25` shows the server answering that shape with a 301 to the page that holds the message. The `page=` of such a link is not the message's page. Topic page links (pagers, `numreponse=0`) and permalinks (`#t<message>` on a canonical URL) carry the real page.
- **Views of a topic** (`R21`): the toolbar links `forum2.php?…&print=1&numreponse=0…` (print view) and `…&numreponse=<m>&quote_only=1…` (single message) are not the topic page; plain topic links have `print=0`, `quote_only=0` or empty values.
- **Search results pager** (`R50b`): `forum1.php?…&page=2&…&recherches=1&…&search=<TERMS>&…&searchall=0&cat=13…` (first results page: no `page`, parameters `recherches=1&cat&orderSearch&config&pseud&search&…`). It repeats `cat` and `trash`; it is a results page, not the topic list of `cat`.
- **Favourites page filters** (`R11`): the page links `forum1f.php?config=hfr.inc&owntopic=<n>&new=<0|1>&nojs=0` with `owntopic` 0 and 2 beside the documented 1 and 3; the pages behind 0 and 2 are not captured.
- **Slug segment = forum** (LOT-003 oracle, 20 topic pages): the `<cat>` segment of every canonical permalink maps through `ForumCatalogue` to the same `cat` the message's own quote link carries.
- **Pending capture**: the AASA file of the site (#127), forums missing from the catalogue (#125), `profilebdd.php?pseudo=`'s redirect target, the pages behind `forum1f.php?owntopic=0|2` and `forum2.php3`.

## 7. Reported by redface2, to verify with our fixtures

Facts from the redface2 project documentation, rewritten here; each becomes *verified* only through a LOT-001 fixture. Source: [docs/research/redface2-comparison.md](research/redface2-comparison.md) §4 (ids X/E below).

| Topic | Reported fact | Id | Result (LOT-001, 2026-10-26) |
|---|---|---|---|
| Write constant | Every `bddpost.php` / `bdd.php` POST carries `verifrequet=1100`; the poll vote does not | X4 | **Settled**: hidden input of every write form (`R40a`, `R43a`, `R45b`, `R47b`) and present in every accepted POST body (`W10`-`W19`); not in the vote form (`R32a`) |
| Write markers | Distinct success sentences for reply, edit, create and delete; specific texts for empty body, invalid token, flood | E15 | **Settled** (MP, `W10`-`W19`): reply "Votre réponse a été postée avec succès !" (refresh `…#bas`), edit "Votre message a été édité avec succès !" (`…#t<n>`), create "Votre message a été posté avec succès !", delete "Message effacé avec succès !" (also for a post already deleted, `W16b`), empty body "Vous devez remplir tous les champs avant de poster ce message", bad token 99-byte plain text "Une erreur est survenue lors de l'envoi des données. Essayez de vider le cache de votre navigateur", flood "Afin de prevenir les tentatives de flood, vous ne pouvez poster plus de 3 réponses consécutives dans un intervalle de 10 minutes", logged out "Désolé, vous devez être enregistré pour poster sur le forum"; new-topic flood "… plus de 1 nouveaux sujets consécutifs dans un intervalle de 60 minutes" (`W11x`). **Public topic** (cat 13, `W30`–`W33`): the same reply, edit, delete and empty-body sentences; refreshes: reply → `/hfr/<cat>/<sub>/<slug>-sujet_<post>_1.htm#bas` (page **1**, while the post landed on the last page, `R61d`), edit → `…-sujet_<post>_<page>.htm#t<numreponse>` (first post too, `W34`, `W35`), delete → `/hfr/<cat>/<sub>/sujet_<post>_<page>.htm` (no slug, no anchor). Public new-topic answer not captured |
| First post | Owner can delete it, which deletes the topic (then 404) | X1 | **MP variant settled, differs**: the owner's first-post edit form offers "Effacer l'intégralité du sujet" (`R43a`); the POST answers "Message effacé avec succès !" (`W19`), after which the owner gets 200 + "Ce message ne vous est pas destiné, désolé" (`RA5`, not 404), but the **recipient keeps the whole thread** (`R13u1b`, `RU2`). Public topic: deleting a later post answers the same sentence and the post is gone (`W32`, `R61e`); deleting a public first post was not tested (not authorised) |
| Create topic | Success redirects to the category list; no topic id returned | E14 | Unsettled for topics. MP creation: success refreshes to the MP list, no thread id (`W10`) |
| Login | Success = `Set-Cookie: md_user` equal to the pseudo; failure and login-flood texts; cookie set may include `md_pass`, `md_forum` | X5, X12 | **Settled in part**: `md_user` = pseudo on success, exact failure text (`W01`, `W03`). **Contradicts** the cookie set: `md_user`, `md_passs`, `md_id`, no `md_pass`/`md_forum`. Login-flood text not observed |
| CRLF | No `\n` → `\r\n` conversion in rf2; whether HFR needs it is open | X11 | **Settled**: bare LF and CRLF are both accepted and stored as sent (`R43a`, `R43b`); CRLF renders as `\r<br />` (`RA2`); server prefills use CRLF (`R41a`) |
| Favourite removal | Single removal by `GET /user/delflag.php?…`; success text "Drapeau effacé…" | X6 | **Settled for a favourite**: `GET /user/delflag.php?…&owntopic=3` answers "Drapeau effacé avec succès" (`P03d`) and also removed the topic's read flag (`P03f`). The same sentence comes back for `owntopic=0`, for `owntopic=1` and for a repeated call (`P03n`, `P03p`, `P03o`); `owntopic` only sets the refresh. The list POST answers "Favoris supprimés avec succès" or "Drapeaux effacés avec succès" (`P03h`, `P03j`, LOT-051 subsection) |
| Global search | The POST answers a waiting page; results are a cookie-less `GET /forum1.php?recherches=1&…`; four result shapes | X7, E12 | **Settled in part**: the POST answers "Votre recherche est en cours…" with a refresh to `GET /forum1.php?recherches=1&…&config=hfr.inc` (`R50a`); that GET works without cookies, 50 rows per page despite `resSearch=200`, with `post_cat_list` (`R50b`); no result = `.hop` "Désolé, aucune réponse n'a été trouvée !" (`R50c`). Pivot shapes not captured |
| Intra-topic search | `transsearch.php` needs `hash_check`; `dep=0` + `firstnum` only on a fresh search | E28 | **Settled in part**: the page form sends `hash_check, post, cat, config, p, sondage, owntopic, word, spseudo, [filter], dep=0, firstnum`; a match answers **302** `Location: /forum2.php?…&word=<UPPERCASED>&spseudo=&currentnum=<match>#t<match>` (`R52a`), no match 200 + `.hop` "Désolé aucune réponse n'a été trouvée" (`R52b`). Stepping not tested |
| Multi-quote | Can be done without the cookie: fetch one quote form per post, concatenate prefills, submit once | X10 | Partly: the cookie route works server-side on topics (`R42`) and MPs (`R47c`, cookie `quoteshardwarefr-prive-<post>`; posted in `W14`); the cookie-less route was not tested |
| MPStorage read | JSON read from the first post's edit form `content_form`, not the rendered text; real documents hold many namespaces from other clients; 64 KiB safety cap; refuse to write non-BMP characters | X8, E23, E24 | **Settled in part** (2026-10-27): the legacy read URL `forum2.php?config=hfr.inc&cat=prive&post=<post>&numreponse=0&page=1&p=1&subcat=0&sondage=0&owntopic=0` answers 200 without redirect; the first post `div#para<numreponse>` holds the document in a `p` (`"` written `&#034;`, HFR's `div` clear inside the `p`) (`R60a`); its edit form (`message.php?…&numreponse=<first post>`, toolbar `edit-in` link) is a `hop` form to `/bdd.php?config=hfr.inc` with `sujet` = `MP_NAME` and the document in `content_form` (`R60b`). On this document the rendered text, entity-decoded, equals `content_form` byte for byte; the legacy page parse reads it (`LOT-004/R60a.oracle.json`). Not observed: user1's live document is the empty structure the legacy app creates (`sourceName` `iOS` everywhere, 568 bytes), so other clients' namespaces, the 64 KiB cap and non-BMP characters stay unverified, and whether rendering alters other content (smiley codes, URLs, BBCode-like text) is open: read `content_form` |
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

## 7b. Reported by Bybifok, to verify with our fixtures

Facts and open questions found by **Bybifok** ([`moust4ki`](https://github.com/moust4ki)) in the legacy fixes of [ezzz/HFRnow#3](https://github.com/ezzz/HFRnow/pull/3) and the prototype [moust4ki/ultra-hfr](https://github.com/moust4ki/ultra-hfr) (reviewed 2026-10-26). Each becomes *verified* only through a captured fixture; the entry that settles it credits Bybifok.

| Topic | Reported fact | Id | Status (2026-10-27) |
|---|---|---|---|
| List pager | The forum-list pager is a window (`1 … 10 20 … 100 200 … 500`): its last link is a lower bound, not the page count; the exact page count of a topic is in its row (`sujetCase4`) | B1 | **Shape settled** (§6c LOT-022, `R04`, `R05a`, `R05b`); "lower bound" follows from it; `sujetCase4` count to assert in a test |
| List paging | Paging goes through the path `liste_sujet-<n>.htm`; `?page=` on `liste_sujet-1.htm` is ignored | B2 | Unsettled. Logged out, `forum1.php?…&page=<n>` answers 301 to `liste_sujet-<n>.htm` (R2) |
| Search | Words shorter than 4 letters are not indexed | B3 | Unsettled |
| AQ RSS | Titles and descriptions keep HTML entities (`&quot;`, `&#039;`) | B4 | Unsettled (LOT-028, pending AQ capture) |
| Search URLs | Intra-topic results are a plain GET `forum2.php?…&word=<UPPERCASED>&spseudo=&currentnum=<match>#t<match>`; a member's posts at `/hfr/recherche/pseudo-<name>.htm` | B5 | **Results URL settled** (§7 E28, `R52a`); member-posts URL unsettled |
| Flags page | "Mes drapeaux" lists only followed topics with news and carries a `suppressflag.php` link, never to call without an explicit user action | B6 | Unsettled; cross-check with `R10` |
| Row icons | `closedb_new` does not say whether a followed topic is read; icon paths depend on the account's theme (`images_forum/1` vs `images/defaut`): match on `alt` or file name | B7 | **First part consistent** (§6c LOT-022: `closedb_new.gif` on every anonymous row); theme-dependent paths unsettled |
| MP list | `[non lu]` means the correspondent has not read it | B8 | **Settled** (§6b, `R13a`, `R13b`, `R13u1`) |
| Old links | `forum2.php3` links still work; "Achats & Ventes" points to its first sub-forum | B9 | **Second part settled** (§6c LOT-021, `R01`-`R03`); `forum2.php3` unsettled |
| Home | 20 category rows | B10 | **Settled** (§6b, `R01`, `R57a`) |

Feasibility questions raised by the same proposals, to answer with evidence before a feature depends on them:

| Question | Feature | Id | Status (2026-10-27) |
|---|---|---|---|
| Is there any server signal that someone quoted me (`quote_only=1`)? | "On t'a cité" | B11 | Not captured (§7 E2) |
| Can a guest upload on `reho.st` be deleted by its uploader? | Upload history | B12 | No delete API evidenced |
| Does HFR accept emoji inside the Basic Multilingual Plane? | Emoji refusal with smiley suggestion | B13 | Non-BMP truncates (§6, `W12`); BMP untested |
| Can continuous scrolling prefetch pages without moving flags? | Continuous scrolling | B14 | Principle settled: prefetch without session, reload the current page with it (§7 E25) |
| What check interval stays polite for a background "Vérifier HFR" Shortcuts intent, without ever fetching a topic page? | Shortcuts check | B15 | Unsettled |

## 8. Third-party services

Inventory, data sent to each host, owners, first-use notices and the decisions on image loading (D-071-1), video players (D-071-2) and AQ requests (D-071-3): [LOT-071](lots/LOT-071-third-party-services.md). This table keeps the wire facts.

| Service | Use | Notes | Source |
|---|---|---|---|
| `aq.super-h.fr` | "Alerte Qualitay" community reports | GET `/api/getAlertesByTopic.php?topic_id=`; POST `/api/addAlerte.php` (fixed field order, response `"1"` = success); RSS `/rss.php` (badge, "new since" `last_check_aq`, category 25 hidden unless pseudo `applereview`); unauthenticated, sends pseudo | D §2.7, `AQPlusView.swift:29-87` (decisions Q-4, Q-7) |
| Image rehost (Chevereto) | Image upload for posts | API key required (ADR 0007) | D §3.2 |
| Giphy | GIF picker | API key required (ADR 0007) | E §6 |
| Video players | YouTube, Vimeo, Streamable links shown as `<iframe>` players (`embedded_videos`) | Dailymotion, Coub, Twitch commented out in legacy; removed from the live app by `d645f52`; SwiftHFR shows a placeholder, player on tap (LOT-071 D-071-2) | `ParseMessagesOperation.m:238-300`, `LinkItem.m:149-158` |
