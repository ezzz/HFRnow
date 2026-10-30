# Roadmap

Each phase has exit criteria. Work items are [issues](https://github.com/ezzz/HFRnow/issues) (`type: lot`, `type: roadmap`…, claimed with `/claim`; ADR 0010) with their owner and status; [LOTS.md](LOTS.md) is the plan of the lots. The phases below say what is built; the milestones say what ships.

## Milestones

Every lot of [LOTS.md](LOTS.md) belongs to one milestone. Each milestone has a live kanban board, where every lot shows as 🔜 todo, 🔄 ongoing or ✅ done:
- [#166](https://github.com/ezzz/HFRnow/issues/166) for M1;
- [#324](https://github.com/ezzz/HFRnow/issues/324) for M2 to M4, with the legend and the definition of done of a lot.

| Milestone | Scope | Exit criteria |
|---|---|---|
| 🚀 M1 · MVP | First usable build: log in, browse forums, topics and flags, read, reply (the audit and tooling lots 000–005 and 071, the engine lots the MVP needs, and the app lots 080–084, 119, 137, 160, 161, 169, 170) | Every M1 lot done; the fixes that touch the MVP merged; the #322 light, dark and Dynamic Type XL checks done; a TestFlight build installed by the maintainer |
| 📖 M2 · Read & reply complete | Every reading and answering feature of the legacy app: quotes, formatting, smileys, images, edit and delete, new topic, polls, search, filters, page tools, offline reading, MPs | Every M2 lot done; TestFlight beta 2 |
| ⚙️ M3 · Engine complete | Every `HFRKit` lot not already in M1 | Every M3 lot done; LOT-070 parity gates green |
| 🏁 M4 · Final version | Everything else: MPStorage sync, notifications, appearance, compliance, accessibility, Phase 5, App Store | LOT-164 parity gate passed; the LOT-165 App Store submission accepted by App Review; every lot done |

M3 runs in parallel with M2: engine lots run in cloud sessions, while app lots need the maintainer's Mac. Moving a lot to another milestone is an operator decision, recorded on the board.

![SwiftHFR milestones: M1 MVP, then M2 read and reply complete on the Mac lane and M3 engine complete on the cloud lane, both leading to M4 final version; below, the life of a lot from todo (ready, blocked, triage) through ongoing (claimed, draft PR, review wanted, changes requested, approved) to done (merged, issue closed, docs up to date)](assets/roadmap-milestones.svg)

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

## Phase 3 — Engine port *(in progress — 39 of 67 engine lots done on 2026-10-29)*
Lots ported one by one with differential tests (`HFRModels`, `HFRNetwork`, parsers, reply posting, `HFRStorage`).
**Exit:** all lots `done`; the engine covers every feature of the legacy app.

## Phase 4 — App *(in progress — app target done by LOT-080; first usable build = LOT-080 to 083, see [LOTS.md](LOTS.md))*
The iOS app target `App/SwiftHFR.xcodeproj` links `HFRKit` and is built and tested in CI ([ADR 0012](adr/0012-app-project-file-strategy.md)).
Reuse and adapt the legacy SwiftUI views on top of `HFRKit`; remove everything unused.

## Phase 5 — iOS 27 experience
Column-based navigation and large/foldable layouts. Design documentation provided by the maintainer.

## App features (Phases 4–5)
New app features (Home, page navigator, Shortcuts check, themes…) come from the [feature backlog](FEATURES.md); each goes through a feature issue, a spec and, when `HFRKit` lacks a capability, engine lots ([ADR 0011](adr/0011-contribution-model-and-feature-intake.md) §2).
