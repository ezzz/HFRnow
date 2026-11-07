# Changelog fragments

A PR that fixes or changes a legacy behaviour adds **one file here** and never edits [`docs/CHANGELOG-LEGACY.md`](../CHANGELOG-LEGACY.md) ([AGENTS.md §8](../../AGENTS.md#8-git-and-pr-workflow), #612). A fragment has a unique name, so two PRs cannot conflict. `python3 tooling/docs/fold.py` (the docs steward, daily) appends the fragments to the table in number order and deletes them.

- **Name**: `<issue>.md`, the number of the issue the PR closes or refs (`612.md`). It becomes the `#` column. Existing rows keep their numbers.
- **Content**: one table row without the `#` cell, four non-empty cells, nothing else:

  ```text
  | T | Résumé court en français. | LOT-XXX #N | `Fichier.swift:12-20` @ `2440d79`, capture R25 |
  ```

  Cells: section (`T` technical or `UX`), French summary, lot / PR, legacy proof (file:line on `master` or a capture). A `|` inside a cell is written `\|`.
- **Check**: `python3 tooling/docs/fold.py --check` (CI, job *Docs consistency*) rejects a malformed fragment and a number that is already a row.
- Never put a fragment and a direct row for the same issue in one PR.
