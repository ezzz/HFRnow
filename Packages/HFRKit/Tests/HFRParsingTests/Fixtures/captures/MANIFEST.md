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
fixture thread (`fixture-test-N`) or the MPStorage thread are replaced, whatever their content (digits included).
Run 3 (follow-up, 11 requests, 115 in total, read-only) added R33a/R33b, R55-p5u1 and R56a/R56b. Run 4 (2026-10-27, P01 approved by the operator that day, 22 requests): user2 replied once in one public topic
(cat 13), edited and deleted that reply (W30-W33, R61b-R62b; the post is gone, `R61e`), and one empty-body reply was refused;
user1 also edited the first post of one of its own topics and restored it (R63a, R63b, R63e, W34, W35; the
edit forms read back after the edit and after the restore, R63c and R63d, were captured to verify the restore and are
not published). **Own
topics** (`own_topics` in the local config) are unlinked by the anonymizer: topic id → `9900001`, message ids →
`9910000001`… (one table for the batch), subject → `Own topic subject`, slug → `own-topic-subject`, message bodies,
the form review and the description → `Own topic text removed.`, each line of the edit text → `Text removed.` (line
breaks kept), related-topic links → `Related topic`, dates → `01-01-2000` / `00:00:00`, the meta date →
`Sat, 01 Jan 2000 00:00:00 GMT`.
Run 5 (2026-10-27, LOT-038 inputs, 4 requests: user1 login, MP list page 1 to locate the thread, R60a, R60b; read-only
on HFR, nothing submitted) opened user1's MPStorage thread, which marked it read for that account (its own storage
thread). Its first post is the storage JSON document: `--private` keeps that one body (thread header and page title
name the MPStorage thread, and the document holds only known keys and the strings `0.1` and `iOS`; anything else stops
the anonymizer), every other body is replaced as usual.
Run 6 (2026-10-28, LOT-051 inputs, ezzz/HFRnow#304 and #305, approved by the operator that day, 37 requests) used user2
only. It made 13 flag writes, at least 65 s apart: 7 `addflag`, 3 `manageaction.php` delflags and 3 `delflag`. Its
favourites were three public cat 13 topics that it had no flag on. It also sent one `addflag` GET without cookies. Before
the first write and after the last one, `forum1f.php?owntopic=0..3` was read (not published). Both reads show the same
topics with the same flag kinds and positions, so the state was restored. The topics read along the way lost their read
flag with their favourite. Public profile pages
(R56) keep their structure; the pseudo (title, header, pseudo cell, avatar `alt`, personal smileys, MP and
"all posts" links) is aliased, every personal row (e-mail, birth date, gender, city, job, hobbies, quote, signature)
gets `Profile field removed.` or, for dates, `01/01/2000`; post count → `100`, arrival and last-post dates →
`01/01/2000` / `01-01-2000 à 00:00`, transaction counts → `0`. Category link texts (`liste_sujet-N.htm`,
`forum1.php?…cat=`) are never rewritten, so a member named like a word of a category name leaves the category alone.

Run 7 (2026-11-02, `mac/capture-batch` batch 1, ezzz/HFRnow#168, #173, #109, #141, #281, #282, #283, 16 requests,
read-only apart from one tokenless `unlog.php` GET) logged user1 and user2 in and read their followed lists, then sent
user2's jar with its own `md_user`/`md_id` and a wrong 32-hex `md_passs` (a stale session; the jar was edited outside the
repository, nothing was sent to HFR beyond these GETs) to the home, `forum1f.php?owntopic=1` and profile pages 1 and 5.
`md_passs` was identical after a second login of user2 (compared locally, never printed). The `Set-Cookie` attributes
of `R74` are written in its meta `note` (values are never kept).

Run 8 (2026-11-02, `mac/capture-batch` public writes, ezzz/HFRnow#275, #265, #138, #135, #136, #137 and #302, approved by
the operator that day on #337, 27 HFR requests and 2 image-host uploads, one attempt per state): user1 created one
throwaway topic `fixture-test` in Programmation › iOS (`W40`), added a two-answer poll to it by editing its first post
(`W41`), voted (`W42`), voted again (`W43`); user2 sent the same vote (`W44`) and a moderator alert on the topic's first
post whose text says it is a test of the app's developers to ignore (`W46`), then reopened the alert page (`R88`); the
alert was also sent and opened without cookies (`W47`, `R89`). user1 then deleted the first post, which deleted the
topic (`W49`, `R92`). The topic is an **own topic** for the anonymizer (aliased as above); `publish.py` now also takes
the own topic from the request (URL, body, `numeropost=`) when a `.hop` answer does not name it. `U01`/`U02` are the
`img3.super-h.fr` upload answers (a 16×16 grey JPEG, legacy multipart layout, the legacy key and a wrong one): the
key, `delete_hash`, delete token and image id are redacted, the random file number is `1234567890`.

Run 9 (2026-11-02, `mac/capture-batch` batch 2, ezzz/HFRnow#169, #114, #333, #334, #172 and #171, private MP writes
between the operator's two accounts, 28 HFR requests including 3 static scripts of `forum-images.hardware.fr`, one attempt
per state): user2 opened a throwaway thread `fixture-test-2` to user1 whose first post holds every composer toolbar tag
(`W61`); user1 answered with BMP emoji (`W62`); user2 sent a multi-quote reply with the selection cookie written as the
site's `forum2.js` `quoter()` writes it (`escape()`d value, host-only, path `/`) on both the composer GET and the POST
(`R95g`, `W63`). The stored sources are the edit forms (`R95c`, `R95f`, `content_form` byte for byte what was sent); the
rendered HTML is HFR's own preview `POST /apercu.php` (`R95d`, `R95h`, the `apercu_form` of the composer, fields as
`editPost.js` `apercevoir()` sets them), because `--private` replaces the bodies of the thread pages. On the raw thread
pages, the preview equals the message body once whitespace is removed, apart from the opening `<p>` the preview lacks
(compared locally, not published). user2 then sent legacy's `manageaction.php` delete body (`MPListView.swift:131-150`) with a
wrong `hash_check`, which HFR refused (`W64x`), then deleted the thread with the right one (`W64`); user1 deleted it too
(`W65`, clean-up). Nothing of the thread is left on HFR. `flows.py form` gained `--cookie` (sent with the POST only).

Run 10 (2026-11-02, `mac/capture-batch` batch 3, ezzz/HFRnow#133, #174, #134, #301 and #127, read-only, no account, 20
requests: 4 to `forum.hardware.fr`, 16 to other hosts). `T` ids are third-party hosts. The Alertes Qualitaÿ feed and one
topic's alert list (`T01`, `T02`, `aq.super-h.fr`) are anonymized by position: every initiator and reporter → `userN`, and
the member-written alert titles and comments → one `x` per word, entities and punctuation kept (the encodings LOT-028 must
decode); public topic titles stay. Image hosts were asked cookie-less for one image URL each of `R20`/`R22a` over `https`,
then over `http` where `https` failed or redirected; a request that got no HTTP answer is recorded as status 0 with the
error in the note (`flows.py get --record-network-error`), and a `Referer` sent is recorded in the note (`--referer`).
Image bodies are not published (meta only). Three public topic pages were read only to look for a `reho.st` image and
are not published (none found).

Run 11 (2026-11-06, `mac/m2-lead` batch `m2-misc`, ezzz/HFRnow#117, #130 and #137, operator-ordered, 19 requests): user1's deep category
list page for the badge (`R117a`); one new MP user1 → user2 `fixture-test-3` whose body starts with a line break (`W130`) and its
thread, edit form and quote form read only (`R130a`-`R130c`); the mark-unread link of that thread sent twice without cookies
(`W137a`, `W137b`); user1 then deleted the thread (`W131`) and user2's list and thread were read (`R130d`, `R130e`; the thread was
already gone for user2). Nothing of the thread is left on HFR. One message, no edit POST, no retry.

Run 14 (2026-11-07, `mac/cap-601-603`, ezzz/HFRnow#601 and #603, read-only, 22 requests): the two logins, then GETs only. The
personal smiley page of both accounts and without cookies (`R601a`-`R601d`); the filtered lists of one category, one sub-forum and
the favourites page (`R603a`-`R603e`); the REST `read` bucket of one category (`R603f`). Nothing was sent to the forum.

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
| R08-2 | `R08-2-list-cat13-owntopic2.html` | `owntopic=2` (read), cat 13: a sticky and two topics; rows aliased by position (topic ids `9800001`…, titles, counts and dates, [kit README](../../../../../tooling/fixtures/README.md#list-rows)), `flag0` icons; re-captured 2026-11-06 | R08, R15/R58 | 022, 024, 045 |
| R08-3 | `R08-3-list-cat13-owntopic3-empty.html` | `owntopic=3`, empty: "Aucun favori n'est repertorié" | R08 | 022, 024 |
| R09 | `R09-list-cat13-owntopic3-anon.html` | `owntopic=3` logged out: 301 to the plain list, filter silently dropped | R09 | 022, 037 |
| R10 | `R10-favourites-owntopic1.html` | `forum1f.php?owntopic=1`, two topics in two categories, rows aliased by position (see R08-2), `favoris.gif`; re-captured 2026-11-06 | R10 | 024 |
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
| R32a | `R32a-topic-poll-anon.html` | Poll topic logged out: vote form `/user/vote.php?config=hfr.inc` shown, radio `reponse` | R32 | 005, 026, 054 |
| R32b | `R32b-topic-poll-logged-in-not-voted.html` | Same, logged in, not voted | R32 | 005, 026, 033, 054 |
| R33a | `R33a-topic-poll-closed-anon.html` | Closed poll (locked topic), logged out: results only (bars, `N votes`, `Total`), no form, "Ce sondage est clos, vous ne pouvez plus voter" | R33 | 005, 026, 054 |
| R33b | `R33b-topic-poll-already-voted.html` | Poll already voted, logged in (user1): results only, no form, "(Multipseudo detecté, vous ne pourrez pas voter à ce sondage avec vos autres pseudos)" (user2 sees the same notice; the page does not tell which account voted) | R33 | 005, 026, 033, 054 |
| R40a | `R40a-reply-form-logged-in.html` | Reply composer (`message.php`), logged in: `hop` form to `/bddpost.php?config=hfr.inc`, `verifrequet=1100`, pseudo echoed, checkboxes | R40 | 036, 048 |
| R40b | `R40b-reply-form-anon.html` | Same composer logged out: empty `hash_check`, visible pseudo/password | R40 | 036, 048 |
| R41a | `R41a-quote-form.html` | Quote form (`numrep=<cited>&ref=1`): prefill `[quotemsg=<numreponse>,1,<author id>]` | R41 | 036, 049 |
| R41b | `R41b-quote-form-of-quoting-post.html` | Quote of a post that quotes (`ref=3`): second value 3 | R41 | 036, 049 |
| R42 | `R42-multiquote-form-cookie.html` | Composer with cookie `quoteshardwarefr-13-<post>=\|a\|b`: two `[quotemsg]` blocks prefilled | R42 | 049 |
| R45a | `R45a-new-topic-form.html` | New-topic form `/hfr/Discussions/nouveau_sujet.htm`: `sujet`, `toread1..5`, `subcat` select | R45 | 036, 048 |
| R45b | `R45b-new-mp-form.html` | New-MP form (`dest` prefilled), never submitted | R45 | 036, 048 |
| R46 | `R46-modo-alert-form.html` | Moderator alert form, GET only, never submitted | R46 | 036, 050 |
| R53a | `R53a-smiley-search-no-result.html` | Smiley search, no result: 40-byte text "Désolé, aucune réponse n'a été trouvée !" | R53 | 005, 025, 053 |
| R53b | `R53b-smiley-search-one-word.html` | One word: 657 smileys | R53 | 005, 025, 053 |
| R53c | `R53c-smiley-search-two-words.html` | Two words: 1010 smileys (words are OR-ed, not AND-ed) | R53 | 005, 025, 053 |
| R54 | `R54-smiley-wiki-detail-anon.html` | Smiley wiki detail page | R54 | 005, 053 |
| R55-p1 | `R55-p1-profile-edit-page1.html` | `/user/editprofil.php?page=1`: personal fields (redacted, birth date and gender unselected) | R55 | 005, 025, 043, 044 |
| R55-p3 | `R55-p3-profile-edit-page3.html` | Page 3: display settings incl. `topicpp` (posts per page) | R55 | 005, 025, 044 |
| R55-p5 | `R55-p5-profile-edit-page5.html` | Page 5: `hash_check` only form | R55 | 005, 025, 043, 044 |
| R55-p5u1 | `R55-p5u1-profile-edit-page5-avatar.html` | Page 5 as user1, an account with an avatar: avatar `mesdiscussions-<id>.jpg`, "Effacer votre avatar" (`clearimage.php?…&codehex=`, redacted), personal smileys `[:code]`…`[:code:5]`, favourite smileys | R55 | 005, 025, 043, 044 |
| R56a | `R56a-profile-operator-anon.html` | Public profile `/hfr/profil-<id>.htm` of user2, logged out: no avatar, no personal smiley, e-mail "Vous n'avez pas accès à cette information", "Statut" | R56 | 005, 027 |
| R56b | `R56b-profile-other-member-anon.html` | Public profile of another member (a post author of R26), logged out: avatar, 4 personal smileys, "Configuration matérielle" link, transactions | R56 | 005, 027 |
| R57a | `R57a-rest-categories.json` | REST categories (20) | R57 | 057 |
| R57b | `R57b-rest-category-topics-last.json` | REST last topics of cat 13 (25 per page) | R57 | 057 |
| R57c | `R57c-rest-topic.json` | REST one topic | R57 | 057 |
| R335a | `R335a-rest-bucket-participated.json` | REST flag bucket `topics/participated/` (global, grouped by category), logged in (user1): 2 groups of 1 topic, aliased by position so fixtures stay stable and carry no live data (kit README, REST flag buckets) | R57 | 057 |
| R335b | `R335b-rest-bucket-read.json` | The same for `topics/read/` | R57 | 057 |
| R335c | `R335c-rest-bucket-favorites.json` | The same for `topics/favorites/` | R57 | 057 |
| R335d | `R335d-rest-bucket-participated-page2-per-page5.json` | Global `participated` asked with `&page=2&results_per_page=5`: answered like page 1 (`page` 1, the hrefs echo the request); paging is not served | R57 | 057 |
| R335e | `R335e-rest-bucket-participated-category-page2-per-page5.json` | Flat form `categories/<cat>/topics/participated/&page=2&results_per_page=5` (category aliased `101` in the file and its URL): a `topic` list with no `links`, `page` echoed as 2, every entry returned (2 kept) | R57 | 057 |
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
| P03c | `P03c-favourites-after-addflag.html` | Favourites list with the flagged topic | P03 | 024 (rows aliased by position, re-run through the kit on the published page 2026-11-06: not re-captured) |
| P03d | `P03d-delflag-favourite-success.html` | `delflag.php?…&owntopic=3`: "Drapeau effacé avec succès" | P03 | 051 |
| P03e | `P03e-favourites-after-delflag-empty.html` | Favourites empty again (state restored) | P03 | 024 |
| P03f | `P03f-list-owntopic2-after-delflag.html` | Read list after delflag: the topic's read flag is gone too | P03 | 024, 051 (rows aliased by position, re-run through the kit on the published page 2026-11-06: not re-captured) |
| P03g | `P03g-favourites-two-rows.html` | `forum1f.php?owntopic=3` with two favourites: `form1` with marker index 2 (Run 6) | P03 | 024, 051 (rows aliased by position, re-run through the kit on the published page 2026-11-06: not re-captured) |
| P03h | `P03h-manageaction-delflags-browser-one-of-two.html` | Browser body of `P03g`'s `form1`, first row checked (meta `request_body`): "Favoris supprimés avec succès", refresh `/forum1f.php?config=hfr.inc&owntopic=3&new=0&nojs=0` | P03 | 051, 037 |
| P03i | `P03i-favourites-after-browser-delflags.html` | The list after `P03h`: only the unchecked row is left | P03 | 024, 051 (rows aliased by position, re-run through the kit on the published page 2026-11-06: not re-captured) |
| P03j | `P03j-manageaction-delflags-legacy-body.html` | Legacy body (no `owntopic`, marker index 1, one topic): "Drapeaux effacés avec succès", refresh `/` | P03 | 051, 037 |
| P03k | `P03k-favourites-three-rows.html` | Three favourites: `form1` with marker index 3 | P03 | 024, 051 (rows aliased by position, re-run through the kit on the published page 2026-11-06: not re-captured) |
| P03l | `P03l-manageaction-delflags-browser-three-rows.html` | Browser body, all three rows checked: same answer as `P03h` | P03 | 051, 037 |
| P03m | `P03m-topic-p1-logged-in-favourite.html` | `R21`'s topic page 1, logged in (user2), topic in the favourites: header `delflag` link with `favorisn.gif` | P03 | 030, 033, 051 |
| P03n | `P03n-delflag-owntopic0-success.html` | `delflag.php` with `owntopic=0` (the `P03m` link): "Drapeau effacé avec succès", refresh to the sub-forum list | P03 | 051, 037 |
| P03o | `P03o-delflag-again.html` | Same request again, no flag left: the same bytes as `P03n` | P03 | 051, 037 |
| P03p | `P03p-delflag-owntopic1-success.html` | `delflag.php` with `owntopic=1`: same sentence, refresh to the sub-forum list with `owntopic=1` | P03 | 051, 037 |
| P03q | `P03q-addflag-logged-out.html` | `addflag.php` GET without cookies: the same bytes as the logged-in success `P03a` | P03 | 051, 037 |
| R50a | `R50a-search-post-waiting-page.html` | Global search POST: "Votre recherche est en cours…", refresh to `GET /forum1.php?recherches=1&…&config=hfr.inc` | R50 | 005, 025, 046 |
| R50b | `R50b-search-results-no-cookie.html` | That GET without cookies: 50 rows, `post_cat_list` | R50, R51 | 005, 022, 046 |
| R50c | `R50c-search-no-result-no-cookie.html` | No result: `.hop` "Désolé, aucune réponse n'a été trouvée !" | R50 | 005, 046 |
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
| R61b | `R61b-public-reply-composer.html` | Reply composer of a public topic (cat 13, `#repondre_form` action), user2: same 43-field `hop` form as `R40a`, action `/bddpost.php?config=hfr.inc` | P01 | 036, 048 |
| W30 | `W30-public-reply-success.html` | Public reply, browser semantics: "Votre réponse a été postée avec succès !", refresh to **page 1** `…sujet_<post>_1.htm#bas` (the post landed on the last page, 30) | P01 | 048, 037 |
| R61d | `R61d-public-topic-last-page-own-post.html` | Last page with the own reply: edit link `message.php?…&cat=13&…&numreponse=<n>&page=30…`, quote link | P01 | 030, 031, 033, 048 |
| R62a | `R62a-public-edit-form-later-post.html` | Edit form of the own later post of a public topic: action `/bdd.php?config=hfr.inc`, hidden `sujet`, `stickold` `0`, delete label "Effacer ce message" | P01, R43 | 036, 048 |
| W31 | `W31-public-edit-success.html` | Public edit (no `delete` sent): "Votre message a été édité avec succès !", refresh `…sujet_<post>_<page>.htm#t<numreponse>` | P01 | 048, 037 |
| R62b | `R62b-public-edit-form-after-edit.html` | Same edit form after `W31`: stored text with the edit | P01 | 036, 048 |
| W32 | `W32-public-delete-post-success.html` | Public delete of the later post (`delete=1`): "Message effacé avec succès !", refresh `/hfr/<cat>/<sub>/sujet_<post>_<page>.htm` (no slug, no anchor) | P01 | 048, 037 |
| R61e | `R61e-public-topic-after-delete.html` | Same last page afterwards: the post is gone | P01 | 033, 048 |
| R63a | `R63a-public-own-topic-first-page.html` | Page 1 of a public topic started by user1 (**own topic**: topic and message ids, subject, slug, texts, related topics and dates replaced, see below) | P01 | 030, 033, 048 |
| R63b | `R63b-public-edit-form-first-post.html` | Edit form of the own topic's first post: action `/bdd.php?config=hfr.inc`, visible `sujet` (maxlength 70), `subcat` select, poll fields, "Effacer l'intégralité du sujet". Never submitted with `delete` | P01, R43 | 036, 048 |
| W34 | `W34-public-first-post-edit-success.html` | First-post edit (one line appended): "Votre message a été édité avec succès !", refresh `…sujet_<post>_1.htm#t<numreponse>` | P01 | 048, 037 |
| W35 | `W35-public-first-post-restore-success.html` | Same edit sending the original fields back: same answer; the stored text and subject were then byte-identical to the original | P01 | 048 |
| R63e | `R63e-public-own-topic-after-restore.html` | Page 1 afterwards (same replacements) | P01 | 033, 048 |
| W33 | `W33-public-reply-empty-body-rejected.html` | Public reply with an empty body: "Vous devez remplir tous les champs avant de poster ce message" (as `W17a`), nothing posted | P01, W17 | 037, 048 |
| R60a | `R60a-mpstorage-thread-first-post.html` | user1's MPStorage thread (subject `MP_NAME`) opened with the legacy read URL (`MPStorage.m:766`): one post, `div#para<numreponse>` > `p` holding the JSON document (`"` as `&#034;`, a `div` clear inside the `p`); the live document is the empty structure the legacy app creates (three empty sections, `sourceName` `iOS`, 568 bytes); JSON body kept, see Run 5 | R13, X8 | 038, 052 |
| R60b | `R60b-mpstorage-edit-form-first-post.html` | Edit form of that first post (toolbar `edit-in` link of R60a), GET only: `hop` form to `/bdd.php?config=hfr.inc`, `numreponse` of the first post, `sujet` = `MP_NAME`, `content_form` = the same JSON as R60a's rendered text, recipient row (aliased) | X8, E23 | 038, 052, 036 |
| R70a | `R70a-home-stale-session.html` | Home with a stale session (user2's `md_user`/`md_id`, wrong `md_passs`): 200, 1569 bytes (anonymized), `.hop` "Identifiants invalides !", `Refresh: 1; url=/unlog.php?config=hfr.inc`, no `Set-Cookie` | R01 | 044, 047, 092 |
| R70b | `R70b-favourites-owntopic1-stale-session.html` | `forum1f.php?owntopic=1`, same stale jar: the same bytes as `R70a` | R10 | 024, 092 |
| R70c | `R70c-profile-edit-page1-stale-session.html` | `editprofil.php?page=1`, same stale jar: the same bytes as `R70a` (no redirect, no `Set-Cookie`) | R55 | 044 |
| R70d | `R70d-profile-edit-page5-stale-session.html` | Page 5, same stale jar: the same bytes as `R70a` | R55 | 043, 044 |
| R71a | `R71a-profile-edit-page5-anon.html` | Page 5 without cookies: 200, `.hop` "Mot de passe incorrect !", `Refresh: 1; url=../login.php?config=hfr.inc` | R55 | 043, 044 |
| R71b | `R71b-profile-edit-page1-anon.html` | Page 1 without cookies: the same `.hop` as `R71a` | R55 | 044 |
| R72a | (meta only) | `GET /unlog.php?config=hfr.inc` (the `R70a` refresh target, no `codehex`) with a valid jar: 200, empty body, no `Set-Cookie` | — | 044 |
| R72b | `R72b-home-after-unlog-without-token.html` | Home with the same jar right after `R72a`: still logged in, the same cookie values | R03 | 044 |
| R73a | `R73a-favourites-owntopic1-two-categories.html` | `forum1f.php?owntopic=1` (user2): two categories, two rows (aliased by position), a closed topic (`lock.gif`) and a poll (`sondage.gif`), `favoris.gif`; re-captured 2026-11-06 | R10 | 024, 092 |
| R73b | `R73b-favourites-owntopic1-thirteen-categories.html` | `forum1f.php?owntopic=1` (user1): 13 categories, 88 rows (26 polls) aliased by position, `favoris.gif` on 84 rows and `flag1.gif` on 4, theme images under `images/defaut/`; re-captured 2026-11-06 | R10 | 024, 092 |
| R74 | (meta only) | Profile page 1 logged in (as `R55-p1`): `md_user` and `md_passs` each set twice, a value for `.hardware.fr` (+30 days) and `deleted` for `.forum.hardware.fr` (expired 1970), see its `note` | R55 | 043, 044 |
| W40 | `W40-public-new-topic-success.html` | New topic (Programmation › iOS, browser semantics): "Votre message a été posté avec succès !", refresh to the **category** list `/hfr/<cat>/liste_sujet-1.htm`, no topic id; sets `md_data` | E14 | 048, 037 |
| W41 | `W41-public-first-post-edit-add-poll-success.html` | First-post edit adding a poll (`have_sondage=1`, `textreponse0..2`, legacy semantics): "Votre message a été édité avec succès !", refresh `…sujet_<post>_1.htm#t<numreponse>` | E11, P01 | 048, 054 |
| R83 | `R83-public-own-topic-poll-form-logged-in.html` | The own topic after `W41`, user1, not voted: vote form as `R32b` (`sondage=2`), the author's own first post | R32 | 026, 054 |
| W42 | `W42-poll-vote-success.html` | Vote (`reponse=1`, `sondage_submit=Voter`, form order): link-less `.hop` "Votre vote a bien été pris en compte !", refresh `/hfr/<cat>/<sub>/sujet_<post>_1.htm` (no slug), no "avec succès" | E10 | 037, 054 |
| W43 | `W43-poll-vote-already-voted.html` | Same body again: `.hop` "Désolé, vous avez déjà voté !" + back link, no refresh | E10 | 037, 054 |
| W44 | `W44-poll-vote-linked-account-already-voted.html` | Same body from user2 (linked account, multipseudo notice on its page): the same sentence | E10 | 037, 054 |
| W45 | `W45-poll-vote-logged-out.html` | Vote POST without cookies on an operator poll: the answer of `W42` (one observation); proves nothing about the session (#137) | W45 | 037, 054 |
| W46 | `W46-modo-alert-success.html` | Moderator alert submitted (user2, browser semantics): `.hop` "Un message a été envoyé avec succès aux modérateurs" **+ back link**, no refresh | R46 | 037, 050 |
| R88 | `R88-modo-alert-already-reported.html` | Alert page of the message just reported: `.hop` "Votre demande de modération sur ce message n'est pas encore traitée." + back link, no form | R46 | 037, 050 |
| W47 | `W47-modo-alert-logged-out-rejected.html` | Alert body without cookies, empty `hash_check`: `.hop` "Vous devez être identifié pour prévenir les modérateurs" + back link | R46, W17 | 037, 050 |
| R89 | `R89-modo-alert-page-logged-out.html` | Alert page without cookies: the same `.hop` as `W47` | R46 | 037, 050 |
| W49 | `W49-public-first-post-delete-topic-success.html` | First-post delete (`delete=1`, legacy semantics): "Message effacé avec succès !", refresh to the **sub-category** list `/hfr/<cat>/<sub>/liste_sujet-1.htm` | P01, X1 | 048, 037 |
| R92 | `R92-topic-after-first-post-delete-404.html` | The topic URL afterwards: **404**, `.hop` "Désolé, ce sujet n'existe pas" + back link | R20 | 030, 048 |
| U01 | `U01-rehost-upload-success.json` | `img3.super-h.fr` upload, legacy key: 200 JSON "file uploaded", `image.url`, `image.thumb.url` (`.th.`), `image.medium` all `null`, numbers as numbers; delete fields redacted | — | 056 |
| U02 | `U02-rehost-upload-wrong-key.json` | Same upload with a wrong key: 400 JSON "Invalid API key." code 100 | — | 056 |
| W61 | `W61-mp-create-bbcode-success.html` | New MP `fixture-test-2` (user2 → user1) whose first post holds b, i, u, strike, spoiler, quote, url (both forms), img, fixed, code, cpp, color, list, nested and unclosed tags, and raw `<b>`/`&`/`"`: "Votre message a été posté avec succès !", refresh to the MP list | W10 | 048, 097 |
| R95c | `R95c-mp-edit-form-bbcode-source.html` | Edit form of `W61` (owner): `content_form` = the CRLF source sent, byte for byte; the "Vue Rapide" review below holds the rendered post, `[img]` written as a link there | R43 | 097, 036 |
| R95d | `R95d-apercu-bbcode-preview.html` | `POST /apercu.php` (`hash_check`, `apercu_contenu` = the `W61` source, `apercu_smiley=0`, `config`): 200, the rendered BBCode in `body.reponse`, line breaks written `\r<br />` (the CR kept) | — | 097, 152 |
| W62 | `W62-mp-reply-bmp-emoji-success.html` | Reply (user1) with U+2764, U+2764 U+FE0F, U+2714, U+2605 and a lone U+FE0F: success | W12 | 048, 096, 151 |
| R95f | `R95f-mp-edit-form-bmp-emoji-source.html` | Edit form of `W62` (user1): `content_form` keeps every BMP emoji and both U+FE0F unchanged | R43, X9 | 096, 151, 036 |
| R95h | `R95h-apercu-bmp-emoji-preview.html` | Preview of the `W62` source: the emoji and U+FE0F written as UTF-8 characters, no `<img>` | — | 096, 151, 097 |
| R95g | `R95g-mp-composer-multiquote-cookie-escaped.html` | MP composer (user2) with `quoteshardwarefr-prive-<post>=%7C<a>%7C<b>` (the site JS's `escape()`d form): two `[quotemsg=<n>,1,<id>]` blocks prefilled, as `R47c` with the raw `\|` form | W14 | 049, 086 |
| W63 | `W63-mp-reply-multiquote-cookie-deleted.html` | Reply posted with that prefill and the cookie sent: success; the answer sets `quoteshardwarefr-prive-<post>=deleted; expires=Thu, 01-Jan-1970 00:00:01 GMT; path=/`, **no `Domain`** (host-only); `W62`, sent without the cookie, carries the same header | W14 | 049, 086 |
| W64x | `W64x-mp-thread-delete-bad-token-rejected.html` | Thread delete, legacy body, wrong `hash_check`: the 99-byte plain text of `W17b`, nothing deleted | X1 | 094, 037 |
| W64 | `W64-mp-thread-delete-owner-success.html` | Thread delete by the owner (`topic0=<post>`, `valuecat0=prive`, `valueforum0=hardwarefr`, `topic1=-1`, `topic_statusno1=-1`, `action_reaction=valid_eff_prive`, `type_page=forum1`): link-less `.hop` "Action effectuée avec succès", refresh 1 s to `/forum1.php?config=hfr.inc&cat=prive&page=1&subcat=&…`, no cookie set | X1 | 094, 037 |
| R95j | `R95j-mp-list-owner-after-thread-delete.html` | Owner's MP list afterwards: no row, no pager | R13 | 094, 023 |
| R95k | `R95k-mp-list-recipient-after-thread-delete.html` | Recipient's list (user1) afterwards: the thread is still there (row 1); 50 rows, 7 pages; the MPStorage row is row 42 of page 1 | R13, R14 | 094, 023, 038 |
| R96c | `R96c-mp-thread-owner-after-thread-delete.html` | Thread URL for the owner afterwards: 200, `.hop` "Ce message ne vous est pas destiné, désolé" (as `RA5`) | X1 | 094, 030 |
| W65 | `W65-mp-thread-delete-recipient-success.html` | The recipient deletes it too (same body, its own `hash_check`): the same `.hop` | X1 | 094, 037 |
| R96d | `R96d-mp-thread-recipient-after-thread-delete.html` | Thread URL for the recipient afterwards: the same "pas destiné" `.hop` | X1 | 094, 030 |
| R96a | `R96a-mp-list-past-last-page.html` | user1's MP list `page=8` of 7, with `MPStorage.m:694`'s query: 200, no redirect, no `.hop`, header row and no topic row; title "… - Page : 8"; the pager lists pages 1 to 7 as links (no current page), "Page Précédente" links page 7, no "Page Suivante" link | R14 | 023, 038, 047, 126 |
| R96b | `R96b-mpstorage-thread-other-account-not-addressed.html` | user2 opens user1's MPStorage thread with legacy's read URL (`MPStorage.m:766`, as `R60a`): 200, the "pas destiné" `.hop` legacy's `parseMPStorage` checks (`MPStorage.m:837`) | R60 | 038 |
| W70 | `W70-mp-create-group-success.html` | New MP to two recipients (#336, 2026-11-05): user1 posts `dest=<user2>,<third member>` (comma, no space), a neutral subject and body, to `bddpost.php`: "Votre message a été posté avec succès !", refresh to the MP list | N07 | 058 |
| R123k | `R123k-new-mp-form-recipients-comma-hint.html` | The new-MP form as the list link opens it (`dest=` empty, user1): the `dest` hint reads "Entrez le(s) pseudo(s) du ou des destinataires, séparés par des virgules." | R45 | 058, 036 |
| R123a | `R123a-mp-list-group-owner.html` | user1's MP list right after `W70`: the group row (`Interlocuteurs multiples` span with the roster as `title`, `[non lu]` "pas été lu par" with lower-cased names) and 12 older group threads (13 group rows in all) | N07, R13 | 058, 023, 171 |
| R123b | `R123b-mp-thread-group-owner.html` | The group thread seen by its owner (one message, no roster on the page) | N07 | 058, 030 |
| R123c | `R123c-mp-reply-composer-group-owner-newdest.html` | The owner's `message.php` reply form: the extra "Destinataires" row with `newdest` ("a, b", the members other than the owner) | N07, R47 | 058, 036 |
| R123d | `R123d-mp-thread-group-member.html` | The same thread seen by user2, a non-owner member (no roster) | N07 | 058, 030 |
| R123e | `R123e-mp-reply-composer-group-member-no-roster.html` | The member's reply form: no "Destinataires" row, no `newdest` (the roster is not read-only text here) | N07, R47 | 058, 036 |
| R123f | `R123f-mp-list-group-member.html` | user2's MP list with the group row (roster in the span `title`, only the third member left in "pas été lu par") | N07, R13 | 058, 023, 171 |
| R123g | `R123g-favourites-owntopic1-empty-after-delflag.html` | user2's `forum1f.php?owntopic=1` with nothing flagged (operator-run capture, #109): the list body with title "Vos sujets", no `.hop`, no topic row, marker `topic0`, the "Discussions" header and the placeholder row "Aucun nouveau message" | R73a, R12 | 024, 092 |
| W71 | `W71-mp-group-reply-roster-unchanged-old-thread.html` | Owner's reply on the #336 group thread, `newdest` as served (#507, 2026-11-06): "Votre réponse a été postée avec succès !", refresh to the thread `#bas` | R123c | 058, 048 |
| W72 | `W72-mp-group-reply-remove-member-to-two-person.html` | Same thread, owner's reply with `newdest` reduced to one member (user2 removed): the same success sentence; it leaves a two-person thread | R123c | 058 |
| R124 | `R124-mp-reply-composer-after-removal-no-newdest.html` | The owner's composer of that thread afterwards: no `newdest`, the row reads "Destinataire" with the one member as plain text | W72 | 058, 036 |
| R125 | `R125-mp-thread-after-removal-system-message.html` | The thread after `W72`: the reply, then a post by "Modération" ("<member> a été retiré de la conversation") (the "Modération" author and the quoted text were read on the raw page; the published file aliases the author and replaces the text, so they cannot be tested from it) | W72 | 058, 030 |
| R126 | `R126-mp-list-removed-member-no-row.html` | The removed member's MP list: no row for the thread | W72 | 058, 023 |
| W73 | `W73-mp-create-group-three-recipients-success.html` | New group MP to three recipients, `dest` comma-separated (#507): "Votre message a été posté avec succès !", refresh to the MP list | R123k, W70 | 058 |
| R127 | `R127-mp-reply-composer-group-owner-three-members.html` | The new group's owner composer: `newdest` with three members, in HFR's order (not the `dest` order) | W73 | 058, 036 |
| W74 | `W74-mp-group-reply-remove-member-success.html` | Owner's reply with `newdest` without user2 (two others kept): success sentence, refresh to the thread | R127 | 058, 048 |
| R128 | `R128-mp-reply-composer-group-owner-two-members.html` | The owner's composer after `W74`: `newdest` still served, two members | W74 | 058, 036 |
| R129 | `R129-mp-thread-group-after-removal-system-message.html` | The thread after `W74`: the reply, then a "Modération" post "<member> a été retiré de la conversation" (a post of its own, with its own message id) (the "Modération" author and the quoted text were read on the raw page; the published file aliases the author and replaces the text, so they cannot be tested from it) | W74 | 058, 030 |
| R130 | `R130-mp-list-group-removed-member-no-row.html` | user2's MP list after the removal: no row for the thread | W74 | 058, 023 |
| R131 | `R131-mp-thread-removed-member-not-addressed.html` | user2's GET of the thread after the removal: 200, "Ce message ne vous est pas destiné, désolé" | W74 | 058, 030 |
| W75 | `W75-mp-group-reply-add-member-success.html` | Owner's reply with user2 put back in `newdest`: success sentence | R128 | 058, 048 |
| R132 | `R132-mp-reply-composer-group-owner-roster-restored.html` | The owner's composer after `W75`: the roster is the original one (`R127`), same order | W75 | 058, 036 |
| R133 | `R133-mp-thread-group-after-add-system-message.html` | The owner's thread after `W75`: the reply, then a "Modération" post "<member> a été ajouté à la conversation" (the "Modération" author and the quoted text were read on the raw page; the published file aliases the author and replaces the text, so they cannot be tested from it) | W75 | 058, 030 |
| R134 | `R134-mp-thread-group-added-member-view.html` | The same thread as the re-added member sees it: every earlier post, including both system posts | W75 | 058, 030 |
| R135 | `R135-mp-list-group-added-member-row.html` | The re-added member's MP list: the group row is back (roster in the span `title`, "pas été lu par" tooltip) | W75 | 058, 023 |
| W76 | `W76-mp-group-reply-unknown-pseudo-refused.html` | Owner's reply with an unknown pseudo (random letters) appended to `newdest`: refusal "Désolé, le pseudo suivant n'existe pas : <pseudo>", nothing posted, no refresh | R135 | 058, 037 |
| R136 | `R136-mp-reply-composer-group-owner-after-refusal.html` | The owner's composer after `W76`: roster unchanged | W76 | 058, 036 |
| W77 | `W77-mp-group-reply-empty-newdest-success.html` | Owner's reply with `newdest=` empty: not refused, the same success sentence | R136 | 058, 048 |
| R137 | `R137-mp-reply-composer-group-owner-after-empty-newdest.html` | The owner's composer after `W77`: roster unchanged (three members) | W77 | 058, 036 |
| W78 | `W78-mp-group-reply-member-unserved-newdest-success.html` | A non-owner member's reply carrying a `newdest` (the owner's roster) its form did not serve, appended after the form's fields: success sentence | R138 | 058, 048 |
| R138 | `R138-mp-reply-composer-group-member-no-roster.html` | That member's composer, as served before `W78`: no `newdest` | W73 | 058, 036 |
| R139 | `R139-mp-reply-composer-group-owner-after-member-newdest.html` | The owner's composer after `W78`: roster unchanged | W78 | 058, 036 |
| R140 | `R140-mp-thread-group-after-all-steps.html` | The new group's thread at the end: no post for the refused `W76`, no system post after `W77` or `W78`, none for the unchanged roster | W71-W78 | 058, 030 |
| (oracles) | `../M2-writes/` | Legacy oracles of `R123a`-`R123g`, `R123k`, `R124`-`R140` and `W71`-`W78` (`run-oracle.sh`, legacy `2440d79`): `mp` for the lists, `favorites` (`R123g`), `topic` for `R123b`/`R123d`, `form` (`reply`, `mp`) for `R123c`/`R123e`/`R123k` and the composers `R124`, `R127`, `R128`, `R132`, `R136`-`R139`, `response` (`reply`) for `W71`-`W78`; own folder and map | R123a-R123g, R123k, R124-R140, W71-W78 | 058, 023, 024, 030, 036 |
| R117a | `R117a-forum-list-header-badge-n7.html` | user1's `/hfr/OSAlternatifs/liste_sujet-200.htm` (#117, 2026-11-06; a deep page, no flagged row): the header badge in `table.none` reads "Vous avez 7 nouveaux messages privés" in `a.red` linking the MP list; | R02, R13 | 023 |
| W130 | `W130-mp-create-leading-newline-success.html` | New MP user1 → user2 `fixture-test-3` (#130) whose body is `\r\n` + a word (meta `request_body` `content_form=%0D%0A…`): "Votre message a été posté avec succès !", refresh to the MP list | R45, W10 | 036, 048 |
| R130a | `R130a-mp-thread-leading-newline.html` | The thread of `W130` for its owner (body replaced by `--private`; on the raw page it renders `<p>\r<br />word`, a normal message `<p>word`) | R13, R43 | 036, 030 |
| R130b | `R130b-mp-edit-form-leading-newline.html` | Edit form of that message: the textarea holds the word **without** the leading break (HFR trims it itself); never submitted | R43 | 036, 048 |
| R130c | `R130c-mp-quote-form-leading-newline.html` | Quote form of that message: `[quotemsg=<cited>,1,<id>]\r\nword[/quotemsg]\n`, the leading break kept | R47 | 036, 049 |
| W137a | `W137a-mp-mark-unread-logged-out.html` | `nonlu.php` of the `W130` thread (link as the page serves it) sent **without any cookie**, no redirect followed: 200 `.hop` "Ce message ne vous est pas destiné, désolé" + back link, no refresh, no cookie set; byte for byte `R96c` (#137) | W18 | 058, 037, 044 |
| W137b | `W137b-mp-mark-unread-logged-out-again.html` | The same request again: identical to `W137a` to the byte | W18 | 058 |
| R298a | `R298a-topic-id-form-1711-logged-out.html` | Id form `forum2.php?config=hfr.inc&cat=25&post=1711&page=1` (an Apple topic), logged out: one 301 to the canonical `/hfr/apple/<slug>-sujet_1711_1.htm`, 200 | R5 | 095, 120 |
| R298b | `R298b-topic-id-form-1711-logged-in.html` | The same, logged in (user2): same 301 and final URL, 200, cookies refreshed | R5 | 095, 120 |
| R298c | `R298c-topic-id-form-subcat-8811-logged-out.html` | Id form with `subcat=528&post=8811`: one 301 to `/hfr/apple/<sub-category>/<slug>-sujet_8811_1.htm`, 200, logged out | R5 | 095, 120 |
| R298d | `R298d-topic-id-form-subcat-8811-logged-in.html` | The same, logged in (user2) | R5 | 095, 120 |
| R298e | `R298e-topic-stale-slug-1711-logged-out.html` | The stale slug of legacy `HFRDebugViewController.m:23` (`/hfr/apple/officiel-application-hfr-sujet_1711_1.htm`), logged out: 301 to the current slug, 200, same body id, final URL and message count as `R298a` | R5 | 095, 120 |
| R298f | (meta only) | The stale slug, logged in (user2): the same 301 and final URL, same body id and message count as `R298b` (body not re-published) | R5 | 095, 120 |
| W131 | `W131-mp-thread-delete-owner-unread-recipient-success.html` | user1 deletes `W130`'s thread with `W64`'s body (clean-up): link-less `.hop` "Action effectuée avec succès" | X1 | 094, 037 |
| R130d | `R130d-mp-thread-recipient-after-sender-delete-unread.html` | The thread URL for user2 afterwards: the "pas destiné" `.hop` (user2 had not opened it) | X1 | 094, 030 |
| R130e | `R130e-mp-list-recipient-after-sender-delete-unread.html` | user2's MP list afterwards: no row ("Aucun message posté"), so no second delete was sent | X1, R13 | 094, 023 |
| (oracles) | `../M2-misc/` | Legacy oracles (`run-oracle.sh`, legacy `2440d79`): `topics` for `R117a` (`needToUpdateMP` true, `sNewMPNumber` 7), `topic` for `R130a`, `form` (`edit`, `quote`) for `R130b`/`R130c`, `response` (`reply`) for `W130`; own folder and map. `W131`, `W137a`, `W137b`, `R130d`, `R130e` have no legacy parser to run | R117a, R130a-R130e, W130 | 023, 036 |
| T01 | `T01-aq-rss-feed.xml` | `aq.super-h.fr/rss.php`: 200 `application/rss+xml;charset=utf-8`, 25 items; each description is CDATA HTML (topic title in `<b>`, count, one `<li>` per reporter "[le <date> à <time>] <b>X (initiateur)</b> : comment"); `&quot;`, `&#039;`, `&amp;` in titles and descriptions; legacy oracle `LOT-028/T01.oracle.json` | P08 | 028, 055 |
| T02 | `T02-aq-alerts-by-topic.xml` | `aq.super-h.fr/api/getAlertesByTopic.php?topic_id=<topic>` (a topic of `T01`): 200 `text/xml;charset=UTF-8`, `<alertes>` of 123 `<alerte id nom pseudoInitiateur date postsIds/>` (date `dd-mm-yyyy`), `&quot;` and `&amp;` in attributes | P08 | 028, 055 |
| T50 | `T50-aq-create-answer.txt` | `POST https://aq.super-h.fr/api/addAlerte.php` (legacy `MessagesView.swift:340-399`), operator-approved write on the operator's own topic, first post, #531: 200 `text/plain;charset=UTF-8`, body `1` (no newline), no cookie, no redirect. Request body (meta): `alerte_qualitay_id=-1`, `nom`, `topic_id`, `topic_titre`, `pseudo`, `post_id`, `post_url` (permalink with `#t<post>`), `commentaire` = `post de <author>`. The topic is the operator's own: ids, title, slug and dates aliased by `own_topics` logic (`topic_id=9900001`, `post_id=9910000001`). The alert title (`nom`) is a placeholder, and the permalink's category and sub-category directories are aliased (`own-category/own-subcategory`). A refusal is **not captured** (not approved) | E §6 | 055, 071, 134 |
| T51 | `T51-aq-alerts-after-create.xml` | `getAlertesByTopic.php?topic_id=<own topic>` read right after `T50`: 200 `text/xml;charset=UTF-8`, one `<alerte id nom pseudoInitiateur date postsIds/>`, the new alert (`postsIds` = the reported message, `pseudoInitiateur` = the `pseudo` sent, `date` the day); alert id, topic and message aliased, title masked as in `T02` | E §6 | 055, 071, 134 |
| R97a | `R97a-apple-app-site-association.json` | `/.well-known/apple-app-site-association`: 200 `application/json`, old-format `applinks` with one App ID and paths `/`, `/hfr/*`, `/forum2.php*`, the same App ID in `webcredentials` | — | 095, FEAT-020 |
| R98a | `R98a-hardware-fr-personal-data-page.html` | `www.hardware.fr/html/donnees_personnelles/` (footer link of every forum page): ISO-8859-1, GDPR rights incl. erasure, exercised by e-mail (address redacted) or by post to the DPO | — | 157 |
| T10 | meta only | `https://nsa34.casimages.com/…jpg`: no DNS answer (status 0) | — | 056, 083 |
| T11, T11h | meta only | `yelims.free.fr` image: `https` TCP refused (status 0); `http` 200 `image/gif` | — | 056, 083 |
| T12 | meta only | `https://img15.hostingpics.net/…jpg`: no DNS answer | — | 056, 083 |
| T13 | meta only | `https://si1.photorapide.com/…jpg`: 200 `image/jpeg` | — | 056, 083 |
| T14, T14h | meta only | `www.camif.fr` image: `https` 404 `text/html`; `http` 301 → the `https` URL, then 404 | — | 056, 083 |
| T15 | meta only | `https://bibi.hn.org/…`: no DNS answer | — | 056, 083 |
| T20, T21, T24 | meta only | `https://reho.st/`: 403 `text/html` without `Referer`; 200 `text/html`, empty body, with `Referer: https://forum.hardware.fr/` or `https://forum.hardware.fr` | E26 | 056, 083, 109 |
| T22, T23 | meta only | `https://reho.st/self/abc123.jpg` (legacy test path, no such image): 403 without `Referer`, 200 empty `text/html` with it | E26 | 056, 083, 109 |
| R122a | `R122a-topic-locked-logged-in.html` | The locked topic of `R31` seen by user2 (#122, 2026-11-05): 200, no `#repondre_form`, no `.hop`, no bottom answer link; the per-message quote links (`quote.gif`, `quote+.gif`/`quote-.gif`) are still there; header flag link `delflag` with `flagn0.gif` | R31 | 033, 031, 113 |
| R122c | `R122c-topic-search-filter-checked.html` | Intra-topic search result with the **filter** box checked: a plain GET of the `R52a` target plus `&filter=1` (user2): 200, only the 31 messages that contain the word (one page, no pager), `<input name="filter" … checked="checked">`, `word` prefilled, `currentnum` present without value, no `dep`/`firstnum` field | R52 | 033, 093, 113 |
| R122d | `R122d-topic-search-word-no-filter.html` | The same GET without `filter`: a normal page 1 (40 messages, pager), `word` prefilled, `filter` unchecked | R52 | 033, 113 |
| R121a | `R121a-mp-list-logged-out.html` | `forum1.php?config=hfr.inc&cat=prive&page=1` without cookies: 200, bare `<body>` with the `.hop` "Désolé, vous ne faites pas partie des membres ayant accès à cette catégorie" and a back link; no list | R13 | 022, 023 |
| R121b | `R121b-search-all-categories-first-category.html` | Global search with an empty `cat` ("Toutes les catégories", cookie-less GET of the `R50b` URL): **302** to `forum1.php?config=hfr.inc&cat=<first category with a hit>&post_cat_list=\|14*hfr\|5*hfr\|…&…&searchall=1`; the page lists that category's hits (1 row) under a form "Le moteur de recherche a trouvé des résultats dans les catégories suivantes" with a `cat` select | R50 | 022, 046, 115 |
| R121c | `R121c-search-all-categories-pivot-category-5.html` | The same results for another category of the pivot (`cat=5`, same `post_cat_list`, `searchall=1`): 4 rows, the pivot form again | R50 | 022, 046, 115 |
| R121d | `R121d-search-form-page.html` | `search.php?config=hardwarefr.inc&cat=13&subcat=0` without cookies: the search form (POST `/search.php?config=hfr.inc`), `cat` select whose first option is "Toutes les catégories" with the **empty** value | S1 | 046, 115 |
| R121e | `R121e-list-cat22-p1-logged-in.html` | Category list page 1 logged in (user1, 301 to the canonical `liste_sujet-1.htm`): 53 rows (3 sticky), 6 with a flag link in `sujetCase5` (4 `flag0.gif`, 2 `favoris.gif`) and 47 with the empty cell, 24 single-page topics; every row is aliased by position (rewritten link form, slug included, [kit README](../../../../../tooling/fixtures/README.md#list-rows)) | R04 | 022, 024, 092 |
| R121f | `R121f-list-cat32-single-page-anon.html` | List of category 32 (Intelligence Artificielle), anonymous: 39 rows (1 sticky), a single page (no "Page Suivante") | R04 | 022 |
| (oracles) | `../M2-readonly/` | Legacy oracles of `R121a`, `R121b`, `R121c`, `R121e`, `R121f`, `R122a`, `R122c` and `R122d` (`run-oracle.sh`, legacy `2440d79`), in their own folder and map: the LOT-002/LOT-003 guard tests list every case of their maps, so wiring these into a differential test is a follow-up | — | 022, 023, 033 |
| T30, T31 | meta only | A real `reho.st` image (`https://reho.st/preview/self/<hash>.jpg`, cookie-less, #134): **403** `text/html` (nginx) without `Referer`; **200** `image/jpeg` (134 kB) with `Referer: https://forum.hardware.fr/` | E26 | 056, 083, 109 |
| T32, T33 | meta only | The same for an `http://reho.st/self/<hash>.jpg` image: 403 without `Referer`, 200 `image/jpeg` with it; no redirect to https | E26 | 056, 083, 109 |
| T40 | `T40-giphy-search.json` | Giphy REST `GET https://api.giphy.com/v1/gifs/search?q=hello&limit=3&offset=0&rating=r&lang=en&api_key=<key>` (source: Giphy's public API reference, developers.giphy.com/docs/api/endpoint; legacy has no REST call, #175), 2026-11-06, key stripped from URL and body (the body never held it): 200 `application/json`, `{data, meta, pagination}`; `meta` = `status`, `msg`, `response_id`; `pagination` = `total_count` 500, `count` 3, `offset` 0; each `data[]` item: `type` `gif`, `id`, `url`, `slug`, `title`, `rating` (`g` for all three although `rating=r` asked: it is a ceiling), `username` (empty when no channel), `alt_text`, `analytics_response_payload`, and `images` with 23 renditions (`original`, `fixed_height`, `fixed_width_small`, `preview_gif`, `original_mp4`…): `url`, `width`/`height`/`size` as **strings**, `mp4`/`webp` variants on the main ones; media URLs carry the tracking query `cid=<8 hex><response_id>&ep=v1_gifs_search&rid=giphy.gif&ct=g`, where the 8-hex prefix is derived from the API key and is replaced by `00000000` everywhere, including inside the Base64 `e=` values of `analytics_response_payload` and the `onload`/`onclick`/`onsent` URLs (decoded, replaced, re-encoded; rescanned decoded); in the `analytics.onload, onclick, onsent` URLs the whole `analytics_response_payload` query value is replaced by `REDACTED` (its percent-encoded Base64 holds the same prefix and no code needs it); `trending_datetime` is `0000-00-00 00:00:00` on one item. Anonymization: channel names and the `user` object of an item replaced (`channel`, `redacted`) | E §6 | 098, 155, 071 |
| T41 | `T41-giphy-trending.json` | `GET /v1/gifs/trending?limit=3&offset=0&rating=r&api_key=<key>`, same day: 200, same envelope (`total_count` 170), same item shape with `ep=v1_gifs_trending`, plus a `user` object (channel profile fields, all replaced by `redacted`; `is_verified` kept) on items that have a channel; `trending_datetime` set (`0000-00-00 00:00:00` on one item), the `cid` prefix replaced as in `T40` | E §6 | 098, 155, 071 |
| R601a | `R601a-profile-edit-page5-personal-smileys.html` | `/user/editprofil.php?config=hfr.inc&page=5` (user1): row "Smilies persos", 6 codes and images, then the link `uploadsmil.php?config=hfr.inc` "Gérer ses smilies personnalisés" | R55 | 025, 104 |
| R601b | `R601b-smiley-upload-page-owner.html` | `/user/uploadsmil.php?config=hfr.inc` (user1): `body#unique__user_page__manage_picture`, 11 slots `[:code]`, `[:code:1]`…`[:code:10]`, 6 with their image, 5 with a file input, one `keyword<N>` input per slot (values replaced); no pagination; the form is never sent | — | 104 |
| R601c | `R601c-smiley-upload-page-no-smiley.html` | The same page for user2, no personal smiley: the 11 slots with a file input, no `/images/perso/` image | — | 104 |
| R601d | meta only | The same page without cookies: 200 `text/html`, no redirect, no cookie set (empty body: run observation, a meta keeps no size) | — | 104 |
| R603a | `R603a-list-cat13-owntopic1.html` | `forum1.php?…&cat=13&page=1&subcat=&…&owntopic=1…` (user1, the header link form of `R10`): 200 in place, 57 rows: 43 `favoris.gif`, 1 `flag1.gif`, 13 with an empty flag cell (all `closed.gif` "Off"); pager `1` alone; rows aliased by position (see R08-2) | R08 | 022, 024 |
| R603b | `R603b-list-cat13-owntopic3.html` | The same with `owntopic=3`: 56 rows, 43 `favoris.gif`, 13 with an empty flag cell (all "Off"); pager `1` alone | R08 | 022, 024 |
| R603c | `R603c-list-cat13-owntopic3-page2.html` | `page=2` of `R603b`: 200 in place, 56 rows, `<title>` with "Page : 2", pager `1` as a cryptlink to page 1 and the current page not printed, "Page Suivante" disabled, "Page Précédente" a cryptlink to page 1. Run observation: the same topics in the same order as `R603b` (row aliases cannot show it) | R08 | 022, 167 |
| R603d | `R603d-list-subcat-owntopic3.html` | `owntopic=3` with `subcat=<s>`: 200 in place, 14 rows (12 `favoris.gif`, 2 with an empty flag cell), `<title>` "<sub-forum> - <category> - FORUM HardWare.fr", pager `1` alone | R08 | 022, 024 |
| R603e | `R603e-favourites-owntopic2.html` | `forum1f.php?…&owntopic=2&new=0&nojs=0` (user2): title "Vos sujets", 3 category headers linking `owntopic=2`, 5 topic rows, one sticky, all `flag0.gif`, and under the second header no topic, only the row "Aucun nouveau message" | R10 | 024 |
| R603f | `R603f-rest-bucket-read-category.json` | REST `read` bucket of one category (flat shape), 2 topics kept (kit README "REST flag buckets"); `tns3` can be absent | E1 | 057 |

## Not captured

| Rows | Why |
|---|---|
| MPStorage row on page 2 or later (#333) | Not reachable on the kit's accounts: user1's storage row is row 42 of 50 on page 1 (`R95k`); pushing it down takes about 9 newer conversations, and HFR allows one new MP per account per 60 minutes (`W11x`). user2 has no storage thread. |
| Thread pages of `fixture-test-2` (run 9) | Captured, not published: `--private` replaces their bodies; the render is published as the `/apercu.php` previews `R95d`, `R95h`. The site scripts read for the cookie and preview code (`forum2.js`, `editPost.js`, `message.js`) are not committed. |
| `forum1f.php?owntopic=0` (`new=0` and `new=1`, run 14) | Captured, not published: rows with live public titles, no filter of the account. What they show is in HFR-PROTOCOL `### Smiley page and filtered lists` as a run observation. |
| `owntopic=2` of cat 13, pages 1-3, `owntopic=1` of the `R603d` sub-forum, the `forum1f.php` `owntopic=1\|3` of user1, `owntopic=2` of user1 (run 14) | Captured, not published: 0.5 to 1.8 MB for `owntopic=2`, the others repeat a published shape; compared on the raw files only (HFR-PROTOCOL, labelled run observations). |
| W02 | Dropped: W01's refusal already gives the failure page; a second failed login was not worth the lockout risk. |
| R63c, R63d | Captured, not published: the own topic's edit form after the edit and after the restore, read back only to verify the restore byte for byte (R63d equals R63b apart from the connected-users count). |
| A second throwaway thread | HFR allows one new topic per 60 minutes (W11x); everything ran in one thread. |
| R34, R51, R58 | Dropped per the checklist (R51 covered by R50b, R58 by R08-2). |
| R33, poll voted by the account itself without the multipseudo notice | Searched, not found: four poll topics of a `forum1f.php?owntopic=1` list were opened page 1; one is R33b (with the multipseudo notice, also for user2), the three others still offer the vote form. A plain "already voted" page would need a vote (P05, out of scope): synthetic per checklist §C N06 if a lot needs it. |
| X10 cookie-less multi-quote | Out of the approved scope or not needed. |
| A cookie-less poll vote and the poll author's results view (run 8) | Captured, not published: held for an operator decision (see the run 8 PR). |
| A reply to a locked topic, a ban refusal (run 8) | The locked topic's composer is served (200) but its POST was not sent (not an operator topic); no banned account. |
| oldcitation, Streamable/Dailymotion/Twitch | Not present on the pages picked; synthetic or a later capture. (`reho.st` images: `T30`-`T33`.) |
| AQ comment with an entity (#438) | None in the live feed of run 10 (`T01`); an entity in a pseudo cannot survive the alias. |
| MPStorage document with other clients' namespaces, member pseudos (blacklist), near the 64 KiB cap or with a non-BMP character | None exists in the kit's accounts: user1's document is the empty legacy structure (R60a/R60b), user2 has no storage thread (R13a). Producing one needs a write to a document shared with the user's other clients: out of scope (pending capture [#272](https://github.com/ezzz/HFRnow/issues/272)). |
| Rare list rows (#121): a `sujetCase3` with a second link outside search results, reply counts with separators, a row without last-post link or without `<b>` author, a pager with a non-cryptlink "Page Suivante" | Searched, not found (2026-11-05): page 1 of 20 category lists (anonymous, plus `R121e` logged in) and the three global-search pages hold none of them: every row has its last-post link and author, counts are bare digits, the pager link is a cryptlink. Stays pending capture. |
| A message whose quote or edit link is printed in clear instead of `md_noclass_cryptlink` (#274) | Not seen in any page of the corpus (`R122a`-`R122d` included: 610 quote and 17 edit toolbar images, all inside `md_noclass_cryptlink` spans, 2026-11-05 scan); the multi-quote `quote+.gif` link and the "Edition rapide" link are plain `<a href>` but sit beside them (`R63a`). May not exist on today's HFR. |

## Legacy on-device samples (#347, for LOT-067 / #92)

Not HFR captures: the bytes the legacy app (`2440d79`) writes in its five small on-device stores, produced by the real legacy
code on synthetic data (`tooling/legacy-oracle/run-oracle.sh -s DIR`, exporter `OracleStores` in `hfrnow.patch`), in
`tooling/legacy-oracle/samples/legacy-stores/`. No HFR request, no account. Dates are fixed instants (2024-01-01 + offsets, the legacy code
stamps `Date()`); `defaults-export-typical.plist` is the real `defaults export` of the host app's domain restricted to the two keys.

| Store | Files | What they cover | Wanted by |
|---|---|---|---|
| `SuperFavoritesIds` + `CollapsedFavoriteSectionIDs` (UserDefaults arrays of integers / strings) | `defaults-absent`, `-empty`, `-typical`, `-boundary` (Int32 max, 1, a section id of every `sectionIdentifier` shape: `forum-id`, `forum-url`, `forum-title` lowercased, `favorite-order`, `favorite-first-post`, `favorite-unknown`), `-same-number-two-categories` (one number, no category), `-objc-insertion-order` (**transliterated**, not produced by running the legacy code: the Objective-C screen `FavoritesTableViewController.m:1639-1657` is not in the test host, so its `NSMutableArray` write is replayed through `UserDefaults`; unsorted, as inserted), `defaults-export-typical` (real `defaults export`, two keys only) `.plist` | empty, typical, boundary, ids by number alone | 067 |
| `smiley_favorites_cache2` (`NSKeyedArchiver` of `NSMutableDictionary<code, SmileyFavorite>`, binary plist) | `smiley-favorites-{empty,typical,boundary}.archive` + `.xml.plist` (plutil view) | empty dictionary (what a last removal writes), 3 favourites, codes differing by case, equal dates, non-ASCII code and URL, fractional and earlier date | 067 |
| `smileySearchHistory_v1` (JSON `Data` in **UserDefaults**, not a file) | `search-history-{typical,50-entries,50-entries-after-case-merge,51st-evicts-oldest,after-corrupt-rewrite}.json` (the value) + `defaults-search-history-<same>.plist` (the key as `<data>`), `defaults-search-history-absent.plist` (key never written: the empty state, `record` never writes `[]`), `search-history-corrupt-before.bin` (the first 40 bytes of the real typical value) | case-insensitive merge, ignored 2-character and zero-result queries, exactly 50, a 51st evicting the oldest, corrupt data rewritten as one entry | 067 |
| `rehostImagesSwiftUI.json` (JSON file in Documents) | `upload-history-{empty,typical,boundary,after-corrupt-rewrite}.json` (img3 URLs of the `U01` shape with synthetic hashes, `previewURL` nil as the only uploader writes it, `ReplyService.swift:1958-2035`), `upload-history-corrupt-before.bin` (the first 60 bytes of the real typical file) | `[]`, 3 images newest first, nil optionals omitted from the JSON, fractional instant, same URL twice, identical id twice, non-ASCII URL, a corrupt file rewritten as the next upload alone | 067 |
| Not produced | | An array of numeric strings or other types under `SuperFavoritesIds` (the loader accepts them; no legacy writer produces them); a smiley favourite stamped by the real add (date is `Date()`, replaced by a fixed one). `search-history-corrupt-before.bin` and `upload-history-corrupt-before.bin` are cuts of real legacy output, not legacy output. | |
