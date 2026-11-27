"""The `Closes #N` / `Refs #N` lines of a PR body: one grammar for the claim check, the sweep and the ledger (#1198).

Imported by `scripts/issue_claims.py`, `tooling/roadmap/hygiene.py` and `tooling/docs/ledger.py`, so a body the
Issue and claim check accepts is one the sweep closes and the ledger folds.

Grammar (AGENTS.md §8 writes the line as `Closes #N`): a reference starts a line, after optional decoration (list
marker, quote, bold or code marks, a `LOT-XXX ·` prefix), with a closing keyword (`close`, `closes`, `closed`, `fix`,
`fixes`, `fixed`, `resolve`, `resolves`, `resolved`) or `Refs`/`Ref`, then `#N`, optionally followed by more numbers
(`Closes #50, #51`). Numbers may be separated by commas, `and`, `&` or spaces. A reference may also open a new clause after `.`, `;`,
`,` or `|` (`Closes #1, closes #2`), (after `.` it opens a sentence; after the others only right after another reference of the line), and its clause must end right after the numbers (end of line or one of
`.,;:()|·—–` or a markdown mark): `Fixes #12 will need a capture` and `the "Closes #152" line` are prose. Case does not
matter; `LOT-XXX` may be followed by a dot, dash or em/en dash. A `Refs LOT-XXX` counts as a preceding reference
(`Refs LOT-118, Refs #209`) but names no issue. Known limit, kept on purpose so older bodies (#303, #259, #257) still read:
a reference after `.` mid-line opens a sentence, so `Not done. Closes #12 (later).` closes #12. HTML comments, fenced code blocks and CR are ignored. Standard library only.
"""
from __future__ import annotations

import re

HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
FENCE = re.compile(r"^[ \t]*(```|~~~).*?^[ \t]*\1[^\n]*$", re.DOTALL | re.MULTILINE)
LINE = re.compile(
    r"(?:^[ \t>*_`+-]*"                                 # list marker, quote, bold or code marks
    r"(?:LOT-\d+[ \t]*[·,;:|—–-][ \t]*[*_`]*)?"        # `LOT-012 · Closes #45`
    r"|(?P<mid>(?<=[.;,|·])[ \t]+))"                    # or a new clause: `Closes #1, closes #2`
    r"(?P<kw>close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)"    # keyword
    r"[ \t]+(?:#(?P<n>\d+)\b"
    r"(?P<more>(?:(?:[ \t]*(?:,|&|and)[ \t]*|[ \t]+)#\d+\b)*)"   # `, #51` or ` #51`
    r"|LOT-\d+\b)",                                   # `Refs LOT-118, Refs #209`: a lot counts as a reference, names no issue
    re.IGNORECASE | re.MULTILINE,
)
EXTRA = re.compile(r"#(\d+)")
CLAUSE_SEPARATOR = re.compile(r"(?:[ \t]*\([^()\n]*\))?[.,;|·]?")  # all that may sit between two references of one line
CLAUSE_END = re.compile(r"[ \t]*(?:$|[.,;:()|·—–*_`])", re.MULTILINE)  # what may follow a reference that does not open its line


def normalized(body: str | None) -> str:
    """Body without CR (the web editor sends CRLF), HTML comments (template hints) and fenced code blocks (quoted examples)."""
    text = HTML_COMMENT.sub("", (body or "").replace("\r\n", "\n").replace("\r", "\n"))
    return FENCE.sub("", text)


def _unique(numbers) -> list[int]:
    return list(dict.fromkeys(numbers))


def _refs(body: str | None, closing: bool) -> list[int]:
    found = []
    text = normalized(body)
    previous_end = None  # end of the last accepted reference
    for match in LINE.finditer(text):
        if match.group("mid"):
            # after `.` a sentence opens; after `, ; | ·` a clause opens only right after another reference of the line
            after_reference = previous_end is not None and CLAUSE_SEPARATOR.fullmatch(text, previous_end, match.start())
            if text[match.start() - 1] != "." and not after_reference:
                continue  # prose: `This keeps legacy, fixes #12 (only partly).`
            if not CLAUSE_END.match(text, match.end()):
                continue  # prose: `Fixes #12 will need a capture`
        previous_end = match.end()
        if match.group("n") is None:
            continue  # `Refs LOT-118`: only there so the next clause of the line opens
        if match.group("kw").lower().startswith("ref") == closing:
            continue
        found.append(int(match.group("n")))
        found.extend(int(n) for n in EXTRA.findall(match.group("more")))
    return _unique(found)


def closing_issues(body: str | None) -> list[int]:
    """Issues the PR closes (`Closes`, `Fixes`, `Resolves`), in order, without duplicates."""
    return _refs(body, closing=True)


def refs_issues(body: str | None) -> list[int]:
    """Issues the PR only refers to (`Refs`), in order, without duplicates."""
    return _refs(body, closing=False)


def cited_issues(body: str | None) -> list[int]:
    """Every issue the PR names, closing or `Refs`: an open PR on one of them means it is being worked."""
    return _unique(closing_issues(body) + refs_issues(body))


def linked_issues(body: str | None) -> list[int]:
    """The issues the PR is accountable for: its closing refs, or its `Refs` when it has no closing one."""
    return closing_issues(body) or refs_issues(body)


def primary_issue(body: str | None) -> int | None:
    """The PR's issue: the first closing ref, else the first `Refs`, never a `Refs` when a `Closes` exists."""
    linked = linked_issues(body)
    return linked[0] if linked else None
