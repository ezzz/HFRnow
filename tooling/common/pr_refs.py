"""The `Closes #N` / `Refs #N` lines of a PR body: one grammar for the claim check, the sweep and the ledger (#1198).

Imported by `scripts/issue_claims.py`, `tooling/roadmap/hygiene.py` and `tooling/docs/ledger.py`, so a body the
Issue and claim check accepts is one the sweep closes and the ledger folds.

Grammar (AGENTS.md §8 writes the line as `Closes #N`): a reference starts a line, after optional decoration (list
marker, quote, bold or code marks, a `LOT-XXX ·` prefix), with a closing keyword (`close`, `closes`, `closed`, `fix`,
`fixes`, `fixed`, `resolve`, `resolves`, `resolved`) or `Refs`/`Ref`, then `#N`, optionally followed by more numbers
(`Closes #50, #51`). A reference may also open a new clause after `.`, `;`, `,` or `|` (`Closes #1, closes #2`). Case
does not matter. A keyword inside a sentence (`also fixes #12 in passing`) is prose, not a reference. HTML
comments (template hints) and CR are ignored. Standard library only.
"""
from __future__ import annotations

import re

HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
LINE = re.compile(
    r"(?:^[ \t>*_`+-]*"                                 # list marker, quote, bold or code marks
    r"(?:LOT-\d+[ \t]*[·,;:|-][ \t]*[*_`]*)?"          # `LOT-012 · Closes #45`
    r"|(?<=[.;,|·])[ \t]+)"                             # or a new clause: `Closes #1, closes #2`
    r"(close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)"    # keyword
    r"[ \t]+#(\d+)\b"
    r"((?:[ \t]*(?:,|&|and)[ \t]*#\d+\b)*)",            # `, #51`
    re.IGNORECASE | re.MULTILINE,
)
EXTRA = re.compile(r"#(\d+)")


def normalized(body: str | None) -> str:
    """Body without CR (the web editor sends CRLF) and without HTML comments (template hints are not links)."""
    return HTML_COMMENT.sub("", (body or "").replace("\r\n", "\n").replace("\r", "\n"))


def _unique(numbers) -> list[int]:
    return list(dict.fromkeys(numbers))


def _refs(body: str | None, closing: bool) -> list[int]:
    found = []
    for match in LINE.finditer(normalized(body)):
        if match.group(1).lower().startswith("ref") == closing:
            continue
        found.append(int(match.group(2)))
        found.extend(int(n) for n in EXTRA.findall(match.group(3)))
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
