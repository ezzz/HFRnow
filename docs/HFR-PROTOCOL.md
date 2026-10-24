# HFR protocol reference

Everything we know about how forum.hardware.fr works: URLs, parameters, forms, cookies, tokens, HTML signals.
**Every entry cites its source**: a legacy `file:line` (repo <https://github.com/francoisgn/hfrnow> @ `2440d79`) and/or an audit section.
Status per fact: **code** = read from legacy code only · **verified** = confirmed by a committed fixture. Until Phase 2 delivers fixtures, everything here is *code*.

Host: `https://forum.hardware.fr` (`Classes/k.m:37-40`). Forum config `config=hfr.inc` on all pages except global search (`config=hardwarefr.inc`).

## 1. Read endpoints

| Id | Purpose | Method | URL | Notes | Source |
|---|---|---|---|---|---|
| R1 | Home: forum list, `hash_check`, MP count | GET | `/` | | `ObjCForumsLoaderWorker.m:20`, `ObjCForumsParser.m:41-42` · audit A §3.1 E1 |
| R2 | Topic list of a forum | GET | `/forum1.php?config=hfr.inc&cat={cat}&page={n}&subcat=&owntopic={0..3}` | `owntopic`: 0 all, 1 tracked (flag1), 2 read (flag0), 3 favourites | `ObjCForumTopicsLoaderWorker.m:36-89, 128-141` · A §3.1 E2 |
| R3 | Favourites across forums | GET | `/forum1f.php?owntopic={1\|3}` | `3` when setting `vos_sujets == 1` | `ObjCFavoritesLoaderWorker.m:46-48` · A E3 |
| R4 | Private messages list | GET | `/forum1.php?config=hfr.inc&cat=prive&page=1` | legacy list shows page 1 only; multi-page scan (`page=N` + long query) exists only in MPStorage | `ObjCMPTopicsLoaderWorker.m:9`, `MPStorage.m:692-736` · A E4, E §2.6 |
| R5 | Topic page | GET | `/forum2.php?config=hfr.inc&cat=..&post=..&page=..` or `/hfr/<cat>/<sub>/<slug>_<id>_<page>.htm` | Follow redirects; the **final URL** gives the page (permalink `post=` → page) | `ObjCTopicPageWorker.m:14-43, 86-94` · A E5, §3.4 |
| R6 | Profile page | GET | `/user/editprofil.php?config=hfr.inc&page={5\|1}` | page 5: `hash_check` + avatar after login; page 1: cookie refresh | `LoginService.swift:87-113`, `MultisManager.m:281` · A E10 |
| R7 | Smiley search | GET | `/message-smi-mp-aj.php?config=hfr.inc&findsmilies=+w1+w2` | ≥ 3 chars | `SmileySearchService.swift:12-42` · A E11 |
| R8 | MP unread count | GET | `/` | first integer in `.cCatTopic.red` | `MPBackgroundService.swift:80-135` · A E12 |
| R9 | Public profile page | GET | `/hfr/profil-{id}.htm` | `table.main` rows `profilCase2/3`, avatar, personal smileys | `UserProfileView.swift:113-430` · review F4 |

## 2. Search

| Id | Purpose | Method | URL | Body / behaviour | Source |
|---|---|---|---|---|---|
| S1 | Global search | POST | `/search.php?config=hardwarefr.inc` | Fields **in this order**: `hash_check, cat, search, resSearch=200, orderSearch=0, titre, searchtype, pseud="", daterange, [jour, mois, annee]`; defaults `cat=13, titre=3, searchtype=1, daterange=2`; query lowercased; legacy replaces the query when it contains a banned word (`jailbreak`, `cydia`, `pengu`, `apple jb`); SwiftHFR refuses the search with a warning instead (Q-7); body declared without charset. Response carries a `<meta http-equiv=refresh … url=…>` | `ObjCForumSearchWorker.m:31, 141, 149-181` · A E7 |
| S2 | Global search results | POST (same body), then GET for next pages | meta-refresh URL from S1 | `&amp;` → `&`; missing meta → "no result page" | `ObjCForumSearchWorker.m:46-95, 211-240` · A E8 |
| S3 | Intra-topic search | POST | `/transsearch.php` | `hash_check, p, post, cat, word, spseudo, filter=1, [firstnum, currentnum]`. **Do not follow redirects**: the `Location` header is the result; none → no result | `ObjCTopicSearchWorker.m:24-52` · A E6 |

## 3. Write flows

### 3.1 Common pattern (reply, edit, delete, new topic, MP)
1. GET the form page (answer URL, edit URL, new-topic URL, MP URL). It contains `<form name="hop">`.
2. Copy every `<input>` (checkbox → `"1"`/`"0"`, radio → value only if checked, others → `value`) and every `<select>` (selected or first option). Values must be HTML-entity-decoded (legacy Swift does not: bug).
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
| Delete | decoded `editURL` | edit with `delete=1` and the unchanged text; first post of a topic not deletable | `ReplyService.swift:954-1038` · D §2.4 |
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

- **Single quote**: GET the decoded `quoteURL`; the server returns the form with `content_form` prefilled `[quotemsg=cat,post,numreponse]…[/quotemsg]`. The reply is then posted to the topic's answer URL. `ReplyService.swift:767-841` · D §2.2
- **Multi-quote** (client-side cookie, as the site's JS does): `quoteJS` = `quoter('hardwarefr', cat, post, numreponse)`; cookie `quotes<arg0>-<arg1>-<arg2>` (e.g. `quoteshardwarefr-13-42`), value = concatenated `|<numreponse>`, domain `.hardware.fr`, path `/`, expires +1 h; deleted when empty. The next quote/answer GET must carry it. Match ids **exactly** (legacy substring match is a bug). `MessagesView.swift:1853-1929` · D §2.2b, C §5
- **Obfuscated URLs**: quote and edit URLs are stored in the CSS `class` of the element around `<img alt="answer">` (prefix of 20 characters); list pager links use `md_cryptlink` (prefix of 12). Decode: drop the prefix, then map each pair of characters through the alphabet `0A12B34C56D78E9F` (index = nibble) into one byte. Decode only if `length > 20` and the string contains neither `/` nor `http`. `RangeOfCharacters.m:92-114`, `ObjCMessageActionsBuilder.m:80-89` · C §3.4, D §2.2

## 5. Session, cookies and tokens

- **Login**: POST `/login_validation.php?config=hfr.inc` with `pseudo, password, action=send, login=Se connecter`; success ⇔ body contains `login_redirection.php`; then GET R6 page 5 for `hash_check` and avatar. Legacy clears all cookies *before* validating (bug). `LoginService.swift:48-129` · A §4.2
- **Identity cookie**: `md_user`; value `deleted` = logged out. A §4.1
- **`hash_check`**: anti-CSRF token required by every POST; hidden input on R1, R3 and R6 pages and in the topic page `hop` and `transsearch` forms (`name="hash_check"`). Per account; refreshed from parse results by `HFRClient`. `ObjCForumsParser.m:41`, `ObjCFavoritesLoaderWorker.m:105`, `LoginService.swift:100`, `ObjCTopicPageWorker.m:150-179` · A §3.1, C §3.3
- **Not logged in** on favourites (R3): `<body>` without `id`; message = first `<p>` or `.hop` text. `ObjCFavoritesLoaderWorker.m:87-95`

## 6. Transport behaviour

- **Encoding — unresolved (Q-2)**: legacy *sends* UTF-8 everywhere; *reads* UTF-8 with Latin-1/CP1252 fallbacks, inconsistently. Real `Content-Type` / `<meta charset>` per endpoint must be captured. A §3.2, D §2
- **HTTP status**: legacy ignores it; application errors are detected from content (`.hop`, `login_redirection.php`, missing `id`, `Location`). A §3.4
- **Headers**: no custom User-Agent, Referer or Origin; gzip accepted. Whether HFR checks any is unverified. A §3.3
- **Timeouts** (legacy): lists 30 s, topic search 60 s, global search 15 s, background MP check 5 s. No retry, no backoff, no rate limiting. A §3.5

## 7. Third-party services

| Service | Use | Notes | Source |
|---|---|---|---|
| `aq.super-h.fr` | "Alerte Qualitay" community reports | GET `/api/getAlertesByTopic.php?topic_id=`; POST `/api/addAlerte.php` (fixed field order, response `"1"` = success); RSS `/rss.php` (badge, "new since" `last_check_aq`, category 25 hidden unless pseudo `applereview`); unauthenticated, sends pseudo | D §2.7, `AQPlusView.swift:29-87` (decisions Q-4, Q-7) |
| Image rehost (Chevereto) | Image upload for posts | API key required (ADR 0007) | D §3.2 |
| Giphy | GIF picker | API key required (ADR 0007) | E §6 |
