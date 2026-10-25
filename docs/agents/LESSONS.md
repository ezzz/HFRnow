# Lessons table

Self-review against this table before every PR and every review fix. Extend it after every review round (REVIEW-ROUNDS.md step 9).
Seeded from a previous multi-agent project, filtered for SwiftHFR.

| # | Lesson | Source |
|---|---|---|
| 1 | Every public type/function added or touched has a one-line doc comment | seed |
| 2 | A test fails without the change and cannot pass trivially | seed |
| 3 | Docs, PR description and specs match the code exactly; no docs for unreleased behaviour | seed |
| 4 | No needless copies of large data (HTML pages, images); state behaviour at limits (memory, disk, huge topics) | seed |
| 5 | Every failure path reports something actionable; async results refresh the UI | seed |
| 6 | Identifiers are unique and outside other namespaces | seed |
| 7 | Every entry point stays consistent (menu, button, gesture, shortcut, deep link) | seed |
| 8 | No ignored errors on file-system/keychain/permission calls; races considered | seed |
| 9 | A matching/ordering fix covers both orders and every combination, not only the reported one | seed |
| 10 | Measure a performance claim before reporting or fixing it | seed |
| 11 | A guard covers every path that acts, not only the obvious one | seed |
| 12 | Tracking docs (LOTS, HFR-PROTOCOL, ADR) updated in the same commit as the change | seed |
| 13 | Tests check the action's own result, not the last notification/state change (another one can replace it) | seed |
| 14 | After a merge with conflicts, review the whole conflicted file against both parents | seed |
| 15 | A scripted edit is verified by reading the diff line by line, not only by the script's own check | seed |
| 16 | Re-check head SHA and checks right before publishing a status | seed |
| 17 | HFR facts (URL, field, cookie, selector) cite a legacy file:line or a fixture | SwiftHFR |
| 18 | Fixtures and logs contain no real pseudo, cookie, token or private content | SwiftHFR |
| 19 | Every "depends on" between lots respects module direction; a flow that parses then submits belongs to `HFRClient`. Enforced by `scripts/check-lot-deps.py` in CI | LOT-000 reviews (Fable F1, CodeRabbit) |
| 20 | A `\|` inside a code span in a Markdown table must be escaped, or the row breaks. Enforced by markdownlint (MD056) in CI | LOT-000 CodeRabbit |
| 21 | SwiftLint is not installed in cloud sessions: before pushing, check line length (≤ 140), `String(decoding:)` (flagged by `optional_data_string_conversion`), identifier length and `inclusive_language` (e.g. no `blacklist` identifiers; the wire key may keep it) | wave 1 (C1, C2) |
| 22 | On Linux, `Date.description` crashes on non-finite dates: never let a test print a value holding one | wave 1 (C1) |
| 23 | After late edits, check `git ls-files` (tracked changes), not only untracked files, before pushing | wave 1 (C1) |
| 24 | swift-corelibs-foundation ignores `timeoutInterval` and per-task redirect delegates, and `URLProtocol` cannot redirect: enforce deadlines yourself and test redirects against a loopback server | wave 1 (C2) |
| 25 | A test socket server must be closed by the thread that owns it, otherwise its file descriptor number can be reused by another server | wave 1 (C2) |
