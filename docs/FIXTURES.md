# Fixtures

Fixtures are real HFR pages used to test parsers, paired with the **oracle**: the output of the legacy parser on the same page.

## Layout
- **Shared capture corpus** (LOT-001): `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/<id>-<slug>.html`
  (`.json` for REST answers) plus `<id>.meta.json` (URL template, requested and final URL, redirect hops, status,
  content type, date, account role `anon`/`user1`/`user2`, names of cookies set, anonymized POST body). Ids follow the
  capture checklist rows; [`captures/MANIFEST.md`](../Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/MANIFEST.md)
  lists what each file covers and which lots consume it. Captures are never edited by hand: re-capture and re-anonymize.
- **Per-lot oracles** (LOT-002..004 onwards): `Fixtures/<lot>/<case>.oracle.json`, the legacy parser output on a
  corpus file; `<case>` names the corpus id it was computed from. Hand-built synthetic pages for states that cannot be
  captured safely live next to them as `Fixtures/<lot>/<case>.synthetic.html`.

## Anonymization (mandatory before commit)
Replace, consistently within a fixture:
- pseudos of real members, wherever HFR prints them (post headers, quotes, lists, MP list titles, smiley codes, REST authors…) → `user1`, `user2`, …; member ids → `9000NN` / `9100NN`
- cookies, session IDs, `hash_check` and any form token → `REDACTED`
- private message content, signatures and mood statuses → placeholder text
- e-mail addresses, IPs → placeholders

Public forum post content may stay when needed for the test; prefer neutral excerpts.

**Policy** (operator decision, 2026-10-26):
- Names in **member positions** (wherever HFR prints a member: post headers, quotes, lists, MP list titles, smiley
  codes, REST authors, URL parameters…) are **always** aliased; the corpus check fails otherwise.
- Names in **public prose and titles** are aliased best-effort: member names seen anywhere in the corpus, plus an
  operator-local `extra_pseudos` list in the git-ignored `local.json` (names spotted by review in prose or titles;
  never committed). Signatures and mood statuses are always replaced by placeholders.
- Collateral rewrites are expected: an ordinary word that is also a pseudo (or listed) becomes `userN` in prose too.
- Topic slugs follow the titles: a name aliased in a file is also rewritten in its slug form in every URL of that file
  and its meta, word by word since HFR keeps only 3 title words in a slug
  ([HFR-PROTOCOL](HFR-PROTOCOL.md) "Topic slug", measured on the R04-R07, R09, R27-list and R50b lists).
- MP subjects of private files are replaced by `Private subject`, except the operator's fixture threads
  (`fixture-test-N`) and `a2bcc09b796b8c6fab77058ff8446c34`. That one is **not** a leak: it is the fixed title of the
  MPStorage thread, a public constant of the legacy app (`Classes/MPStorage.m:23`, `MP_NAME`, the same for every
  user), kept so LOT-038 can test locating the storage MP.
A reviewer must check anonymization; `check --corpus` and gitleaks run on every push as safety nets.

## Capture
Run on the maintainer's Mac with [`tooling/fixtures/flows.py`](../tooling/fixtures/flows.py) (one step per
invocation, shared 3 s delay and request budget, persistent per-account jars in the work folder outside the repo),
then [`publish.py`](../tooling/fixtures/publish.py) (anonymizes every capture listed in `corpus.json` into the corpus
folder, `--private` for MP pages, and refuses a file that still leaks), `anonymize.py check --corpus` (no config
needed; CI runs it on every push) and `check --config` (operator pseudos and ids). Before committing, also run an
independent grep: collect the member names from the **raw** files' member positions with your own patterns and
assert none appears in the anonymized set, plus the cookie values, tokens and passwords. Raw captures stay in the
work folder and are deleted once the anonymized files are merged.

What to capture: the operator-approved [LOT-001 capture checklist](lots/LOT-001-capture-checklist.md) (read GETs, write flows limited to private messages between the two operator accounts, and what is covered by synthetic pages instead). Any new capture needs the operator's go first.

Tooling (Python 3 stdlib): [`tooling/fixtures/`](../tooling/fixtures/README.md) — `capture.py` (polite raw capture, outside the repo), `anonymize.py` (redaction, obfuscated-link decode and re-encode, `check` verifiers), `publish.py` (raw → corpus). CI runs its unit tests (synthetic HTML only) and `check --corpus` on the committed corpus.
