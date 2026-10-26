# Capture corpus (LOT-001)

Shared corpus of live HFR responses captured on 2026-10-26 with `tooling/fixtures/flows.py`, then published with
`tooling/fixtures/publish.py` (manifest `tooling/fixtures/corpus.json`): every member pseudo in every member position
and, when specific enough, in free text → `user1`/`user2` (operator accounts) and `userN` (consistent within a file;
personal smiley codes share the alias of the member they are named after), operator ids → `9000NN`, other members'
ids → `9100NN` (profile links, contact links, avatars, quote prefills), signatures and mood statuses → placeholders,
tokens and cookies → `REDACTED`. Each capture
has `<id>.meta.json`: URL template, requested and final URL, redirect hops, HTTP status, content type, server date,
account role (`anon`, `user1`, `user2`), names of the cookies set (never values) and, for POSTs, the anonymized request
body in field order, with the same aliases as its page. CI runs `anonymize.py check --corpus` on this folder.
Per-lot oracles (legacy parser output) are added next to these files by LOT-002..004.

Checklist: LOT-001 capture checklist (operator-approved 2026-10-26). Ids follow its rows; a suffix (`a`, `b`, `-1`)
splits a row into several captures. Public topics were picked from the anonymous lists R04-R07 (neutral subjects).

**Run status.** Run 1 (52 requests) did the read-only rows; user1's stored password was refused (W01), so the
"logged in" rows ran as `user2`, and it stopped at an HTTP 500 (R55 path check). Run 2 (52 requests, 104 in total) did
the write flows inside **one** throwaway MP thread `fixture-test-1` (user2 → user1, neutral text), the flag test P03
on a public topic (state restored), the searches, then user1 again with a corrected password (W01b). Private files
(`"private": true` in the meta) were anonymized with `--private`: MP bodies and the subjects of every MP that is not a
fixture thread are replaced.

| Id | File | Covers | Row | Lots |
|---|---|---|---|---|
| R01 | `R01-home-anon.html` | Home, logged out: 19 categories (incl. `apple`, `ia`), moderator MP links, empty `hash_check` in `#fastsearch` | R01 | 021, 045 |
| R03 | `R03-home-logged-in-no-unread-mp.html` | Home, logged in (user2), no unread MP: MP row "Envoyer / lire des messages privés" without a count; 32-hex `hash_check` | R03 | 021, 023, 047 |
| R04 | `R04-list-cat13-p1-anon.html` | Topic list cat 13 page 1 via `forum1.php` → 301 to `/hfr/Discussions/liste_sujet-1.htm`: sticky, locked, poll rows, big page counts | R04 | 022, 002 |
| R05a | `R05a-list-cat13-p12-anon.html` | List page 12: pager links obfuscated (`md_cryptlink`) except page 1 | R05 | 022 |
| R05b | `R05b-list-cat13-p500-anon.html` | Deep list page 500 (not the last page: the pager goes on) | R05 | 022 |
| R06 | `R06-list-subcat-cuisine-anon.html` | Sub-forum list `/hfr/Discussions/Cuisine/liste_sujet-1.htm` | R06 | 022 |
| R07 | `R07-list-graphisme-anon.html` | Another forum's list page 1 (`/hfr/Graphisme/…`) | R07 | 021, 022 |
| R08-1 | `R08-1-list-cat13-owntopic1-empty.html` | `owntopic=1`, logged in, empty: `.hop` "Aucun sujet auquel vous avez participé n'est connu" | R08 | 022, 024 |
| R08-2 | `R08-2-list-cat13-owntopic2.html` | `owntopic=2` (read), one row: the topic read by R21 (E25), `flag0`/`flag1`/`favoris` icons | R08, R15/R58 | 022, 024, 045 |
| R08-3 | `R08-3-list-cat13-owntopic3-empty.html` | `owntopic=3`, empty: "Aucun favori n'est repertorié" | R08 | 022, 024 |
| R09 | `R09-list-cat13-owntopic3-anon.html` | `owntopic=3` logged out: 301 to the plain list, filter silently dropped | R09 | 022, 037 |
| R10 | `R10-favourites-owntopic1.html` | `forum1f.php?owntopic=1`, two tracked topics in two categories | R10 | 024 |
| R11 | `R11-favourites-owntopic3-empty.html` | `forum1f.php?owntopic=3` with no favourite | R11 | 024 |
| R12 | `R12-favourites-anon.html` | `forum1f.php` logged out: `<body>` without `id`, `.hop` "Aucun sujet que vous avez lu n'est connu" | R12 | 024, 037 |
| R20 | `R20-topic-p1-anon.html` | Topic page 1, 40 posts, logged out: action links `message.php?…&numrep=N&ref=M…#formulaire` in `md_noclass_cryptlink` spans, ads | R20 | 030-033, 003 |
| R21 | `R21-topic-p1-logged-in.html` | Same page logged in: same action-link shape, `quoter(…)` JS, `addflag`/`delflag`/`modo.php` links, `#repondre_form`, fast-answer `hop` form, logout link (token redacted) | R21 | 030, 031, 033 |
| R22a | `R22a-topic-middle-page-anon.html` | Middle page (1100): "reprise du message précédent" block, 33 bodies | R22 | 030, 033 |
| R22b | `R22b-topic-last-page-anon.html` | Last page (2201), 10 posts | R22 | 030, 033 |
| R23 | `R23-topic-single-page-anon.html` | Single-page topic | R23 | 033 |
| R24 | `R24-topic-beyond-last-page-anon.html` | `page=max+1`: 301, 301, then 302 to the last page | R24 | 045, 033 |
| R25 | (meta only) | Permalink `…&numreponse=M`: 301 with relative `Location: …-sujet_<post>_<page>.htm#t<M>`, empty body | R25 | 045 |
| R26 | `R26-topic-quotes-smileys-anon.html` | Chatty page: quotes, many personal smileys, signatures | R26, R30 | 032, 034 |
| R27 | `R27-topic-spoilers-anon.html` | Spoilers, quotes, YouTube embeds, edited/cited trailers | R27 | 034 |
| R27b | `R27b-topic-code-blocks-anon.html` | Code blocks (cat 10, single page) | R27 | 034 |
| R27-list | `R27-list-list-programmation-anon.html` | Programmation list page 1 (used to pick R27b) | — | 022 |
| R28 | `R28-topic-images-videos-anon.html` | 42 images, quotes, spoiler, YouTube | R28, R29 | 034, 035, 056 |
| R31 | `R31-topic-locked-anon.html` | Locked, sticky, single-page topic | R31 | 033, 036 |
| R32a | `R32a-topic-poll-anon.html` | Poll topic logged out: vote form `/user/vote.php?config=hfr.inc` shown, radio `reponse` | R32 | 026, 054 |
| R32b | `R32b-topic-poll-logged-in-not-voted.html` | Same, logged in, not voted | R32 | 026, 054 |
| R40a | `R40a-reply-form-logged-in.html` | Reply composer (`message.php`), logged in: `hop` form to `/bddpost.php?config=hfr.inc`, `verifrequet=1100`, pseudo echoed, checkboxes | R40 | 036, 048 |
| R40b | `R40b-reply-form-anon.html` | Same composer logged out: empty `hash_check`, visible pseudo/password | R40 | 036, 048 |
| R41a | `R41a-quote-form.html` | Quote form (`numrep=<cited>&ref=1`): prefill `[quotemsg=<numreponse>,1,<author id>]` | R41 | 036, 049 |
| R41b | `R41b-quote-form-of-quoting-post.html` | Quote of a post that quotes (`ref=3`): second value 3 | R41 | 036, 049 |
| R42 | `R42-multiquote-form-cookie.html` | Composer with cookie `quoteshardwarefr-13-<post>=\|a\|b`: two `[quotemsg]` blocks prefilled | R42 | 049 |
| R45a | `R45a-new-topic-form.html` | New-topic form `/hfr/Discussions/nouveau_sujet.htm`: `sujet`, `toread1..5`, `subcat` select | R45 | 036, 048 |
| R45b | `R45b-new-mp-form.html` | New-MP form (`dest` prefilled), never submitted | R45 | 036, 048 |
| R46 | `R46-modo-alert-form.html` | Moderator alert form, GET only, never submitted | R46 | 036, 050 |
| R53a | `R53a-smiley-search-no-result.html` | Smiley search, no result: 40-byte text "Désolé, aucune réponse n'a été trouvée !" | R53 | 025, 053 |
| R53b | `R53b-smiley-search-one-word.html` | One word: 657 smileys | R53 | 025, 053 |
| R53c | `R53c-smiley-search-two-words.html` | Two words: 1010 smileys (words are OR-ed, not AND-ed) | R53 | 025, 053 |
| R54 | `R54-smiley-wiki-detail-anon.html` | Smiley wiki detail page | R54 | 053 |
| R55-p1 | `R55-p1-profile-edit-page1.html` | `/user/editprofil.php?page=1`: personal fields (redacted, birth date and gender unselected) | R55 | 025, 043, 044 |
| R55-p3 | `R55-p3-profile-edit-page3.html` | Page 3: display settings incl. `topicpp` (posts per page) | R55 | 025, 044 |
| R55-p5 | `R55-p5-profile-edit-page5.html` | Page 5: `hash_check` only form | R55 | 025, 043, 044 |
| R57a | `R57a-rest-categories.json` | REST categories (20) | R57 | 057 |
| R57b | `R57b-rest-category-topics-last.json` | REST last topics of cat 13 (25 per page) | R57 | 057 |
| R57c | `R57c-rest-topic.json` | REST one topic | R57 | 057 |
| W00 | `W00-login-form-anon.html` | Login page `login.php`: form `form1` fields | W01 (diagnosis) | 043 |
| W01 | `W01-login-failure.html` | Refused login (user1, stored credentials): `.hop` "Votre mot de passe ou nom d'utilisateur n'est pas valide", refresh to `/`, no cookie | W01 (stands in for W02) | 043 |
| W03 | `W03-login-success.html` | Login success (user2): "Vérification de votre identification...", refresh to `login_redirection.php`, cookies `md_user`, `md_passs`, `md_id` | W03 | 043, 042, 025 |
| W01b | `W01b-login-success-user1.html` | Login success (user1, corrected password) | W01 | 043 |
| R02 | `R02-home-logged-in-unread-mp.html` | Home, user1 with unread MPs: `a.cCatTopic.red` "Vous avez 10 nouveaux messages privés" (= number of unread conversations) | R02 | 021, 023, 047 |
| W10 | `W10-mp-create-crlf-success.html` | New MP user2 → user1 (CRLF body): "Votre message a été posté avec succès !", refresh to the MP list, no thread id | W10 | 048, 037, 036 |
| W11x | `W11x-mp-create-second-topic-flood.html` | Second new MP refused: "… plus de 1 nouveaux sujets consécutifs dans un intervalle de 60 minutes" | W11 | 037, 048 |
| R13a | `R13a-mp-list.html` | MP list (user2, one thread): read icon `closedp.gif`, `[non lu]` span = the **recipient** has not read it | R13 | 022, 023, 038 |
| RA1 | `RA1-mp-thread-after-create.html` | MP thread page after W10 (owner): edit link `message.php?…&numreponse=`, quote link `…&numrep=&ref=`, `nonlu.php` link | R43/R47 | 030, 058 |
| R43a | `R43a-mp-edit-form-first-post.html` | Edit form of the first post: action `/bdd.php`, `delete` checkbox "Effacer l'intégralité du sujet", CRLF stored as sent | R43 | 036, 048 |
| R47b | `R47b-mp-reply-composer.html` | MP reply composer (owner): no `newdest` field | R47 | 036, 058 |
| W11 | `W11-mp-reply-lf-legacy-success.html` | Reply with bare LF and legacy `"0"` checkboxes (also W13a): "Votre réponse a été postée avec succès !", refresh `…#bas` | W11, W13 | 048, 036 |
| W12 | `W12-mp-reply-nonbmp-success.html` | Reply with U+1F600 in the middle: success answered, text cut before the emoji (see R43c, RA2) | W12 | 048 |
| W20a | `W20a-mp-reply-flood.html` | Flood: "Afin de prevenir les tentatives de flood, vous ne pouvez poster plus de 3 réponses consécutives dans un intervalle de 10 minutes" | W20 | 037, 048 |
| W20b | `W20b-mp-reply-flood-again.html` | Same refusal 3 s later | W20 | 037 |
| RA2 | `RA2-mp-thread-crlf-lf-nonbmp.html` | Thread after W11/W12: smiley rendered with `smiley=0`, truncated non-BMP post | X11, X9 | 030, 048 |
| R43b | `R43b-mp-edit-form-lf-post.html` | Edit form of a non-first post: delete label "Effacer ce message", LF stored as sent | R43 | 036, 048 |
| R43c | `R43c-mp-edit-form-nonbmp-post.html` | Edit form of W12: stored text "fixture-test 3, before" | R43, X9 | 048 |
| W15 | `W15-mp-edit-success.html` | Edit (with `delete=0` sent): "Votre message a été édité avec succès !", refresh `…#t<numreponse>` | W15 | 048, 037 |
| R47a | `R47a-mp-quote-form.html` | MP quote form (`numrep=<cited>&ref=2`): `[quotemsg=<numreponse>,2,<author id>]` | R47 | 049, 058 |
| W18 | `W18-mp-mark-unread-success.html` | `nonlu.php`: "Le message a été marqué comme non lu avec succès", refresh to the MP list | W18 | 058, 023 |
| R13b | `R13b-mp-list-after-mark-unread.html` | MP list after W18: icon `closedbp.gif` (unread) | W18, R13 | 023 |
| P03a | `P03a-addflag-success.html` | `addflag.php`: "Favori positionné avec succès", refresh to the sub-forum list | P03 | 051, 024 |
| P03b | `P03b-addflag-again.html` | Same call again: same success text (idempotent) | P03 | 051 |
| P03c | `P03c-favourites-after-addflag.html` | Favourites list with the flagged topic | P03 | 024 |
| P03d | `P03d-delflag-favourite-success.html` | `delflag.php?…&owntopic=3`: "Drapeau effacé avec succès" | P03 | 051 |
| P03e | `P03e-favourites-after-delflag-empty.html` | Favourites empty again (state restored) | P03 | 024 |
| P03f | `P03f-list-owntopic2-after-delflag.html` | Read list after delflag: the topic's read flag is gone too | P03 | 024, 051 |
| R50a | `R50a-search-post-waiting-page.html` | Global search POST: "Votre recherche est en cours…", refresh to `GET /forum1.php?recherches=1&…&config=hfr.inc` | R50 | 025, 046 |
| R50b | `R50b-search-results-no-cookie.html` | That GET without cookies: 50 rows, `post_cat_list` | R50, R51 | 022, 046 |
| R50c | `R50c-search-no-result-no-cookie.html` | No result: `.hop` "Désolé, aucune réponse n'a été trouvée !" | R50 | 046 |
| R52a | (meta only) | `transsearch.php` match: **302**, `Location: /forum2.php?…&word=<UPPER>&currentnum=<n>#t<n>` | R52 | 046 |
| R52b | `R52b-transsearch-no-match.html` | No match: 200, `.hop` "Désolé aucune réponse n'a été trouvée" | R52 | 046 |
| W17a | `W17a-mp-reply-empty-body-rejected.html` | Empty body: "Vous devez remplir tous les champs avant de poster ce message" | W17 | 037 |
| W17c | `W17c-mp-reply-logged-out-rejected.html` | POST without cookies: "Désolé, vous devez être enregistré pour poster sur le forum" | W17 | 037, 044 |
| W17b | `W17b-mp-reply-bad-token-rejected.html` | Bad `hash_check`: 99-byte plain text "Une erreur est survenue lors de l'envoi des données…" | W17 | 037 |
| W13b | `W13b-mp-reply-browser-semantics-success.html` | Reply, browser semantics with `smiley=1`: smileys not rendered (see RA3) | W13 | 048, 036 |
| R47c | `R47c-mp-composer-multiquote-cookie.html` | MP composer with `quoteshardwarefr-prive-<post>` cookie: two `[quotemsg]` blocks | W14 | 049 |
| W14x | `W14x-mp-reply-flood-fourth-consecutive.html` | 4th consecutive post 23 s after the 3rd: flood | W14, W20 | 037 |
| W14 | `W14-mp-reply-multiquote-success.html` | Multi-quote reply, 10 min later: success | W14 | 049, 048 |
| W16a | `W16a-mp-delete-post-success.html` | Delete a non-first post (`delete=1`): "Message effacé avec succès !" | W16 | 048, 037 |
| W16b | `W16b-mp-delete-post-again.html` | Second delete of the same post: same success text | W16 | 037 |
| R13u1 | `R13u1-mp-list-recipient-unread.html` | user1's MP list (subjects of non-fixture MPs replaced): 50 rows, 7 pages, group rows, MPStorage row, pager obfuscated | R13, R14 | 022, 023, 038 |
| RU1 | `RU1-mp-thread-recipient-view.html` | Thread seen by the recipient: no edit link on the other account's posts | R43 | 030, 031 |
| R47u1 | `R47u1-mp-reply-composer-recipient.html` | Reply composer, recipient side | R47 | 036 |
| W13cx | `W13cx-mp-reply-flood-other-account.html` | user1's first reply refused by the flood rule (4th consecutive post in the thread, other account, same client) | W20 | 037 |
| RA3 | `RA3-mp-thread-before-cleanup.html` | Thread with edits, quotes, a deleted post | W15, W16 | 030, 048 |
| W13c | `W13c-mp-reply-recipient-success.html` | user1 → user2 reply after 10 min: success | W13 | 048 |
| RA4 | `RA4-mp-thread-both-accounts.html` | Thread with posts from both accounts (owner view) | R43 | 030 |
| R44 | `R44-mp-edit-form-other-account-message.html` | Edit form requested by the owner (user2) on user1's message: served (action `/bdd.php`, text prefilled, no delete box). Never submitted | R44 | 037, 048 |
| W19 | `W19-mp-delete-first-post-success.html` | Owner deletes the first post (`delete=1`): "Message effacé avec succès !", refresh to the MP list | W19 | 048 |
| RA5 | `RA5-mp-thread-after-delete-owner.html` | Owner afterwards: 200, `.hop` "Ce message ne vous est pas destiné, désolé" | W19, X1 | 037, 048 |
| R13c | `R13c-mp-list-empty-after-delete.html` | Owner's MP list: empty | W19 | 023 |
| R13u1b | `R13u1b-mp-list-recipient-after-owner-delete.html` | Recipient's list: the thread is **still there** | W19, X1 | 023 |
| RU2 | `RU2-mp-thread-recipient-after-owner-delete.html` | Recipient can still read the whole thread | W19, X1 | 030, 048 |

## Not captured

| Rows | Why |
|---|---|
| W02 | Dropped: W01's refusal already gives the failure page; a second failed login was not worth the lockout risk. |
| A second throwaway thread | HFR allows one new topic per 60 minutes (W11x); everything ran in one thread. |
| R33, R34, R51, R58 | Dropped per the checklist (R51 covered by R50b, R58 by R08-2). |
| R56 | Skipped: a public profile shows personal data. |
| X10 cookie-less multi-quote, poll vote, public posting | Out of the approved scope or not needed. |
| oldcitation, Streamable/Dailymotion/Twitch, reho.st images | Not present on the pages picked; synthetic or a later capture. |
