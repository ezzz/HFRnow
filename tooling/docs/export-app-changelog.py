#!/usr/bin/env python3
"""Exports the "Résumé (FR)" column of docs/CHANGELOG-LEGACY.md for the app's "Nouveautés" screen (LOT-120).

    python3 tooling/docs/export-app-changelog.py            # writes App/SwiftHFR/Resources/changelog-v1.json
    python3 tooling/docs/export-app-changelog.py --check    # exit 1 when the bundled copy is stale

Run it when the steward has folded new rows (ledger.py fold) and before a release. Standard library only.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "CHANGELOG-LEGACY.md"
TARGET = ROOT / "App" / "SwiftHFR" / "Resources" / "changelog-v1.json"
ROW = re.compile(r"^\|\s*(\d+)\s*\|\s*(T|UX)\s*\|")


def cells(line):
    """The cells of a table row; `\\|` stays inside a cell."""
    parts = re.split(r"(?<!\\)\|", line.strip())[1:-1]
    return [part.strip().replace("\\|", "|") for part in parts]


def entries(text):
    """One entry per numbered row, in file order: row number, section (T or UX), summary without code or emphasis marks."""
    result = []
    for line in text.splitlines():
        if not ROW.match(line):
            continue
        row = cells(line)
        if len(row) < 3 or not row[2]:
            continue
        result.append({"id": int(row[0]), "section": row[1], "summary": re.sub(r"\*+", "", row[2].replace("`", ""))})
    return result


def render(text):
    """The file's content for `text`, stable (sorted keys, trailing newline)."""
    return json.dumps(entries(text), ensure_ascii=False, indent=1, sort_keys=True) + "\n"


def main(argv):
    expected = render(SOURCE.read_text(encoding="utf-8"))
    if "--check" in argv:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != expected:
            print(f"{TARGET.relative_to(ROOT)} is stale: run tooling/docs/export-app-changelog.py", file=sys.stderr)
            return 1
        return 0
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(expected, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
