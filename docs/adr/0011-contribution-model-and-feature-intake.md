# 0011 — Contribution model, feature intake and legacy archive

**Status:** Proposed — 2026-10-27 (maintainer; needs the agreement of ezzz, owner of the repository). Hosting itself is [ADR 0010](0010-hosting-on-ezzz-hfrnow-dev-swift.md).

## Context
- SwiftHFR lives on `ezzz/HFRnow:dev-swift` ([ADR 0010](0010-hosting-on-ezzz-hfrnow-dev-swift.md)). `master` is the shipped Objective-C app with its `HFRswift/` SwiftUI layer.
- New contributors arrive with different practices. The first one (Bybifok, `moust4ki`) builds UI-first with an agent, without specs, tests or adversarial review, and opened PRs #3–#6 on `master`. They compiled, yet dropped user settings, broke `[code]` fonts and replaced a just-finished navigation.
- `write` collaborators (`francoisgn`, `moust4ki`) can merge their own PR on green CI alone.
- Q-1 is decided (2026-10-26): SwiftHFR ships as an update of the existing App Store app `hfrplus.red.super`, from this repository.
- PRs from forks run `pull_request` workflows **without secrets** and with a read-only token.

## Decision

### 1. Who works where
| Role | Where they push | PR target |
|---|---|---|
| Maintainers (ezzz, francoisgn) and their agent sessions | branches in `ezzz/HFRnow` (`lot/…`, `fix/…`, `feat/…`, `chore/…`, `docs/…`, `claude/…`) | `dev-swift` |
| Everyone else, including invited contributors | their own fork, whatever their role | `dev-swift` |

- Contributing never requires write access. The recommended role for an invited contributor is **Triage** (labels, issues).
- Every PR on `dev-swift` needs **one approving review by someone other than its author**, on top of the checks of ADR 0005. With write access, green CI alone would allow self-merges.
- PRs to `master` that change SwiftHFR scope are redirected to `dev-swift`.
- Every required check passes **without secrets** (fork PRs). `pull_request_target` with a checkout of PR code is forbidden.

### 2. Feature intake
An idea, a prototype or a mock-up becomes code in this order: feature issue → spec `docs/features/FEAT-XXX.md` (what and why, screens and states, HFR facts with their source, edge cases, engine lots needed, legacy settings kept) → engine lots in `docs/LOTS.md` when `HFRKit` lacks a capability → app PRs, one feature slice each, meeting AGENTS.md §9.
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
- The required review is applied in `.github/rulesets/dev-swift.json` (`required_approving_review_count: 1`) once this ADR is accepted. A maintainer's PR then waits for someone else's approval; lower the count only if every write member is a maintainer.
- Code from contributors' own repositories is ported through lots, not merged wholesale. Copying files from an MPL-2.0 project (e.g. `moust4ki/ultra-hfr`) keeps those files under MPL-2.0; the author can instead contribute their own code under this project's license through a PR (CONTRIBUTING.md).
- CI does not judge UX, protocol assumptions or removed settings: those are caught by the spec and the review, not by green checks.
