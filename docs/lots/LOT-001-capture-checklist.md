# LOT-001 capture checklist

Approved by the operator on 2026-10-26, including W02, W20 and P03 from §B-2; every other §B-2 row is skipped. Run status and deviations: corpus `MANIFEST.md`.

## 0. Rules for every capture
- Raw bytes + headers + redirect chain are kept for every id (settles charset, audit A §3.2, D Q1; PROTOCOL §6). Anonymized afterwards ([FIXTURES](../FIXTURES.md), LOT-001 anonymizer); the legacy oracle runs on the anonymized file.
- Accounts: `anon` = no cookies; `user1`, `user2` = the two operator accounts. Pseudos become `user1`/`user2`.
- **Authenticated topic GETs mark the topic read for that account (E25).** Public pages are captured as `anon` unless the logged-in shape is the point.
- **Write flows only ever target user1 ↔ user2 private messages.** Anything else is in §B-2 ("needs operator decision", default = skip) or §C.
- Throttle ≥ 3 s between requests; total budget ≈ 90 requests; the script stops on the first 429/5xx.
- "Topic X" placeholders (`{T_…}`) are picked by the operator (or from the list captures R04-R07): public topics only, no private content. Selection hints are in each row.
- Status column: RO = read-only, W = STATE-CHANGING (session, MP between our accounts, or private flag).
- Lots: consumers per `docs/LOTS.md`. Settles: HFR-PROTOCOL §7 ids (X/E), redface2 comparison §4.4 items (written `4.4#n`), audit ids (B6, C8, D9), review F7/F8.

Sources for URLs: PROTOCOL §1-3 (`R1`-`R9`, `S1`-`S3`, §3.1-3.3) unless another citation is given; each PROTOCOL row cites its legacy `file:line`.

## A. Read-only GETs (≈ 40 captures)

### A-1 Home, lists, favourites, MP list

| Id | Page / flow | URL pattern (source) | Acct | RW | Lots | Settles |
|---|---|---|---|---|---|---|
| R01 | Home, logged out | `GET /` (R1; `ObjCForumsLoaderWorker.m:20`) | anon | RO | 021, 045 | encoding/headers (E27, PROTOCOL §6), B Q15; empty `hash_check`; Apple category absence (B §3.1) |
| R02 | Home, logged in, **unread MP = 1** (after W10) | `GET /` (R1, R8; `MPBackgroundService.swift:80-135`) | user1 | RO | 021, 023, 047 | B6; 4.4#7 (`.cCatTopic.red` vs list count); `hash_check` present |
| R03 | Home, logged in, no unread MP (after W13b read) | same | user1 | RO | 021, 023, 047 | B6 count 0 semantics; 4.4#7 |
| R04 | Topic list, big forum (cat 13), page 1, `owntopic=0` | `GET /forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=0` (R2; `ObjCForumTopicsLoaderWorker.m:36-89`) | anon | RO | 022, 002 | rows: sticky, closed, poll, ≥1000 replies, special titles (B §6.8) |
| R05 | Same, a middle page ≥ 10, then last page (2 captures) | `…&page=N` | anon | RO | 022 | pager structure, `md_cryptlink` 12-char prefix, long ranges (B Q5; E7) |
| R06 | Sub-forum list and single-page / empty filter (2 captures) | `/hfr/<cat>/<sub>/liste_sujet-1.htm` (B §6.9); `…&owntopic=1` on a forum with nothing | anon | RO | 022 | tabs `#onglet1..4`; "Aucun message" (B §6.6) |
| R07 | Small forum, page 1 | R2 with another `cat` | anon | RO | 021, 022 | 22-row category table check (B Q2) |
| R08 | Topic lists with `owntopic=1`, `2`, `3` (3 captures) | R2 `owntopic={1,2,3}` | user1 | RO | 022, 024 | flag URLs with `page=`, blue/red/yellow flags (B §6.7); `owntopic` semantics |
| R09 | Topic list `owntopic=3`, logged out | R2 | anon | RO | 022, 037 | "not logged in" detector on E2 (audit A Q6) |
| R10 | Favourites, `owntopic=1` and `3` (2 captures) | `GET /forum1f.php?owntopic={1\|3}` (R3; `ObjCFavoritesLoaderWorker.m:46-48`) | user1 | RO | 024 | B7 variants; multi-category, polls, sticky, category id ≥ 100 if any |
| R11 | Favourites, empty | R3 | user2 (must have none; else say which) | RO | 024 | `favorites-empty` (B §6.12) |
| R12 | Favourites, logged out | R3 | anon | RO | 024, 037 | `<body>` without `id` (PROTOCOL §5; `ObjCFavoritesLoaderWorker.m:87-95`) |
| R13 | MP list: unread + read + group row (after W10-W14) | `GET /forum1.php?config=hfr.inc&cat=prive&page=1` (R4; `ObjCMPTopicsLoaderWorker.m:9`) | user1 | RO | 022, 023, 038 | B6; E21 DOM; `[non lu] ` prefix and `closedbp.gif` (4.4#6); storage MP title if the account has one (read-only) |
| R14 | MP list page 2 (only if user1 has > 1 page; else skip) | `…&page=2` (`MPStorage.m:692-736`) | user1 | RO | 023, 038 | pager spans obfuscated on authenticated page 2+ (E7, E21) |
| R15 | Read-marking probe: user2 list `owntopic=1` before / after a `GET /` | R2, R1 | user2 | RO | 045, 047 | 4.4#7 and E25 (does an authenticated `/` mark read?) |

### A-2 Topic pages (the core of LOT-030..035)

| Id | Page / flow | URL pattern (source) | Acct | RW | Lots | Settles |
|---|---|---|---|---|---|---|
| R20 | Baseline multi-page topic, page 1 (40 msgs) | `GET /forum2.php?config=hfr.inc&cat=..&post=..&page=1` → 301 to `/hfr/<cat>/<slug>-sujet_<post>_<page>.htm` (R5; `ObjCTopicPageWorker.m:14-43`) | anon | RO | 030-033, 003 | C F01/F05: anonymous action links (`numrep=N&ref=M`, E7), `quoteJS`; E13; E19 page size; E27 |
| R21 | Same topic, page 1, logged in | same | user1 | RO (marks read) | 030, 031, 033 | authenticated URL shape (`citer-…htm`, `editer-…`), obfuscated crypt classes (E7, C8, F8), hop/`transsearch` forms' `hash_check` (PROTOCOL §5), `addflag`/`nonlu` links (C F23) |
| R22 | Middle page, and last (partial) page (2 captures) | `…_<page>.htm` | anon | RO | 030, 033 | "reprise du message précédent" block (C Q2), `maxPage`, no next, reply form (C F02/F03) |
| R23 | Single-page topic | R5 | anon | RO | 033 | `maxPage == 1` (C F04) |
| R24 | Page beyond max | `forum2.php?…&page=<max+1>` | anon | RO | 045, 033 | redirect to last page, effective URL (C F27, Q5; E13) |
| R25 | Permalink by message | `forum2.php?…&post=..&page=1&numreponse=M` | anon | RO | 045 | 301 + `#t<M>` fragment (E13; NET-09) |
| R26 | Quote content set, 2 pages: nested quotes (3 levels), old-style `oldcitation`, quote of a deleted/anonymous author | R5 | anon | RO | 032, 034 | C F11; E20 citation header forms |
| R27 | Spoilers (nested, with image) + code blocks + keyword colouring | R5 | anon | RO | 034 | C F13, F17 (**C8**) |
| R28 | Images: linked, bare, `reho.st`/`hfr-rehost.net`, broken, animated GIF; video embeds (YouTube long/short/`t=`, Vimeo, Streamable, Dailymotion, Twitch) | R5 | anon | RO | 034, 035, 056 | C F14, F18 (**C8**); E26 hosts |
| R29 | Signatures (short / image / link), edited messages with "Message cité N fois", deleted message, moderation notice, ad block ("Publicité") | R5 | anon | RO | 030, 034 | C F08-F10, F19; E20 |
| R30 | Smileys: standard (http vs https), perso, many in a row; pseudos with spaces/accents/`&`/zero-width; avatar over http | R5 | anon | RO | 030, 034 | C F15, F24, Q3 (**C8**); E22 |
| R31 | Locked/closed topic | R5 | anon | RO | 033, 036 | C F06: no reply link; E16 (composer URL not proof of postability) |
| R32 | Poll topic: results as `anon`; vote form as a user who has **not** voted | R5 + poll block | anon, user2 | RO (marks read) | 026, 054 | C F20; D11 radio value semantics (`PollData.swift:44-100`), E10 field names; D Q8 |
| R33 | Closed poll, and a poll the account already voted in (only if one exists; else §C N06) | R5 | anon / user1 | RO | 026 | C F20 variants |
| R34 | `quote_only=1` | `GET forum2.php?config=hfr.inc&cat&post&numreponse&quote_only=1` (E2) | anon | RO | — (optional) | E2 only; skip if the operator prefers |

### A-3 Forms (GET only, never submitted here)

| Id | Page / flow | URL pattern (source) | Acct | RW | Lots | Settles |
|---|---|---|---|---|---|---|
| R40 | Reply form of a **public** topic: fast-answer `#repondre_form` + plain `message.php` composer | first `<a>` of `#repondre_form` (PROTOCOL §3.1; `ObjCTopicPageWorker.m:156-157`) | user1 and anon (2) | RO | 036, 048 | D F1/F1b/F2; field list, `verifrequet` (X4), `subcat=0` (E17), `MsgIcon`, checkboxes `signature/smiley/emaill` (X3, D3); anonymous composer with pseudo/password (E16) |
| R41 | Single quote form of a public post, and quote of a post that itself quotes | decoded `quoteURL` (PROTOCOL §4; `ParseMessagesOperation.m:371-372`) | user1 | RO | 036, 049 | D F3/F3c; **X2** `[quotemsg=…]` meaning (4.4#2); cookie vs no cookie (X10) |
| R42 | Multi-quote form with the `quotes<a>-<b>-<c>` cookie set for 2-3 posts (cookie injected by the script, PROTOCOL §4) | same + `Cookie:` | user1 | RO | 049 | D F3b; X10; D C1 (cookie name arguments, D Q5) |
| R43 | Edit form GET of **own** message and of first post of own topic | decoded `editURL` (`ParseMessagesOperation.m:373-375`) | user1 / user2 on MP threads (W-created) | RO | 036, 048 | D F4/F4b: action (`bdd.php` vs `bddpost.php`, D Q2), `sujet`/`subcat`/flags (`have_sondage`, `sticky`…), `&amp;` entity decoding (F4c); X1 delete-topic label "Effacer l'intégralité du sujet" |
| R44 | Edit form attempted on another account's MP message (hand-built URL, GET) | `message.php?…&numreponse=<other>` | user2 | RO | 037, 048 | D R8 (edit by non-owner) |
| R45 | New-topic form, and new-MP form (`dest=user2`) | `#md_btn_new_topic` href (`ObjCTopicListParser.m:134-135`); `…/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=` (`ParseMessagesOperation.m:389-390`) | user1 | RO | 036, 048 | D F5/F6; subcat `<select>` selected/unselected; `newdest` (E8) |
| R46 | Moderator alert form GET on a public post (never submitted) | `GET /user/modo.php?config=hfr.inc&cat&post&numreponse&page&ref=1` (E3; `ReplyService.swift:1400-1531`) | user1 | RO | 036, 050 | D F9 "form" state; field `raison`; action keeps `?ref=18` (E3) |
| R47 | MP quote form and MP reply composer (on W threads) | `GET /message.php?config=hfr.inc&cat=prive&post=<id>&numrep=<n>&ref=<rank>&page=1&p=1&subcat=0&sondage=0&owntopic=0&new=0#formulaire` (E9) | user1 | RO | 036, 049, 058 | D F6b; E9 `numrep` meanings, `ref=0` "reprise" block |

### A-4 Search, smileys, profiles, REST, misc

| Id | Page / flow | URL pattern (source) | Acct | RW | Lots | Settles |
|---|---|---|---|---|---|---|
| R50 | Global search: POST → meta-refresh page, results page 1 and 2, results with pivot (multi-category), no results (4-5 captures) | `POST /search.php?config=hardwarefr.inc` (S1/S2; `ObjCForumSearchWorker.m:31,149-181`), then GET of the refresh URL | user1 | RO (search only) | 022, 025, 046 | B §6.13; X7/E12 shapes; 4.4#5 (`hardwarefr.inc` vs `hfr.inc`); field order |
| R51 | Global search as GET without session (rf2 path) | `GET /forum1.php?recherches=1&…` (X7) | anon | RO | 046 | 4.4#5 (GET without session, result page size) |
| R52 | Intra-topic search, **redirect not followed**: with match (Location), no match | `POST /transsearch.php` (S3; `ObjCTopicSearchWorker.m:24-52`) | user1 | RO | 046, 025 | 4.4#8 (Location vs followed), E28 (`dep`, `firstnum`); C F22 |
| R53 | Smiley search: 0 / 1 / many results and `+a+b` AND form; special chars | `GET /message-smi-mp-aj.php?config=hfr.inc&findsmilies=+w1+w2` (R7; `SmileySearchService.swift:12-42`) | user1 | RO | 025, 053 | audit **D9** S1/S4; charset (A Q1); E22 `user_id` |
| R54 | Smiley wiki detail | `GET /wikismilies.php?config=hfr.inc&detail=%5B%3Aezzz%5D` (`SmileyAlertView.m:151-152`) | anon | RO | 053 | audit **D9** S2 |
| R55 | Profile edit pages: `page=5`, `page=1`, `page=3` (3 captures); path check `/editprofil.php` vs `/user/editprofil.php` | `GET /user/editprofil.php?config=hfr.inc&page=5` (R6; `LoginService.swift:87-113`) | user1 | RO | 025, 043, 044 | **4.4#9** path; avatar/`hash_check` shape; E19 posts-per-page setting |
| R56 | Public profile page (another member and user2, as anon) | `GET /hfr/profil-{id}.htm` (R9; `UserProfileView.swift:113-430`; id regex `profil-[0-9]+.htm` `MessagesTableViewController.m:1880`) | anon | RO | 027 | F4 fields, personal smileys, "Statut" (E5) |
| R57 | REST API: categories, one category's topics, one topic (3 captures) | `GET /webservices/rest_api.php?uri=forums/hardwarefr/categories/` … (E1) | anon | RO | 057 | E1 (LOT-057 depends on 001); returned `/api/` hrefs 404 |
| R58 | Read marking via cookie-less prefetch | R5 as anon vs R21 flags afterwards | anon/user1 | RO | 045 | E25 (folded into R15; no extra capture if R15 is done) |

## B. Write flows

### B-1 Allowed now: session and MP between user1 ↔ user2 only

All use two **throwaway MP threads** titled `fixture-test-1`/`-2` created by W10/W11 (neutral text). Each POST response is captured whole (incl. `<meta refresh>`), plus the byte-exact request body (field order = the oracle for D3, audit D §9). Order matters: W01 → W10 … W23.

| Id | Flow | URL / fields (source) | Acct | RW | Lots | Settles |
|---|---|---|---|---|---|---|
| W01 | Login success user1 (staging jar) | `POST /login_validation.php?config=hfr.inc` `pseudo,password,action=send,login=Se connecter` (PROTOCOL §5; `LoginService.swift:62-67`) | user1 | W (session) | 043, 042, 025 | **X5, X12 (4.4#4)**: `Set-Cookie` names/attrs (`md_user`, `md_pass`, `md_forum`), body marker `login_redirection.php`, redirect page |
| W02 | Login failure: one wrong password for user2 (once) | same | user2 | W (session; lockout risk, **decision**) | 043 | X5 failure text, login flood text only if it appears (4.4#4); expect `md_user` absent |
| W03 | Login success user2 | same | user2 | W (session) | 043 | second jar; `hash_check` per account (C2) |
| W10 | New MP user1 → user2, **CRLF body**, 2 lines | `POST /bddpost.php?config=hfr.inc` from form R45; `dest`, `sujet`, `content_form` with `\r\n` (D F6; `AddMessageViewController.m:513-622`) | user1 | W | 048, 037, 036 | D R10; create success text (E15), redirect target (E14); `verifrequet=1100` (X4); form `action`; later read-back for CRLF (**X11, 4.4#3**) |
| W11 | New MP, same text with **bare LF** | same | user1 | W | 048 | X11: read back both via edit form (R43) |
| W12 | MP with a non-BMP character in the middle | same | user1 | W | 048 | **X9 / Q-3**: truncated at the first non-BMP char while answering success; read back |
| W13 | MP reply user2 → user1, two variants: (a) form copy with `"1"/"0"` checkboxes (legacy), (b) browser semantics (unchecked not sent) | `bddpost.php` (PROTOCOL §3.1; `ReplyService.swift:294-365`) | user2 | W | 048, 036, 037 | **X3 (4.4#3)**: effect of `signature=0`, `smiley`, `emaill`; E15 reply text; D R1 |
| W14 | Quote reply in MP (single quote, then a multi-quote post) | form R47 prefill → `bddpost.php` | user1 | W | 049, 048 | X2 (MP: second value = `ref`), X10 (several `[quotemsg]` blocks accepted?), E9 |
| W15 | Edit own MP message | action read from R43 form (`bdd.php` expected, D Q2) | user1 | W | 048, 037 | D R7; edit success text (E15); form action |
| W16 | Delete a non-first message | edit form + `delete=1` (PROTOCOL §3.1; `ReplyService.swift:954-1038`) | user1 | W | 048, 037 | D R9; delete text (E15); second delete of the same post |
| W17 | Rejections: (a) empty body, (b) invalid/garbled `hash_check`, (c) POST without cookies (logged out) | `bddpost.php` with altered field | user1 / anon | W (rejected, no content) | 037, 048 | D R3, R5, R6; E15 plain-text token error (~99 bytes), logged-out shape (`identification.php`/`name="login"`) |
| W18 | Mark MP unread | `GET /user/nonlu.php?config=hfr.inc&cat=prive&subcat=0&post=<thread>&page=1&p=1&sondage=0&owntopic=0&new=0` (E6) | user1 | W (own flag) | 058, 023 | E6; unread state binary per conversation |
| W19 | Delete the whole throwaway MP (first post, owner) | edit form of first post, `delete=1` (X1) | user1 | W | 048 | **X1** behaviour on first-post delete (MP variant), page afterwards (404?) — last step, cleans up |
| W20 | Flood: 4 quick replies in a throwaway MP within 10 min | `bddpost.php` | user2 | W (**decision**, see B-2) | 037, 048 | D R2, E15 flood wording (accent: "prevenir" vs "prévenir") |

### B-2 Needs operator decision (default: **skip**; the least intrusive option is proposed)

| Id | Flow | Why it matters | Least intrusive option | Default |
|---|---|---|---|---|
| P01 | Reply in a **public** topic | public form differs from MP (`cat`, `sujet`, `subcat`) and success redirect `…#bas` (E13) | rely on R40/R41/R43 (GET forms of public topics) + MP POSTs; or one reply "test" in a topic the operator owns, then edit it, never delete others' content | skip |
| P02 | Create a public topic and delete it (X1, E14 category redirect, D R10 new topic without subject) | topic creation response, `sujet`/`subcat` | one topic in the least-visited sub-category, neutral title, deleted by the owner right after (W19-like); operator names the category | skip |
| P03 | Favourite add/remove (`addflag` GET, `delflag` GET, `manageaction.php` POST) | D R12/R13, X6, 4.4#10 (`ref`/`page`/`p` needed?) | flags are private to the account: user2 adds then removes one flag on a public topic and restores the previous state; captures both responses and "already flagged" | **proposed yes**, operator to confirm |
| P04 | Moderator alert POST (sent / duplicate / pending / treated states, E3) | D R11 | none: alerts go to moderators. Cover with synthetic fixtures (§C N04) | skip |
| P05 | Poll vote POST (single, multi, already voted) | E10, D11, `vote.php` | none: votes are public. Synthetic (§C N05) | skip |
| P06 | Poll create/close (E11) | LOT-054 extension | MP threads cannot hold polls as far as we know: not captured | skip |
| P07 | Flood on a public topic | E15 | W20 in MP covers the wording; public limit may differ | skip |
| P08 | AQ service GET (`getAlertesByTopic`, RSS) | D A1-A3 | third-party host, not HFR; blocked on Q-4 (LOT-055) | skip |

## C. What we cannot capture safely, and how the oracle covers it

| Id | Item | Reason | Oracle / fixture instead |
|---|---|---|---|
| N01 | MPStorage create/update (`bddpost.php`/`bdd.php` to recipient `MultiMP`, M5/M6) | recipient is a third-party account: forbidden (MP only between user1 ↔ user2). Form action is settled by W15 | synthetic JSON from `MPStorage.m:769-828`, rf2 envelopes (E23/E24: 13+ namespaces, malformed, `mpFlags`, empty); "destiné" error page (M4) hand-built; legacy exporter runs on them (LOT-004) |
| N02 | Reading an MPStorage document of the operator's accounts | personal data; only if one already exists | if present, R13 lists it and the anonymizer replaces JSON; otherwise synthetic as N01 |
| N03 | Image rehost (Chevereto) and Giphy responses (I1-I3) | API key, uploads to a third party (ADR 0007) | hand-written JSON from `RehostImage.m:230-297` |
| N04 | Moderator alert states: pending-mine/joined, treated (E3), already alerted | requires bothering moderators | hand-built `.hop` pages from E3 texts + `ReplyService.swift:1400-1531` test snippets |
| N05 | Poll vote responses ("Votre vote a bien été pris en compte !", "déjà voté", E10) | public effect | hand-built from E10 texts |
| N06 | Poll states not obtainable (already voted / closed) | depends on forum content | R32/R33 if found, else hand-built from R32 |
| N07 | Group MP (`newdest`, "Interlocuteurs multiples", E8/E21 group row) | needs a third member | synthetic row from E21 DOM; R13 may contain one if user1 already has a group MP |
| N08 | Maintenance page, error pages (`<body><p>…`, B §6.3), NUL byte / invalid UTF-8 (C F25) | cannot be provoked | synthetic |
| N09 | Locked-topic POST refusal (E16) | needs a locked topic we may post in | R31 + hand-built refusal `.hop` |
| N10 | Login flood text (X5) | would lock an operator account | hand-built from X5 text |
| N11 | Blacklist/whitelist/own-pseudo policy variants (C F12, F26 filtered-posts) | legacy context, not a page | oracle run on captured R20-R30 with a fixed settings plist (LOT-003) |
| N12 | Rate-limit / `429` shapes | abuse | none |
| N13 | Staff directory (E5), sanctions (E4) | not used by any lot | not captured |

## D. Totals and dependencies
- Read-only captures: ≈ 55 files from ≈ 40 ids (several ids hold 2-5 captures). **Over the 25-40 target**: the least valuable to drop first are R34, R14, R58 (folded), R06 second capture, R51. The operator can cut A-1/A-4 rows without blocking Phase 3.
- Writes: 13 MP/session flows (W01-W20) + 1 proposed flag test (P03).
- Dependency order: W01, W03 → W10 → R02 → W13 → R03 → W11, W12, W14, W15, W16, W17, W18 → R13, R43, R47 → W19 (cleanup). Topic pages R20-R34 are independent.
- Consumers coverage check: 021 (R01-R03, R07), 022 (R04-R09, R13), 023 (R02, R03, R13, W18), 024 (R08, R10-R12), 025 (R50-R55), 026 (R32, R33), 027 (R56), 030-035 (R20-R31), 036-037 (R40-R47, W10-W20), 038 (R13, N01), 041-042 (W01, W03, R40), 043-044 (W01-W03, R55), 045 (R20-R25, R15), 046 (R50-R52), 047 (R02, R03), 048-051 (W10-W19, D03), 052 (N01 + W15), 053 (R53, R54), 054 (R32), 056 (R28), 057 (R57), 058 (W18, R47).
