# GAP fragments

A PR that adds a row to the [gap report](../GAP-LEGACY-VS-SWIFT.md) adds **one file here** and never edits that file ([AGENTS.md §8](../../../AGENTS.md#8-git-and-pr-workflow), #612). A fragment has a unique name, so two PRs cannot conflict. `python3 tooling/docs/fold.py` (the docs steward, daily) inserts each row at the end of its section, regenerates the H.1 list and the Counts table, and deletes the fragments. Rows already in the report are edited in place as before, in their own PR.

- **Name**: `GAP-<issue>.md`. The ID of a new row is its **issue number** (`GAP-612`); a second new row in the same PR uses the **PR number** (`GAP-614`: issues and PRs share one number space, so it cannot collide). Never a sequential number: it can be cited in code comments from the first commit and is never renumbered. Existing IDs (up to `GAP-229`) do not change.
- **Content**: two lines, nothing else:

  ```text
  Section: Reader
  | GAP-612 | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
  ```

  - `Section:` is the exact title of a `##` section that holds a GAP table (`Navigation`, `Lists`, `Reader`, `Composer`, `Private messages`, `Search`, `Settings and appearance`, `Accounts`, …).
  - The row has the nine columns of the report. `Gap` is `same`, `ported with changes`, `ported with changes (engine only)`, `UX change`, `new`, `dropped` or `not planned`. `H.1` is `a`, `a·master`, `b`, `b·needed`, `b·operator` or `—`. A `|` inside a cell is written `\|`.
- **Check**: `python3 tooling/docs/fold.py --check` (CI, job *Docs consistency*) rejects a malformed fragment, an ID that is already a row and an unknown section.
- Never edit the H.1 list or the Counts table by hand: they are generated. Changing the `Gap` or `H.1` cell of an existing row in place is fine: `--check` then only warns that the tallies are stale, and the next fold regenerates them.
- `--check` catches a fragment and a direct row only when the numbers are equal (direct rows use sequential numbers), so a reviewer checks that a PR never has both.
