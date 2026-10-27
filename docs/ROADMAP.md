# Roadmap

Each phase has exit criteria. Work items, their owners and status live in [LOTS.md](LOTS.md), the only tracker until Issues are enabled on ezzz/HFRnow (then GitHub issues `type: lot`, `type: roadmap`, claimed with `/claim`; ADR 0010).

## Phase 0 — Foundations *(done — 2026-10-24)*
- [x] License (PolyForm Noncommercial), credits, README, AGENTS.md
- [x] `HFRKit` package skeleton with SwiftSoup
- [x] CI (Linux + macOS/Xcode 27), CodeQL, dependency review, Dependabot, gitleaks, Scorecard
- [x] Issue forms, label taxonomy, auto-labelling, PR template, CodeRabbit config
- [x] Repository settings applied with `scripts/configure-repo.sh` (branch protection, secret scanning push protection, private vulnerability reporting, topics)
- [x] CodeRabbit installed and reviewing PRs

**Exit:** CI green on `master`, protections active. ✓

Moved out of Phase 0: the iOS app target (Xcode 27, Mac session) is created before Phase 4; the engine phases do not need it.

## Phase 1 — Audit of the legacy engine *(done — 2026-10-24, [audit](audit/README.md))*
Deep audit of the ~10 k lines of legacy Objective-C networking, HTML parsing and storage, and of vendor usage.
Output: dependency graph, ordered lots in [LOTS.md](LOTS.md), first version of [HFR-PROTOCOL.md](HFR-PROTOCOL.md).
**Exit:** every legacy engine file mapped to a lot; lot order reviewed.

## Phase 2 — Fixtures and oracle *(done — 2026-10-26, LOT-001 to LOT-005)*
Harness in the legacy app exporting parser output as JSON from real pages; capture on the maintainer's Mac; anonymization.
**Exit:** fixtures + oracle output committed for every parsing lot.

## Phase 3 — Engine port *(in progress — 23 of 55 engine lots done on 2026-10-27)*
Lots ported one by one with differential tests (`HFRModels`, `HFRNetwork`, parsers, reply posting, `HFRStorage`).
**Exit:** all lots `done`; the engine covers every feature of the legacy app.

## Phase 4 — App *(starting — app target LOT-080 on the Mac; first usable build = LOT-080 to 083, see [LOTS.md](LOTS.md))*
Prerequisite: create the iOS app target on the Mac (Xcode 27), wire it to `HFRKit`, add an app build job to CI, record the project-file strategy in an ADR.
Reuse and adapt the legacy SwiftUI views on top of `HFRKit`; remove everything unused.

## Phase 5 — iOS 27 experience
Column-based navigation and large/foldable layouts. Design documentation provided by the maintainer.

## App features (Phases 4–5)
New app features (Home, page navigator, Shortcuts check, themes…) come from the [feature backlog](FEATURES.md); each goes through a feature issue (its FEATURES.md entry until Issues are enabled), a spec and, when `HFRKit` lacks a capability, engine lots ([ADR 0011](adr/0011-contribution-model-and-feature-intake.md) §2).
