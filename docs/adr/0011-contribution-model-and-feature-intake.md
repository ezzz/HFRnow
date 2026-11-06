# 0011 — Contribution model, feature intake and legacy archive

**Status:** Proposed — 2026-10-27 (maintainer; needs the agreement of ezzz, owner of the repository). Hosting itself is [ADR 0010](0010-hosting-on-ezzz-hfrnow-dev-swift.md).

## Context
- SwiftHFR lives on `ezzz/HFRnow:dev-swift` ([ADR 0010](0010-hosting-on-ezzz-hfrnow-dev-swift.md)). `master` is the shipped Objective-C app with its `HFRswift/` SwiftUI layer.
- New contributors arrive with different practices. The first one (Bybifok, `moust4ki`) builds UI-first with an agent, without specs, tests or adversarial review, and opened PRs #3–#6 on `master`. They compiled, yet dropped user settings, broke `[code]` fonts and replaced a just-finished navigation.
- `write` collaborators (`francoisgn`, `moust4ki`) can merge their own PR; the team is three people.
- Q-1 is decided (2026-10-26): SwiftHFR ships as an update of the existing App Store app `hfrplus.red.super`, from this repository.
- PRs from forks run `pull_request` workflows **without secrets** and with a read-only token.

## Decision

### 1. Who works where
| Role | Where they push | PR target |
|---|---|---|
| Maintainers (ezzz, francoisgn) and their agent sessions | branches in `ezzz/HFRnow` (`lot/…`, `fix/…`, `feat/…`, `chore/…`, `docs/…`, `claude/…`) | `dev-swift` |
| Everyone else, including invited contributors | their own fork, whatever their role | `dev-swift` |

- Contributing never requires write access. The recommended role for an invited contributor is **Triage** (labels, issues).
- **No human approval is required** to merge into `dev-swift` (`required_approving_review_count: 0`): in a team of three, waiting for each other would stall the work. A PR is protected by the required checks (ADR 0005), every conversation resolved, and the review by a different model (AGENTS.md §5–6). The author merges once the [merge criteria](../../CONTRIBUTING.md#2-merge-criteria) hold.
- PRs to `master` that change SwiftHFR scope are redirected to `dev-swift`.
- Every required check passes **without secrets** (fork PRs). `pull_request_target` with a checkout of PR code is forbidden.

### 2. Feature intake
An idea, a prototype or a mock-up becomes code in this order: feature issue → spec `docs/features/FEAT-XXX.md` (what and why, screens and states, HFR facts with their source, edge cases, engine lots needed, legacy settings kept) → when `HFRKit` lacks a capability, engine lots that follow the migration loop of AGENTS.md §5 (an issue each, claimed there and planned in `docs/LOTS.md`, each specified in `docs/lots/LOT-XXX-*.md`) → app PRs, one feature slice each, meeting the definition of done (AGENTS.md §9).
- Prototype code is a reference, like the legacy app ([ADR 0004](0004-legacy-app-as-oracle.md)), not code to merge as is.
- A feature that reads or writes something new on the forum first gets its facts into `docs/HFR-PROTOCOL.md`, with evidence (AGENTS.md §3).
- The author of an idea is credited in the spec, in the PR that implements it and in `CREDITS.md`, whoever writes the code.

### 3. Legacy Objective-C archive
At the production switch (separate ADR):
- tag `legacy/objc-final` on the last `master` commit that shipped the Objective-C app, and branch `archive/objc` from it (protected, read-only);
- `dev-swift` becomes the default branch content; CI and default-branch automation move with it.
The archive stays the functional blueprint and the oracle of [ADR 0004](0004-legacy-app-as-oracle.md). Until then, oracle exports name the legacy commit they ran on.

## Consequences
- One integration branch, one process: the rules in `AGENTS.md` apply to every contributor.
- The shipped app and SwiftHFR never share a PR; nothing in SwiftHFR work can break a TestFlight build.
- Without a required approval, nothing stops a maintainer from merging their own PR once the checks are green: the merge criteria and the second-model review are a discipline, not a lock. Revisit (count 1 in `.github/rulesets/dev-swift.json`) if write access goes beyond the current team (ezzz, francoisgn, moust4ki).
- Code from contributors' own repositories is ported through lots, not merged wholesale. Copying files from an MPL-2.0 project (e.g. `moust4ki/ultra-hfr`) keeps those files under MPL-2.0; the author can instead contribute their own code under this project's license through a PR (CONTRIBUTING.md).
- CI does not judge UX, protocol assumptions or removed settings: those are caught by the spec and the review, not by green checks.
