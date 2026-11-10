# Fixture kit

Python 3 standard library only (no dependency). Output is English, colored only on a TTY (`NO_COLOR` disables it).
Policy: [docs/FIXTURES.md](../../docs/FIXTURES.md). Protocol facts: [docs/HFR-PROTOCOL.md](../../docs/HFR-PROTOCOL.md) §4-5.

| File | Role |
|---|---|
| `capture.py` | Polite capture of the pages listed in a manifest (operator-run, Mac) |
| `flows.py` | Step-by-step capture of pages and write flows (login, form GET → POST), shared delay and budget |
| `anonymize.py` | Anonymizer library, CLI and `check` verifier |
| `publish.py` | Raw captures → corpus files and `<id>.meta.json`, driven by `corpus.json` |
| `corpus.json` | The corpus manifest: raw id → corpus id, slug, extension, private |
| `local.example.json` | Template of the git-ignored `local.json` |
| `tests/` | `python3 -m unittest discover tooling/fixtures/tests` (synthetic HTML only, run in CI) |

## Safety rules

1. Raw captures live **outside any git work tree** (`capture.py` refuses otherwise), for example `~/agent-work/<task>/raw/`.
2. `local.json` (real pseudos, e-mail) and the credentials file are never committed (`local.json` is git-ignored).
3. Only anonymized output is committed, written by `publish.py` (which refuses a file that still leaks). Run `anonymize.py check --corpus` on it, plus an independent grep from the raw files (FIXTURES.md).
4. Delete the raw captures once the anonymized files are committed.
5. Nothing is sent to the forum except what the manifest lists (`capture.py`, GET only) or the step you run (`flows.py`).

## Local config (`local.json`)

```json
{
  "pseudos": ["FirstRealPseudo", "SecondRealPseudo"],
  "emails": ["operator@example.org"],
  "profile_ids": [111111, 222222],
  "extra_pseudos": ["Other Member Seen In Prose"],
  "own_topics": [123456]
}
```

`profile_ids` entries may be `null` when an account's id is unknown (the position still gives `user1` → `900001`).

- `pseudos`: mapped to `user1`, `user2`... in this order. Every other member becomes `user3`, `user4`... in document order, consistently within one file (see below).
- `profile_ids`: the operator's ids become `900001`...; other members' ids become `910001`... (one table per file).
- `emails`: redacted in addition to every e-mail-looking string.
- `extra_pseudos` (optional): other members' names spotted in public prose or titles (never in a member position,
  where they are found anyway). Replaced like corpus-wide names in the free text of every file, short or common
  words included. The file is local: this list never enters the repository.
- `own_topics` (optional): public topics started by an operator account (topic id, the `post` value). Anyone can open
  such a topic and read its author, so on its pages the anonymizer also replaces the topic id (`9900001`…), every
  message id (`9910000001`…, one table for the publish batch), the subject (also the title link `a.cCatTopic` of its row's title cell `td.sujetCase3` on a list page, replaced at that position before pseudos, with any search-hit excerpt of that cell) and slug, message bodies, the review under
  the edit form, the description, each line of the edit text (line breaks kept), the "Sujets relatifs" links and every
  date; `verify_own_topic` checks those positions on any page naming a fake own topic id. **Run `check --config` on such
  a batch**: `check --corpus` (no config) cannot recognise an own-topic page whose topic id was never aliased.

## What is replaced

**Member positions** (`DISCOVER` in `anonymize.py`, all seen live in the LOT-001 corpus): post author cell
(`td.messCase1 b.s2`; a `b.s2` elsewhere, such as a poll question, is not a member), quote headers (`X a écrit :`),
edit notices, the recipient row of MP forms (`th.repCase1` "Destinataire", R60b), `pseudo=` / `spseudo=` / `dest=` / `auteur=` URL parameters (HFR writes raw spaces and apostrophes in
these values, a pseudo may even end with `'`: a value runs to `&`, `"`, `<` or `#`, and to the closing `'` only
inside a JS single-quoted string) and `pseudo`/`dest` inputs, profile and
moderator link texts, the MP list titles (`lu par : a, b`, `Message privé pour a, b`, `Interlocuteurs multiples`
span, `Ce message privé à X`, `Mettre X en ignore list`), list author (`td.sujetCase6`) and last poster
(`a.Tableau … <b>X</b>`, home `catCase3` `<b>par X</b>`), `Envoyer un message privé à X`, `Ajouter X à votre liste
de contacts`, the review under the reply form (`td.messCase1bis`), `Auteur : X` in the description meta, personal
smileys (`[:code]`, `[:code:N]` and `/images/perso/[N/]code.gif` get the same alias as a member of that name, so
`[:user12:1]` pairs with `/images/perso/1/user12.gif`, also `%`-encoded in URLs such as `detail=%5B%3Acode%5D`, and the
`alt`/`title` (`code`, `code:N`) of those images), REST `author` / `last_author` titles, avatar `alt`, and on the public
profile page (R56) its `<title>` "X - FORUM HardWare.fr", `h4` "Informations sur : X", the Pseudo cell,
`/hfr/recherche/pseudo-X.htm` and the link texts "Envoyer un message privé à X" / "Ajouter X à votre liste de contacts".
On that page only (`body#unique__user_page__view_user_profile`), the value cell of every personal row (e-mail, birth
date, gender, city, job, hobbies, quote, signature) becomes `Profile field removed.` (a birth date `01/01/2000`), the post
count `100`, the arrival and last-post dates `01/01/2000` / `01-01-2000 à 00:00` and transaction counts `0`: with the
pseudo and id aliased, real values would still single the member out. Signatures (`span.signature`) and mood statuses (`span.MoodStatus`) are a member's own words (real names, handles, links): their content is always replaced by `Signature removed.` / `Mood removed.`. HFR's own signature separator (fifteen dashes and `<br />` at the start of the span) and its closing clear div are kept around the placeholder (#267, `R267a`); `check` accepts the dashes before the placeholder and nothing else, and refuses any element inside one other than `br` and a single `div style="clear: both;"`. Names are matched
whole (a multi-word pseudo is never split) and decoded from entities, `%`-escapes and JSON escapes.

**Personal smiley page** (`uploadsmil.php`, R601b, R601c): the code of each slot, its image path and the image `alt`/`title` (`code:0` on the first slot) are smiley positions like the ones above, in filled and empty slots. Each filled `keyword<N>` input becomes `Keywords removed.`, an empty one stays empty; both verifiers fail on any other value, on any page. The wiki's `keywords<N>` field (R54) is not this position.

**Member ids** go through the id table wherever they appear: `profil-N`, `adduser=N`, `id_user=N`, avatars
`mesdiscussions-N` (also REST `tns3`), the third `[quotemsg=…,…,N]` value and the composer's smiley search
`find_smilies_timer('hfr.inc',N)` (the logged-in member, R60b).

**Alertes Qualitaÿ** (`aq.super-h.fr`, `T01`/`T02`): the `pseudoInitiateur` attribute of the per-topic list and every
reporter of an RSS item (`<li>[le …] <b>X (initiateur)</b> : …`) are member positions; the member-written alert titles
(`nom`, the item `<title>`) and comments become one `x` per word, entities and punctuation kept. `check` verifies these
files with an XML parse of its own (`verify_aq`).

**Local AQ instance** (`origin: local-instance`, `T52`-`T71`, #574; `T72`-`T90`, #611): answers of a local copy of the published server, fed fake values only, so no alias table goes over them and `check` compares every position with the run's own forms instead (`verify_aq_local_meta`, `verify_aq_local_answer`, config-free, also in `publish.py`): exact key set, `origin` itself, host `192.0.2.1`, the two API paths, closed values for every request field and response header, and for an answer a bare code or a list of the run (alert id, `postsIds`, date). `origin` is the only value allowed, and a meta on that host cannot drop it. A new fake value form of a later run is added to `_V_AQ_LOCAL_*` with its test. `publish.py` reads `<raw>.headers.txt` into `response_headers` and, when no file holds the bytes, keeps `body_length`: the meta is the only record of an empty answer (`T62`, `T67`, `T68`). It applies the AQ gate to these files too. Tests: `tests/test_aq_own.py` (`AQLocalTests`), `tests/test_publish.py`.

**Free text**: a member name of 3+ characters that is not a function word or site/markup token (`COMMON_WORDS`, kept short on purpose: an ordinary noun used as a pseudo is still replaced in prose) is also replaced in text
nodes (except the sub-forum labels: `a.cHeader` list links in the list page's `td.padding` bar, where HFR prints
category names; a known name left in any other list link text fails `check`), text attributes (`title`, `alt`, `value`, `content`…), external URLs and internal topic slugs (also in the
meta URLs, so `final_url` matches the page). In a slug a name takes HFR's slug form (`slug_words`: no accents, lower
case, `_` and non-ASCII punctuation deleted, `-` between words); HFR keeps at most 3 title words (HFR-PROTOCOL.md "Topic slug", 341 pairs of R04-R07, R09, R27-list, R50b), so a name printed in
the file also has each of its specific words replaced in its slugs (`[Ab Cdef] colo en cours` → `cdef-cours-2018`,
live R07). Never in tag or attribute names, internal paths and queries (other than
the parameters above) or scripts. Shorter names and common words (a member called `Le` or `follow`) are replaced in
their positions only. Names known from any capture of the corpus (`publish.py` collects them) are replaced in the
free text of every file. Names seen only as smiley codes are replaced in smiley positions only. The anonymizer
refuses to write a page whose markup (tag and attribute names, in order) changed, apart from the replaced
message bodies, signatures, moods and personal `selected` options.

## List rows

List rows are aliased by position so fixtures stay stable and carry no live data. A row is aliased when it links with
`owntopic=1|2|3` (`forum1f.php?owntopic=…`, a category list with `owntopic=2`) or shows a flag (a link or an image in its flag cell), in
the `forum2.php` form or the rewritten `/hfr/…-sujet_N_P.htm` form, and then **every** row of the page is aliased (`alias_followed_lists`, no config needed): topic id `9800001`+row,
last message `9810000001`+row, title `Followed topic N` (slug `followed-topic-N`, sub-category directory `subcategory-K`),
last page `200+N`, read page `100+N` (also the `(p.N)` of the flag title), replies `5000+N`, views `300000+N`, date `01-01-2000` + N days
and N minutes (unique and ordered, so a sort by last post stays deterministic), `subcat` `960001`+, and on a page with category header
rows `cat` `101`+ (three digits at most: legacy's `wordAfterString:@"cat="` looks for the closing `&` within 4 characters) and the header
title `Category N`. Kept: row shape, flag and topic icons, link forms, `page=1`, `numreponse=0`, a zero count, `&nbsp;` cells, the browsed
category of a single-category list. Authors and last posters go through the normal pseudo aliasing.

`check` verifies it with `verify_followed_lists` (an `html.parser` walk, not the redactor's patterns): on such a page, every attribute
and text of a row (`tr` attributes included) must be an alias of that row or a known form: numbers, `title` forms, an `alt` whitelist,
links to `forum2.php`, `profilebdd.php` or the rewritten form only, images from the forum image host. A second rule,
`verify_operator_members`, runs on a page labelled with `user1` or `user2` (`account` of the meta, `--account` on the command line): an
alias `user1` or `user2` in a member position (list author, last poster; compared as `re.sub('[^0-9a-z]','',html.unescape(s).lower())`, since
HFR inserts U+200B in long pseudos) of a row linking a real id (`post=` or `sujet_N_`) fails; a row is exempt only if all its links are
private threads. Tests: `tests/test_followed_lists.py`, one per position.

## REST flag buckets

REST flag buckets (logged-in `rest_api.php?uri=forums/hardwarefr/[categories/<cat>/]topics/{participated,read,favorites}/`) are aliased by position so fixtures stay stable and carry no live data (`alias_rest_buckets`, no config needed). Only structure and field names are kept, and a fixed size: 2 groups of 1 topic (global) or 2 topics (flat), whatever the real size; an answer with fewer entries is refused. The first of each new shape comes first (flags, sub-category present or not, closed, offset past the count). `results_count` and `results_per_page` follow what is kept. Per kept topic `i`: `id` `9800000+i`, `title` `Followed topic i`, `last_post_date` `2000-01-01` + i days and i minutes, `links.posts.count` `5000+i` (and the `page=` of its href), `last_position` `200+i`, `last_post_read_id` `9810000000+i`, the category in every href `101`+ and its title `Category N`, the sub-category `960001`+. Authors, last authors and `tns3` (absent for a member without avatar) go through the normal member aliasing. An unknown field stops the anonymizer. The capture's own category URL follows (`categories/101/…` in the meta). Every dict kind has an exact key set in both layers (an unknown or missing key stops the anonymizer and fails `check`) and every string is rewritten or compared with a constant (the forum href, the `type` words, the avatar form). `check` verifies it with `verify_rest_buckets` (a JSON walk that numbers the topics, categories and sub-categories itself and requires the exact alias at every position: ids, title, date, counts, `last_position`, `last_post_read_id`, the page in a posts href, list sizes, author names), on any JSON with a bucket field or whose capture (meta `url`/`final_url`) is a bucket request, so a body with its markers stripped is still checked; `verify_rest_meta` does the same for the category of a bucket URL in a meta. Tests: `tests/test_rest_buckets.py`.

## Anonymize and verify

```sh
python3 tooling/fixtures/anonymize.py --config tooling/fixtures/local.json raw/topic.html out/topic.html
python3 tooling/fixtures/anonymize.py --config tooling/fixtures/local.json --private raw/mp.html out/mp.html
python3 tooling/fixtures/anonymize.py check --config tooling/fixtures/local.json out/*.html
python3 tooling/fixtures/anonymize.py check --corpus Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures
```

`check` needs no config (CI runs `--corpus` on the committed corpus); with `--config` it also looks for the
operator's pseudos, e-mails, ids and own topic ids (`own_topics`: required for a batch with own-topic pages). Findings are printed as `file:line:col: reason`, never with the value or its
neighbourhood (CI logs are public, and a neighbour can be a leak too). It runs two independent verifiers: the `DISCOVER` positions, and
`StructuralVerifier`, an `html.parser` walk with its own patterns over every position above (plus every
`profil-`/`adduser=`/avatar/quote id, which must be a fake one). A position the anonymizer misses is therefore
reported by `check`. `--corpus DIR` checks every `<id>.meta.json` and its `file` (with `--private` when the meta
says so) and fails on a capture file no meta describes. Findings never print the offending value.

Also redacted: `hash_check` and the logout `codehex` token (inputs, URLs, JS), cookie and session values
(`md_user`, `md_passs`, `md_id`, `md_data` as set live, plus `md_pass`, `md_forum`, `PHPSESSID`, `sessid`, `sid`),
hidden token-like inputs, personal profile fields (`email`, `homepage`, `custom_*` values; birth date and gender
selections), e-mails, IPv4 addresses (replaced by `192.0.2.1`), operator ids also as bare numbers of 5+ digits.

Obfuscated links (`md_noclass_cryptlink`, `md_blank_cryptlink`, `md_cryptlink` class tokens) are decoded (alphabet `0A12B34C56D78E9F`, two characters per byte), redacted, then **re-encoded with the same prefix** so the fixture keeps the real structure. Check mode decodes them too. `--private` replaces the content of every element whose `id` starts with `para` (message body) and every MP subject
(the `a.cCatTopic` of the title cell `td.sujetCase3`, chosen by position, never by content: a subject may be digits
only, and the page links of `td.sujetCase4` are not subjects) except the fixture threads `fixture-test-N` and the
MPStorage title (FIXTURES.md); `check --private` verifies it, in both verifiers. On the MPStorage thread page (R60a) the
first post, the storage JSON document, is kept when the thread header names the thread and the document holds only known
keys and the strings `0.1` / `iOS`; any other content raises `MPStorageDocumentError` (fail closed). On the storage thread's form pages the copies of the
document (`content_form`, the review cell after `td.messCase1bis`) must pass the same check, on both sides. `check --private`
accepts that body only on a page whose `<title>` names the thread and whose JSON keys and strings are all in its own word list.
On every other form page (composer, edit, quote prefill), `--private` also replaces the `content_form` textarea and the review cell after `td.messCase1bis` by the placeholder, unless the page names only fixture threads (`fixture-test-N` in every `sujet` input and "Sujet :" header); a page naming no thread fails closed. `check --private` flags both positions, in both verifiers (#401).

The CLI runs `check` on its own output and writes nothing if a leak remains. `check` exits non-zero and prints each offending line.

## Publish the corpus

```sh
python3 tooling/fixtures/publish.py --config local.json --raw ~/agent-work/<task>/captures-raw \
    --dest Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures [RAW_ID ...]
```

For each `corpus.json` entry: `<id>-<slug>.<ext>` (anonymized page) and `<id>.meta.json` with the kept raw meta
fields (`account`, `method`, `url_template`, `url`, `final_url`, `status`, `content_type`, `date`, `redirects`,
`set_cookie_names`, `request_fields`, `note`), `request_body` (the anonymized POST body from `<raw>.request.txt`),
`file` and `private`. The page and its meta share one alias table. A capture that still leaks is not written.

## Capture

```sh
python3 tooling/fixtures/capture.py --manifest manifest.json --out ~/agent-work/<task>/raw --dry-run
python3 tooling/fixtures/capture.py --credentials creds.json --manifest manifest.json --out ~/agent-work/<task>/raw
```

`creds.json` (JSON only, outside the repo): `{"accounts": [{"pseudo": "...", "password": "..."}, {"pseudo": "...", "password": "..."}]}`. The first entry is `user1`, the second `user2`.

`manifest.json`: `{"pages": [{"id": "topic-p1", "url": "/forum2.php?config=hfr.inc&cat=13&post=1", "account": "anon", "method": "GET"}]}` with `account` one of `anon`, `user1`, `user2`.

Login is `POST /login_validation.php?config=hfr.inc`; success means the body contains `login_redirection.php`. One request at least every 3 s (`--delay` can only raise it), a spinner while waiting, stop on HTTP 429 or 5xx. Credentials and cookie values are never printed; saved headers have `Set-Cookie` values replaced.

## Step-by-step flows (`flows.py`)

```sh
F="python3 tooling/fixtures/flows.py --work ~/agent-work/<task> --credentials creds.json --anon-config local.json"
$F login --account user1 --id W01                     # staging jar, kept only on success
$F get   --account anon  --id R20 --url '/forum2.php?config=hfr.inc&cat=13&post=1&page=1'
$F get   --account user1 --id R42 --url '/message.php?…' --cookie 'quoteshardwarefr-13-1=|5|6'
$F form  --account user1 --id W10 --form-url '/message.php?…&dest=…' --set sujet=fixture-test-1 \
         --set-json 'content_form="line 1\r\nline 2"' [--mode browser] [--dry-run]
$F post  --account user1 --id R52 --url /transsearch.php --field hash_check=@HASH --hash-from R21 --no-redirect
$F get   --account anon  --id T22 --url 'https://reho.st/self/abc123.jpg' --referer https://forum.hardware.fr/
$F get   --account anon  --id T11 --url 'https://yelims.free.fr/…' --record-network-error   # no HTTP answer → status 0
$F peek  R21 --forms --links addflag                  # anonymized summary, never raw bytes
```

State lives in the work directory: `cookies/<account>.txt` (0600), `captures-raw/<id>.{html,headers.txt,meta.json,request.txt}`,
`state.json` (request count and last request time, so `--delay` and `--budget` hold across invocations). Every redirect
hop is recorded; `--no-redirect` keeps the 3xx answer. Forms are copied in DOM order with `legacy` checkbox semantics
(`"1"`/`"0"`, every named input) or `browser` semantics (unchecked fields and extra submit buttons not sent). The run
stops on HTTP 429/5xx, on a rendered captcha field and when the budget is spent. Printed output goes through the
anonymizer.
