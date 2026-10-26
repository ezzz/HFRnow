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
  "extra_pseudos": ["Other Member Seen In Prose"]
}
```

`profile_ids` entries may be `null` when an account's id is unknown (the position still gives `user1` → `900001`).

- `pseudos`: mapped to `user1`, `user2`... in this order. Every other member becomes `user3`, `user4`... in document order, consistently within one file (see below).
- `profile_ids`: the operator's ids become `900001`...; other members' ids become `910001`... (one table per file).
- `emails`: redacted in addition to every e-mail-looking string.
- `extra_pseudos` (optional): other members' names spotted in public prose or titles (never in a member position,
  where they are found anyway). Replaced like corpus-wide names in the free text of every file, short or common
  words included. The file is local: this list never enters the repository.

## What is replaced

**Member positions** (`DISCOVER` in `anonymize.py`, all seen live in the LOT-001 corpus): post author cell
(`td.messCase1 b.s2`; a `b.s2` elsewhere, such as a poll question, is not a member), quote headers (`X a écrit :`),
edit notices, `pseudo=` / `spseudo=` / `dest=` / `auteur=` URL parameters (HFR writes raw spaces and apostrophes in
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
pseudo and id aliased, real values would still single the member out. Signatures (`span.signature`) and mood statuses (`span.MoodStatus`) are a member's own words (real names, handles, links): their content is always replaced by `Signature removed.` / `Mood removed.`. Names are matched
whole (a multi-word pseudo is never split) and decoded from entities, `%`-escapes and JSON escapes.

**Member ids** go through the id table wherever they appear: `profil-N`, `adduser=N`, `id_user=N`, avatars
`mesdiscussions-N` (also REST `tns3`) and the third `[quotemsg=…,…,N]` value.

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

## Anonymize and verify

```sh
python3 tooling/fixtures/anonymize.py --config tooling/fixtures/local.json raw/topic.html out/topic.html
python3 tooling/fixtures/anonymize.py --config tooling/fixtures/local.json --private raw/mp.html out/mp.html
python3 tooling/fixtures/anonymize.py check --config tooling/fixtures/local.json out/*.html
python3 tooling/fixtures/anonymize.py check --corpus Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures
```

`check` needs no config (CI runs `--corpus` on the committed corpus); with `--config` it also looks for the
operator's pseudos, e-mails and ids. Findings are printed as `file:line:col: reason`, never with the value or its
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
MPStorage title (FIXTURES.md); `check --private` verifies it, in both verifiers.

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
$F peek  R21 --forms --links addflag                  # anonymized summary, never raw bytes
```

State lives in the work directory: `cookies/<account>.txt` (0600), `captures-raw/<id>.{html,headers.txt,meta.json,request.txt}`,
`state.json` (request count and last request time, so `--delay` and `--budget` hold across invocations). Every redirect
hop is recorded; `--no-redirect` keeps the 3xx answer. Forms are copied in DOM order with `legacy` checkbox semantics
(`"1"`/`"0"`, every named input) or `browser` semantics (unchecked fields and extra submit buttons not sent). The run
stops on HTTP 429/5xx, on a rendered captcha field and when the budget is spent. Printed output goes through the
anonymizer.
