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
| 26 | Parse HTML with `SwiftSoup.parseHTML`, never `parse`: `parse` switches to the XML parser when a page starts with `<?xml` | wave 1 (C4) |
| 27 | SwiftLint runs locally from its Linux release binary (or builds from source in ~10 min): lint before pushing instead of spending a CI round | wave 1–2 (C4, C3b) |
| 28 | `URL.cachesDirectory` does not exist on Linux, and `FileManager.replaceItemAt` fails there: use explicit paths and `rename(2)` for atomic writes | wave 2 (C3a, C3b) |
| 29 | Never let file deletion follow symlinks: validate every path component from the root, refuse symlinked roots, areas and entries | wave 2 (C3a, CodeRabbit) |
| 30 | On Linux, `URLSession` carries the cookies it added onto a followed redirect, whatever the new host: account sessions refuse redirects that leave the allowed hosts | wave 2 (C2c, Fable) |
| 31 | Keep other clients' JSON numbers as written (lexeme or Decimal), never through `Double`: preserved data must round-trip byte-exact | wave 2 (Fable on LOT-062) |
| 32 | Header-name checks (in code and in tests) must trim and lowercase names, or `" Cookie"` slips through | wave 2 (C2c) |
| 33 | An anonymizer's position list is checked by an independent verifier (other parser, other patterns) and by a grep of names harvested from the **raw** files; the list that produced the output never vouches for it. Tests isolate one position each (a name also caught elsewhere hides a missing selector) | PR #38 Fable review (LOT-001) |
| 34 | Patterns over attribute values are quote-aware: a raw `'` inside a double-quoted value ended two "independent" regexes at the same place | LOT-001 v2 fix round |
| 35 | Before starting a parser lot, check **both** inputs exist: the captures it reads **and** a legacy-oracle exporter that covers it (ADR 0004). Fixtures alone are not a requirement met | wave 3 (CodeRabbit on #45, LOT-025) |
| 36 | A capture checklist row skipped or "dropped" by the capture session is a gap to send back to it, not a cue to hand-build the page in the cloud | wave 3 (R33/R56, LOT-026/027) |
| 37 | A URL extracted from a page and then requested with the session must be checked for scheme **and** host: an explicit `http://host:80/` passes a host-only check | wave 3 (CodeRabbit on #45, CWE-319) |
| 38 | Read the capture before designing states: the checklist expected poll results for anonymous visitors, the page shows the voting form | wave 3 (C5, LOT-026) |
| 39 | Redaction rules decide by position (DOM cell), never by what the content looks like: a "keep digits, they are page numbers" rule kept digit-only MP subjects. A derived form of a name (URL slug) follows the source's own transformation, measured on real pairs (HFR keeps 3 title words, so a name can appear by one word) | LOT-001 corpus fix round (CodeRabbit); slug rule measured in HFR-PROTOCOL.md §6 "Topic slug" (R04, R05a, R05b, R06, R07, R09, R27-list, R50b) |
| 40 | Stacked PRs that share one generated file (e.g. `hfrnow.patch`) are merged in order with merge commits, never rebased or force-pushed; after a squash merge of the lower PR, merge master into the next branch and keep that branch's own version of the shared file | LOT-002..004 merges |
| 41 | Bot review rounds on docs-heavy PRs: batch the fixes, reply to and resolve every thread (master requires resolved conversations), and merge once required checks are green **and** the operator has approved merging (AGENTS.md §0) | LOT-002..004 CodeRabbit rounds |
| 42 | Parallel lots that append to the same shared doc section (HFR-PROTOCOL §6c) conflict on every merge: create the shared heading first, each lot adds only its own `###` subsection, and the orchestrator resolves by keeping all subsections | wave 4 (#45, #52, #53, #55, #59) |
| 43 | A link a parser returns that the app may follow with the session (actions, pager, lists) is restricted to the forum origin (`HFRURL.forumRelativePath`); member-supplied links (websites) stay external and are documented as never requested with the session | wave 4 (Fable on #55, orchestrator on #53, #59) |
| 44 | "Not found" must stay distinguishable from "could not read": a page whose rows all fail, or a login wall on a URL that always has a body, throws instead of returning an empty list | wave 4 (Fable on #55, orchestrator on #53) |
