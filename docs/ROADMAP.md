# Roadmap

Each phase has exit criteria. Work items live in [LOTS.md](LOTS.md) and GitHub issues (`type: roadmap`).

## Phase 0 — Foundations *(in progress)*
- [x] License (PolyForm Noncommercial), credits, README, AGENTS.md
- [x] `HFRKit` package skeleton with SwiftSoup
- [x] CI (Linux + macOS/Xcode 27), CodeQL, dependency review, Dependabot, gitleaks, Scorecard
- [x] Issue forms, label taxonomy, auto-labelling, PR template, CodeRabbit config
- [ ] Repository settings: run `scripts/configure-repo.sh` from the maintainer's machine (branch protection, secret scanning push protection, private vulnerability reporting, topics) — cloud agents cannot change repository settings
- [ ] CodeRabbit GitHub app installed (maintainer)
- [ ] iOS app target created on the Mac (Xcode 27) and wired to `HFRKit`; ADR on project-file strategy

**Exit:** CI green on `master`, protections active, app target builds in CI.

## Phase 1 — Audit of the legacy engine
Deep audit of the ~10 k lines of legacy Objective-C networking, HTML parsing and storage, and of vendor usage.
Output: dependency graph, ordered lots in [LOTS.md](LOTS.md), first version of [HFR-PROTOCOL.md](HFR-PROTOCOL.md).
**Exit:** every legacy engine file mapped to a lot; lot order reviewed.

## Phase 2 — Fixtures and oracle
Harness in the legacy app exporting parser output as JSON from real pages; capture on the maintainer's Mac; anonymization.
**Exit:** fixtures + oracle output committed for every parsing lot.

## Phase 3 — Engine port
Lots ported one by one with differential tests (`HFRModels`, `HFRNetwork`, parsers, reply posting, `HFRStorage`).
**Exit:** all lots `done`; the engine covers every feature of the legacy app.

## Phase 4 — App
Reuse and adapt the legacy SwiftUI views on top of `HFRKit`; remove everything unused.

## Phase 5 — iOS 27 experience
Column-based navigation and large/foldable layouts. Design documentation provided by the maintainer.
