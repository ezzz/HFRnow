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
SwiftHFR final: Le lien de la barre d'outils, jamais celui du message.
Gap: ported with changes
```

```ledger-note
GAP-LEGACY-VS-SWIFT.md, H.1 decision 2 (line ~277): replace "drops" by "dropped" and add "#455 brings it back".
```
````

- `changelog`: one row per line, four non-empty cells (`T` or `UX`, French summary, lot / PR, legacy proof). The `#` of the row is **the PR number**, so two PRs on one issue (`Refs #N`) both fold.
- `gap-new`: `Section: <exact title of a ## section of the report>`, then the nine-cell row; its ID is the issue number (a second new row in one PR uses the PR number; CI checks it).
- `gap-edit`: the id alone on the first line, then one `<Column>: <new text>` line per cell to replace (`Feature`, `Legacy behaviour`, `Legacy ref`, `SwiftHFR final`, `Lot/Feat`, `Gap`, `Source`, `H.1`; case and spaces ignored). Other cells stay as they are, and the edited row must stay valid (`Gap` and `H.1` values). One block per row and body. The H.1 list and the Counts table are generated, never written.
- `ledger-note`: free text for an edit that is not a row (a sentence of the report, say). The steward lists it and applies it **by hand** in a separate, reviewed PR; it never fails a fold.
- A `|` inside a cell is `\|`. The section ends at the next `#`–`###` heading. The reviewer reviews it like the code.
- **No entry: no section, no label.** CI fails a `ledger` PR without a section, and a section without the label.

The label is added by a member of the repository (a contributor without label access asks for it); CI then needs a new run, so push a commit (or have a member re-run the check) after the label is added. CI checks on each push (not on a body edit): after editing the body, run `python3 tooling/docs/ledger.py check-body --pr N --file body.md` or push. The steward's parser is the final arbiter.

## The steward

The orchestrator's hygiene routine (`tooling/roadmap/hygiene.py` reports what is pending, daily, dry-run by default) or any orchestrator after a batch of merges:

```text
python3 tooling/docs/ledger.py fold                     # dry run: merged `ledger` PRs without `ledger: done`, what would be written
git fetch origin dev-swift && git switch --detach origin/dev-swift
python3 tooling/docs/ledger.py fold --apply --commit    # clean tree at origin/dev-swift: writes the docs, branch docs/ledger-<date>, one commit
# push, open one docs-only PR (no App/ or Packages/ file: the macOS jobs are skipped), merge on green CI
python3 tooling/docs/ledger.py done 590 604 --apply     # swap `ledger` for `ledger: done` on each folded PR; run it again after a failure
```

- A bad PR is **reported and skipped** (PR, block, reason); the others fold. `fold` exits non-zero when nothing was folded although PRs were pending, or with `--strict` when any was skipped. The author fixes the body; the next run folds it.
- `ledger-note` entries are listed as `BY HAND`: apply them in a follow-up PR on a branch `docs/ledger-notes-<date>` (the script cannot reproduce it, so it gets an adversarial review), then run `done`.
- `--prs 590 604` (or `590,604`) folds exactly those merged PRs, whatever their label: that is how the ledger PR is checked. The commit message says it: on the base, `ledger.py fold --apply --prs <listed> && git diff --exit-code <head>` shows no difference ([AGENTS.md §8](../../AGENTS.md#8-git-and-pr-workflow)). No adversarial review is needed.
- The CI guard keeps the rule honest: a feature PR touching a ledger path fails, a `docs/ledger-*` PR touching anything else fails.
- `fold` is idempotent: an entry already in the docs is skipped, one that clashes with different text skips its PR. It reads PRs through REST (`gh api`; GraphQL is blocked in cloud sessions).
