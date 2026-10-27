# Collaboration — repositories, roles, and how an idea becomes code

Decision records: [ADR 0010](adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md) (hosting), [ADR 0011](adr/0011-contribution-model-and-feature-intake.md) (contribution model). Engineering rules: [AGENTS.md](../AGENTS.md).
This page is for everyone: maintainers, contributors, and the agents they drive.

## 1. Repositories and branches

| Where | What | Who merges |
|---|---|---|
| `ezzz/HFRnow` → **`dev-swift`** | SwiftHFR integration branch (this codebase). Every SwiftHFR PR targets it | maintainers, green checks required |
| `ezzz/HFRnow` → `master` | Shipped Objective-C app + `HFRswift/` layer. Not SwiftHFR | ezzz |
| `francoisgn/ios-app_SwiftHFR` → `master` | Read-only mirror of `dev-swift` ([§5](#5-mirror)) | nobody: synced hourly by a workflow |
| your fork → any branch | Contributors without write access | — |

## 2. Roles

| Role | Access | Works from |
|---|---|---|
| Owner (ezzz) | Admin of `ezzz/HFRnow`: settings, protection, roles, releases | branches in `ezzz/HFRnow` |
| Maintainer (francoisgn) | Write | branches in `ezzz/HFRnow`, named as in [AGENTS.md §8](../AGENTS.md#8-git-and-pr-workflow) |
| Contributor | Triage recommended; Write when already granted | a fork, whatever the role |
| Agent session | the access of the human driving it, never more | same as its human |

Nobody needs write access to contribute. Forks get the same CI; only secrets are missing, and no required check uses one.
Every PR on `dev-swift` needs one approval from someone other than its author: with Write access, green CI alone would allow self-merges.

## 3. From an idea to a merged feature

```
idea / prototype / mock-up
  └─► issue (feature form)                         anyone
        └─► entry in FEATURES.md (status proposed)  maintainer, with credit to the author
              └─► spec  docs/features/FEAT-XXX.md   author or maintainer — what, why, HFR facts, edge cases
                    ├─► engine lots in LOTS.md        when HFRKit lacks a capability (parsing, network…)
                    └─► app PR(s) on dev-swift            one feature slice per PR, entry criteria below
```

- **Prototypes are welcome and are references, not merge candidates.** A working build in another repository shows the target; the code enters through the steps above, like the legacy app does ([ADR 0004](adr/0004-legacy-app-as-oracle.md)).
- **No guessing about HFR** ([AGENTS.md §3](../AGENTS.md#3-ground-rules)): a feature that reads or writes something new on the forum (a page, a form, a cookie) first gets its protocol facts into `docs/HFR-PROTOCOL.md`, with evidence.
- **Design proposals** (mock-ups, boards) are attached to the issue as images. An adopted design becomes a spec under `docs/features/` with the tokens and states it needs; the boards stay credited to their author.
- **Credit** stays visible: the author of an idea is named in `FEATURES.md`, in the spec, and in the PR that implements it, whoever writes the code.

## 4. Entry criteria for a PR on `dev-swift`

A PR that misses one of these is turned back to draft with a list of what is missing — no partial review.

- [ ] Linked to an issue, a `FEATURES.md` entry or a lot; **one** feature slice or one fix.
- [ ] Branched from the current `dev-swift`, conflict-free; no unrelated changes (formatting, renames, other features).
- [ ] Follows [AGENTS.md §4](../AGENTS.md#4-engineering-conventions); module boundaries respected; nothing forum-related outside `HFRKit`.
- [ ] Tests: engine logic has Swift Testing tests that fail without the change; view logic lives in testable view models.
- [ ] UI changes: before/after screenshots (light, dark, Dynamic Type XL; iPad if the layout changes) in the PR body.
- [ ] CI green, CodeRabbit comments answered, self-review against [LESSONS](agents/LESSONS.md).
- [ ] Docs in the same PR: spec, `HFR-PROTOCOL.md`, ADR when a decision is taken.
- [ ] Agent-written code: author model named, reviewed by a different model ([AGENTS.md §6](../AGENTS.md#6-model-routing-which-agent-does-what)).

### If you build with an agent
Start every session with: *"Read AGENTS.md and docs/COLLABORATION.md and follow them. Work only on <issue/feature>. Write the spec and the tests before the code. Stop and ask when HFR behaviour is not documented."* Then ask a **second** agent, on a different model, to review the diff adversarially before you open the PR. A maintainer can pair with you on the first PR.

## 5. Mirror

`francoisgn/ios-app_SwiftHFR:master` follows `dev-swift` through `.github/workflows/mirror-from-ezzz.yml` (hourly, fast-forward only, deploy key). Nothing is ever committed there; issues and PRs go to `ezzz/HFRnow` ([ADR 0010](adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md)).

## 6. CI scope

- Required checks run on `dev-swift` (push and PRs, forks included). `master` keeps its own `wrapper-tests.yml`.
- Default-branch-only automation (weekly CodeQL, issue auto-labelling) is inactive until the production switch; Dependabot runs from the `master` copy of its configuration, which only targets `dev-swift` ([ADR 0010](adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md)).
- Never add `pull_request_target`, and never make a required check depend on a secret.
- **What CI does not catch**: a change that compiles and passes the tests can still break UX, drop a setting, conflict with gestures or rely on an unverified HFR behaviour. Those are stopped by the entry criteria (§4) and the required review, not by green checks.

## 7. Handover

Done on 2026-10-27: [migration/EZZZ-CUTOVER.md](migration/EZZZ-CUTOVER.md).

## 8. Production switch (later)

Decided in its own ADR when SwiftHFR replaces the shipped app: tag `legacy/objc-final` and branch `archive/objc` on the last Objective-C release, then `dev-swift` becomes the default branch and CI follows. The Objective-C code stays readable forever as the blueprint of what works.
