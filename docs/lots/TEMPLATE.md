# LOT-XXX — <name>

- **Module:** HFRParsing | HFRNetwork | HFRStorage | HFRModels | HFRClient | App
- **Difficulty / model:** … (author → reviewer)
- **Issue:** #…

## Legacy sources
Files and line ranges in <https://github.com/ezzz/HFRnow> @ `87fe0d1c` (the legacy reference, AGENTS.md §2: `git show 87fe0d1c:<path>`) this lot replaces.

## Legacy counterpart (app lots)
One line per view or view model: the SwiftHFR file, the legacy file and symbol at `87fe0d1c` it ports (`HFRswift/Swift/MainWindow.swift (ForumTopicsListView)`), or "none @ 87fe0d1c". Above the main type in the code, write `// Port of HFRswift/Swift/<File>.swift (<Symbol>) @ 87fe0d1c. Differences: …`, naming the GAP row, and `UXD-NN` when a difference waits on a decision (AGENTS.md §4).

## UX evolutions (app lots)
Every user-visible difference from legacy, each with its GAP id (a new row is a `gap-new` block of the `### Ledger` section of the PR body, its id the issue number: `GAP-568`; [tooling/docs/README](../../tooling/docs/README.md)) and its class from the H.1 column of `docs/migration/GAP-LEGACY-VS-SWIFT.md`: `b·needed` (why), `b·operator` (decision and date) or `b` (optional: a setting or M5, never the default). Write "None: same UX as legacy" when there is none.

## Behaviour
Inputs, outputs, rules. Every HFR fact also goes to `docs/HFR-PROTOCOL.md`.

## Edge cases
…

## Fixtures
List of fixture files and what each covers.

## Intentional differences from legacy
Legacy bugs fixed on purpose, with justification.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
