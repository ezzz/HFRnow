# AGENTS.md — Operating manual for contributors (humans and AI agents)

This file is the single source of truth for **how** work is done on SwiftHFR.
Every agent (Claude Code, Codex, or any other) must read it before touching the repository.
It is a living document: when a lot teaches us something, it is written here (see [§11](#11-keeping-this-file-alive)).

> `CLAUDE.md` only imports this file. Do not put instructions anywhere else.

---

## 0. Guardrails (read first)

The **operator** is the human driving an agent session. Agents act on the operator's behalf and within the operator's permissions on this repository.

- **Routine work needs no extra confirmation**: your own branches, PRs, fixes to your open PRs, replies on your PRs, comments on issues you claimed, `docs/LOTS.md` updates.
- **Consequential actions are confirmed by the operator first** (draft, show, wait): merges, releases and tags, anything on another repository, editing or closing what someone else wrote (back up, show the diff, apply, re-read), repository settings, new dependencies, disclosing a security finding, messages outside GitHub.
- How strictly confirmations apply, and whether they carry over to child sessions, is **the operator's call**. Personal rules belong in an untracked `CLAUDE.local.md` (or your tool's equivalent), not in this file.
- Merges to `master` happen through PRs with green checks; who may merge is governed by repository permissions.
- A human reviewer's correction overrides an agent's plan: apply it, reply once, update the docs.

## 1. Project in one paragraph

SwiftHFR is a native iOS client for the [forum.hardware.fr](https://forum.hardware.fr) (HFR) community forum,
written in Swift/SwiftUI. It is the successor of the community app *HFR+ / HFRnow* (Objective-C + Swift),
itself a fork of a fork. The legacy app is our **functional oracle**: we port its behaviour, we do not copy its architecture.
License: [PolyForm Noncommercial 1.0.0](LICENSE) — no commercial use, credit the authors ([CREDITS.md](CREDITS.md)).

## 2. Where things are

| Path | Content |
|---|---|
| `Packages/HFRKit/` | UI-free engine (Swift package): `HFRModels`, `HFRParsing`, `HFRNetwork`, `HFRStorage`, `HFRClient` |
| `App/` | iOS app target (SwiftUI). Created during the first Mac session — see [ROADMAP](docs/ROADMAP.md) |
| `docs/ARCHITECTURE.md` | Modules, dependency rules, design principles |
| `docs/ROADMAP.md` | Phases and their exit criteria |
| `docs/LOTS.md` | Migration lots: status, owner, reviewer. **Check it before starting work.** |
| `docs/agents/` | [ORCHESTRATION](docs/agents/ORCHESTRATION.md) (parallel sessions), [REVIEW-ROUNDS](docs/agents/REVIEW-ROUNDS.md) (bots & reviews), [LESSONS](docs/agents/LESSONS.md) (self-review table) |
| `docs/lots/` | One spec file per lot (`LOT-XXX-name.md`) |
| `docs/HFR-PROTOCOL.md` | What we know about HFR: URLs, forms, cookies, HTML structure |
| `docs/FIXTURES.md` | How fixtures are captured, anonymized and used |
| `docs/adr/` | Architecture Decision Records. A decision not in an ADR is not a decision |
| `.github/labels.yml` | The label taxonomy (§7) — the only place labels are defined |
| `scripts/configure-repo.sh` | Repository settings as code (protection, security features). Run by the maintainer |

Legacy codebase (read-only reference): <https://github.com/francoisgn/hfrnow>.
When a behaviour is unclear, **read the legacy code** instead of guessing, and cite the file and line in the lot spec.

## 3. Ground rules

1. **No guessing about HFR.** Every URL, form field, cookie or HTML selector must be traced to the legacy code or a captured fixture, and recorded in `docs/HFR-PROTOCOL.md`.
2. **Respect module boundaries** ([ARCHITECTURE](docs/ARCHITECTURE.md)). `HFRParsing`, `HFRNetwork` and `HFRStorage` never import each other; multi-step flows live in `HFRClient`, which never imports `HFRStorage` ([ADR 0008](docs/adr/0008-hfrclient-orchestration-module.md)). Nothing in `HFRKit` imports SwiftUI or UIKit.
3. **No new dependency** without an ADR and the maintainer's approval. Today the only third-party dependency is SwiftSoup ([ADR 0002](docs/adr/0002-swiftsoup-html-parser.md)).
4. **Secrets never enter the repository**: no tokens, passwords, cookies, session IDs or signing material — not in code, fixtures, logs, tests or commit messages. Secrets live in GitHub Actions secrets; for local builds only in git-ignored configuration files as defined by [ADR 0007](docs/adr/0007-third-party-api-keys.md). Push protection and gitleaks will block you; never bypass them.
5. **Fixtures are anonymized before commit** ([FIXTURES](docs/FIXTURES.md)). A real pseudo, cookie or hash in a fixture is a security incident.
6. **Small, reviewable changes.** One lot or one issue per PR. No drive-by refactors.
7. **Don't work on something already claimed** in `docs/LOTS.md` or assigned on an issue. Claim before coding ([ORCHESTRATION](docs/agents/ORCHESTRATION.md)).
8. **No hidden state.** Plans, claims and progress live in `docs/LOTS.md` and GitHub issues/PRs, never only in a session's memory.
9. **Measure, don't assume** — performance claims, protocol behaviour, test results.

## 4. Engineering conventions

- iOS 27 minimum, Swift 6.2+ language mode 6, strict concurrency. async/await only — no GCD, no completion handlers in new APIs.
- Shared state: `@Observable` classes marked `@MainActor`. No `ObservableObject`/`@Published`.
- Parsers are **pure functions**: `HTML string in → model out`, throwing typed errors. No global state, no I/O.
- Prefer Swift-native APIs (Swift Regex, `replacing(_:with:)`, `FormatStyle`, `URL.appending(path:)`).
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). Engine code without tests is not done.
- Protocols only where a second implementation is realistic (transport, HTML backend, storage). No speculative abstractions.
- Comments explain *why*, never *what*. Public API gets a one-line doc comment.
- SwiftLint must pass (`.swiftlint.yml`). Do not disable rules inline without a justification comment.

## 5. The migration loop (one lot)

Each lot in `docs/LOTS.md` follows exactly this loop:

1. **Claim** — set yourself as owner in `docs/LOTS.md` (status `in-progress`), committed and pushed **before** writing code. When an orchestrator session is active, ask it to claim for you instead and do not edit `LOTS.md` ([ORCHESTRATION](docs/agents/ORCHESTRATION.md)).
2. **Spec** — write/complete `docs/lots/LOT-XXX-*.md`: legacy sources (file:line), inputs/outputs, edge cases, protocol facts (also copied to `docs/HFR-PROTOCOL.md`).
3. **Fixtures** — real pages + legacy parser output (the oracle), anonymized.
4. **Port** — implement in the right module, Swift-native, no ObjC.
5. **Differential tests** — the new code must reproduce the oracle output on every fixture. Differences must be justified in the spec (legacy bug fixed on purpose = documented).
6. **CI green** — build, tests, lint, CodeQL, secret scan.
7. **Review** — self-review against [LESSONS](docs/agents/LESSONS.md), then a different agent/model than the author, ideally one tier above (§6). Bot rounds follow [REVIEW-ROUNDS](docs/agents/REVIEW-ROUNDS.md).
8. **Close** — status `done` in `docs/LOTS.md`, learnings added to this file (§11).

## 6. Model routing (which agent does what)

Starting hypothesis, adjusted after the first lots (record changes here).

| Work | Model |
|---|---|
| Structuring decisions, ADRs on hard problems, the message parser (`ParseMessagesOperation` port) | Fable 5.1 |
| Audit synthesis, module design, sessions/auth/cookies, posting and other state-changing flows, all reviews of Sonnet work | Opus 5.5 |
| Bulk porting of well-specified lots, simple parsers, read-only fetchers and clients, storage, CI | Sonnet 5.5 |
| Mechanical work: fixture anonymization, renames, doc/label upkeep, convention checks | Haiku 5.5 |

Rule: **the reviewer is never the author model.**

## 7. Labels and prioritization

Labels are defined in [`.github/labels.yml`](.github/labels.yml) and synced automatically. Issue forms set them; a workflow applies them.
Every issue carries one label per axis:

| Axis | Labels | Meaning |
|---|---|---|
| Type | `type: bug`, `type: feature`, `type: security`, `type: roadmap`, `type: chore`, `type: docs` | What it is |
| Priority | `priority: high`, `priority: medium`, `priority: low` | How soon |
| Difficulty | `difficulty: trivial`, `difficulty: easy`, `difficulty: medium`, `difficulty: difficult` | Effort/risk — drives model routing (§6) |
| Area | `area: models`, `area: parsing`, `area: network`, `area: storage`, `area: app`, `area: ci`, `area: docs` | Where |
| Status | `status: needs-triage`, `status: blocked`, `status: ready` | Workflow state |

**Picking work:** take `status: ready` issues in this order: `type: security` first, then `priority: high` → `low`.
Within a priority, match `difficulty` to your model tier (§6). Security issues are never reported publicly — see [SECURITY.md](SECURITY.md).

## 8. Git and PR workflow

- Default branch: `master` (protected: PR + green checks required, no force push).
- Branch names: `lot/XXX-short-name`, `fix/short-name`, `feat/short-name`, `chore/short-name`, `docs/short-name`.
- Commits: imperative mood, explain *why*. Reference the issue/lot (`Refs #12`, `LOT-003`).
- **Before opening an issue or PR, check for duplicates**: synonyms, titles and bodies, open and closed, plus `LOTS.md`. An older issue asking the same thing is the one to keep. A better PR already open → close ours with one sentence and a link.
- **PR description**, short, in order: `Closes #N` / `LOT-XXX` (or `Part of` + what is left); the problem; the cause; what changed and why this wide and no wider; the tests (names, what they check, shown to fail without the change).
- Draft while unfinished; ready as soon as CI is green. Answer reviews within a day; handle bot rounds with [REVIEW-ROUNDS](docs/agents/REVIEW-ROUNDS.md).
- No new PR while one of yours has an unanswered review comment.
- Commit small, push often: a crash should lose minutes, not hours.
- Never commit generated artifacts, `DerivedData`, `.build`, or anything matched by `.gitignore`.

## 9. Definition of done

- [ ] Code in the right module, boundaries respected
- [ ] Tests (differential tests for ported logic) — all green in CI
- [ ] SwiftLint, CodeQL, dependency review and secret scanning green
- [ ] Spec / protocol / ADR docs updated
- [ ] Reviewed by another model or a human
- [ ] Self-review against [LESSONS](docs/agents/LESSONS.md) done
- [ ] `docs/LOTS.md` and the issue status updated

## 10. Environments

- **Linux cloud agents**: can edit code and docs and run `swift test` on `HFRKit` (keep the engine Foundation-only). The Swift toolchain comes from [`scripts/cloud-setup.sh`](scripts/cloud-setup.sh), pasted into the cloud environment's setup script (needs `download.swift.org` in the allowed domains). Cannot build the app.
- **Mac agents (Claude Code CLI on the maintainer's Mac)**: Xcode builds, simulator, device installs.
- **CI** is the arbiter: if it is not green in CI, it is not done.

## 11. Keeping this file alive

At the end of every lot, add what you learned (process lessons go to [LESSONS](docs/agents/LESSONS.md) instead) that the next agent needs: HFR quirks, conventions decided, traps.
Keep entries short and dated. Remove anything that became false.

### Learnings log

- 2026-10-24 — LOT-000: audit agents proposed lots that mixed parsing and networking; the synthesis copied it and only the independent review caught it. Always check lot dependencies against `Package.swift` (LESSONS #19).
- 2026-10-24 — Phase 0: from cloud sessions, `@mentions` in posted comments are altered, so bot commands (`@dependabot rebase`, `@coderabbitai review`) do not work. Ask the operator to post them.
- 2026-10-24 — Phase 0: CodeQL's Swift extractor failed on the preview Xcode 27 toolchain; Swift analysis runs on `macos-26` (stable Xcode), the iOS 27 build check stays on `xcode-27`.
- 2026-10-25 — Wave 1: CI job logs **can** be read from cloud sessions with the GitHub MCP tool `get_job_logs` (only `gh api …/logs` is blocked, because logs are served from another host). Annotations remain the quickest signal.
- 2026-10-24 — Phase 0: cloud agents cannot change repository settings (proxy returns 403); settings live in `scripts/configure-repo.sh`, run by the maintainer.
- 2026-10-24 — Phase 0: GitHub-hosted runners provide Xcode 27 only through the `xcode-27` runner label (preview). Default `macos-26` images ship Xcode 26.x and cannot build the iOS 27 target.
