# Docs tooling

Two scripts keep the shared docs conflict-free ([#612](https://github.com/ezzz/HFRnow/issues/612), [#620](https://github.com/ezzz/HFRnow/issues/620)). Python standard library only; tests in `scripts/tests/test_docs_fold.py` and `test_docs_ledger.py`.

| Script | Who runs it | What it does |
|---|---|---|
| `fold.py` | CI (`--check`), the steward | Folds fragments of `docs/changelog-legacy.d/` and `docs/migration/gap.d/` into `docs/CHANGELOG-LEGACY.md` and `docs/migration/GAP-LEGACY-VS-SWIFT.md`, regenerates the H.1 list and the Counts table. Formats: README of each fragment folder |
| `ledger.py` | CI (`check-body`, `guard`), the steward (`fold`, `done`) | Turns the `### Ledger` entries of merged PRs into those fragments, applies in-place GAP edits, folds |

## The ledger rule

A feature PR **never** touches `docs/CHANGELOG-LEGACY.md`, `docs/migration/GAP-LEGACY-VS-SWIFT.md`, `docs/changelog-legacy.d/` or `docs/migration/gap.d/` (the *Docs consistency* check fails it, unless its branch is `docs/ledger-*`). Its entries go in the PR body and the PR gets the label `ledger`. No file, no conflict, no late push, no macOS rerun.

### Example of the section (PR body)

````markdown
### Ledger

```changelog
| T | Le lien d'un message n'est plus suivi avec la session. | LOT-031 #455 | `ReplyService.swift:210-232` @ `2440d79`, capture R25 |
```

```gap-new
Section: Reader
| GAP-455 | Lien d'action | Cherche dans toute la ligne | `ReplyService.swift:210` | Cherche dans `div.toolbar` | LOT-031 | ported with changes | capture R25 | a |
```

```gap-edit
GAP-045
| GAP-045 | Marquer non lu | … the whole new row, nine cells, same id … |
```
````

- `changelog`: one row per line, four non-empty cells (`T` or `UX`, French summary, lot / PR, legacy proof). The `#` is the issue of the PR (`Closes`/`Refs #N`, else the PR number).
- `gap-new`: `Section: <exact title of a ## section of the report>`, then the nine-cell row; its ID is the issue number (a second new row in one PR uses the PR number).
- `gap-edit`: the id, then the **whole** new row (same id): it replaces the row in place. The H.1 list and the Counts table are generated, never written.
- A `|` inside a cell is `\|`. The section ends at the next `#`–`###` heading. The reviewer reviews it like the code.

The check runs on each push (not on a body edit): after editing the body, run `python3 tooling/docs/ledger.py check-body --file body.md` or push. The steward's parser refuses a malformed body and names the PR.

## The steward

The orchestrator's hygiene routine (`tooling/roadmap/hygiene.py` reports what is pending, daily, dry-run by default) or any orchestrator after a batch of merges:

```text
python3 tooling/docs/ledger.py fold                  # dry run: merged `ledger` PRs without `ledger: done`, what would be written
python3 tooling/docs/ledger.py fold --apply --commit # writes the docs, branch docs/ledger-<date>, one commit
# push, open one docs-only PR (no App/ or Packages/ file: the macOS jobs are skipped), merge on green CI
python3 tooling/docs/ledger.py done 590 604 --apply  # swap `ledger` for `ledger: done` on each folded PR
```

The ledger PR needs no adversarial review ([AGENTS.md §8](../../AGENTS.md#8-git-and-pr-workflow)): it is valid if, on its base, `ledger.py fold --apply` for the PRs it lists reproduces it. `fold` is idempotent: an entry already in the docs is skipped, one that clashes with different text stops the run. It reads PRs through REST (`gh api`; GraphQL is blocked in cloud sessions).
