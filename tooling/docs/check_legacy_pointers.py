#!/usr/bin/env python3
"""Checks the legacy pointers of the `// Port of` headers of `App/` against the lines they cite (#1252).

A pointer `// Port of <path> (<Symbol> :a-b, lines c-d, <Other> e-f) @ <sha>` names symbols and the lines of
`git show <sha>:<path>` that should hold them (AGENTS.md §2 and §4). The sha is moved when the reference moves, the
lines are not: a pointer whose range no longer holds its symbol is wrong. Only that shape is checked; every other
item or header is counted as unchecked, and nothing that cannot be parsed fails (the exit code is 1 only for a symbol
missing from a range of a sha that could be read, or a range past the end of the file).

    python3 tooling/docs/check_legacy_pointers.py [--root App] [--fetch]

`--fetch` runs `git fetch origin legacy/duo-inner-cover` first (the shas of AGENTS.md §2 are its ancestors); a sha git
cannot read is unchecked, not a failure. Python standard library only.
"""
import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator, Optional

PORT = re.compile(r"Port of ")
PAIR = re.compile(r"\s*(?:and\s+)?(\S+) \(([^)]*)\)")
SHA = re.compile(r"(?: and \S+)?\s*@ ([0-9a-f]{7,40})\b")
SYMBOL_RANGE = re.compile(r"^(?P<sym>[A-Za-z_][\w.]*)\s*(?:lines\s+)?:?\s*(?P<a>\d+)-(?P<b>\d+)$")
RANGE_ONLY = re.compile(r"^lines\s+(?P<a>\d+)-(?P<b>\d+)$")
LAST_WORD = re.compile(r"([A-Za-z_]\w*)\s*$")
CODE_LIKE = re.compile(r"^(?:[A-Z]\w*|[a-z]+[A-Z]\w*)$")

Reader = Callable[[str, str], Optional[list]]


@dataclass(frozen=True)
class Pointer:
    """One symbol and range of a header, with where the header is written."""
    file: str
    line: int
    legacy_path: str
    symbol: str
    first: int
    last: int
    sha: str


@dataclass(frozen=True)
class Result:
    failures: list
    checked: int
    unchecked: int


def header_blocks(text: str) -> Iterator[tuple]:
    """The `//` comment blocks of a file (a pointer often wraps), as (first line number, joined text)."""
    block: list = []
    start = 0
    for number, line in enumerate(text.splitlines() + [""], start=1):
        stripped = line.strip()
        if stripped.startswith("//") and not stripped.startswith("///"):
            if not block:
                start = number
            block.append(stripped[2:].strip())
        elif block:
            yield start, " ".join(block)
            block = []


def code_symbol(item: str) -> Optional[str]:
    """The identifier ending `item` when it looks like code (camelCase, PascalCase, or written in backticks), else None."""
    word = LAST_WORD.search(item.replace("`", ""))
    if word and (item.rstrip().endswith("`") or CODE_LIKE.match(word[1])):
        return word[1]
    return None


def parse(file: str, text: str) -> tuple:
    """(pointers with a symbol and a range, number of items or headers that cannot be checked)."""
    pointers: list = []
    unchecked = 0
    for start, block in header_blocks(text):
        for port in PORT.finditer(block):
            rest = block[port.end():]
            pairs: list = []
            while match := PAIR.match(rest):  # `A (…) and B (…) @ sha`: each file has its own items
                pairs.append((match.group(1), match.group(2)))
                rest = rest[match.end():]
            sha = SHA.match(rest)
            if not pairs or not sha:
                unchecked += 1
                continue
            for path, items in pairs:
                previous = ""
                attached = False
                for raw in items.split(","):
                    item = raw.strip()
                    plain = item.replace("`", "")
                    found = SYMBOL_RANGE.match(plain)
                    only = RANGE_ONLY.match(plain)
                    symbol = found["sym"].split(".")[-1] if found else ""
                    # `Common.swift:108-110` names another file, not a symbol of this one; a plain word (`alerts :4618-4640`)
                    # is prose: both unchecked. A symbol is camelCase, PascalCase or written in backticks.
                    if (
                        found and not only and not re.search(r"\.(swift|m|h)$", found["sym"])
                        and (CODE_LIKE.match(symbol) or item.startswith("`"))
                    ):
                        pointers.append(Pointer(file, start, path, symbol, int(found["a"]), int(found["b"]), sha[1]))
                        attached = True
                    elif only and previous and not attached and (symbol := code_symbol(previous)):
                        # « icon Picker, lines 411-416 »: the range belongs to the item before it.
                        pointers.append(Pointer(file, start, path, symbol, int(only["a"]), int(only["b"]), sha[1]))
                        attached = True
                    else:
                        unchecked += 1
                        attached = False
                    previous = item
    return pointers, unchecked


def git_reader(repo: Path) -> Reader:
    """Reads `git show <sha>:<path>` as lines, None when git cannot (sha not fetched, path absent)."""
    def read(sha: str, path: str) -> Optional[list]:
        done = subprocess.run(
            ["git", "-C", str(repo), "show", f"{sha}:{path}"], capture_output=True, text=True, errors="replace", check=False
        )
        return done.stdout.splitlines() if done.returncode == 0 else None
    return read


def check(root: Path, read: Reader, repo_root: Path) -> Result:
    """Checks every pointer under `root`."""
    failures: list = []
    checked = 0
    unchecked = 0
    cache: dict = {}
    for source in sorted(root.rglob("*.swift")):
        text = source.read_text(encoding="utf-8", errors="replace")
        pointers, skipped = parse(str(source.relative_to(repo_root)), text)
        unchecked += skipped
        for pointer in pointers:
            key = (pointer.sha, pointer.legacy_path)
            if key not in cache:
                cache[key] = read(*key)
            legacy = cache[key]
            if legacy is None:
                unchecked += 1
                continue
            checked += 1
            where = f"{pointer.file}:{pointer.line}: {pointer.legacy_path} {pointer.first}-{pointer.last} @ {pointer.sha}"
            if pointer.last < pointer.first:
                failures.append(f"{where}: reversed range")
                continue
            if pointer.first < 1 or pointer.first > len(legacy):
                failures.append(f"{where}: range outside the file ({len(legacy)} lines)")
                continue
            window = "\n".join(legacy[pointer.first - 1:pointer.last])
            if not re.search(rf"(?<!\w){re.escape(pointer.symbol)}(?!\w)", window):
                failures.append(f"{where}: `{pointer.symbol}` is not in these lines")
    return Result(failures, checked, unchecked)


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default="App", help="the folder whose .swift headers are checked")
    parser.add_argument("--fetch", action="store_true", help="fetch legacy/duo-inner-cover first")
    args = parser.parse_args(argv)
    repo = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    fetched = True
    if args.fetch:
        fetch = ["git", "-C", str(repo), "fetch", "--quiet", "--no-tags", "origin", "legacy/duo-inner-cover"]
        fetched = subprocess.run(fetch, check=False).returncode == 0
        if not fetched:
            print("::warning::legacy/duo-inner-cover could not be fetched: pointers whose sha is missing stay unchecked")
    result = check(repo / args.root, git_reader(repo), repo)
    if result.checked == 0 and fetched:
        print("::warning::no legacy pointer could be read against its sha: nothing was checked")
    for failure in result.failures:
        print(f"error: {failure}")
    print(f"legacy pointers: {result.checked} checked, {result.unchecked} unchecked, {len(result.failures)} wrong")
    return 1 if result.failures else 0


if __name__ == "__main__":
    sys.exit(main())
