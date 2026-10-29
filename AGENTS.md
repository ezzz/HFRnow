# AGENTS.md — Operating manual for contributors (humans and AI agents)

This file is the single source of truth for **how** work is done on SwiftHFR.
Every agent (Claude Code, Codex, or any other) must read it before touching the repository.
It is a living document: when a lot teaches us something, it is written here (see [§11](#11-keeping-this-file-alive)).

> `CLAUDE.md` imports this file and adds the guardrails a Claude session must never break; it never contradicts this file. Do not put instructions anywhere else.

**Starting a session — in this order:**
1. Read this file, [ORCHESTRATION](docs/agents/ORCHESTRATION.md), [REVIEW-ROUNDS](docs/agents/REVIEW-ROUNDS.md) and [LESSONS](docs/agents/LESSONS.md).
2. Look at the [issues of ezzz/HFRnow](https://github.com/ezzz/HFRnow/issues), not memory: the ones you claimed (a `/claim` comment with your session id), then `status: ready` issues nobody claimed (§7). [`docs/LOTS.md`](docs/LOTS.md) is the plan (scope, dependencies, routing) and links each lot to its issue.
3. Work only under an issue you claimed (§5). Every PR names its issue (`Closes #N`, or `Refs #N` for partial work; the only exceptions are a `Direct-PR: <reason>` small fix and Dependabot), and a lot PR its lot (`LOT-XXX`) (§8).
4. Get the PR reviewed by another model and handle bot rounds per REVIEW-ROUNDS. The author merges once the PR is merge-ready; risky flows and PRs whose author has no write access are merged by the core orchestrator or the maintainer (§8).
5. Before you stop: say where each lot you own stands (on its PR), and give back what you will not finish (`/release` on its issue, §5).

---

## 0. Guardrails (read first)

The **operator** is the human driving an agent session. Agents act on the operator's behalf and within the operator's permissions on this repository.

- **Routine work needs no extra confirmation**: your own branches, PRs, fixes to your open PRs, replies on your PRs, `/claim` and `/release` comments, and comments on the issues you claimed.
- **Consequential actions are confirmed by the operator first** (draft, show, wait): merges outside the §8 merge policy, releases and tags, anything on another repository, editing or closing what someone else wrote (back up, show the diff, apply, re-read), repository settings, new dependencies, disclosing a security finding, messages outside GitHub.
- How strictly confirmations apply, and whether they carry over to child sessions, is **the operator's call**. Personal rules belong in an untracked `CLAUDE.local.md` (or your tool's equivalent), not in this file.
- Merges to `dev-swift` happen through PRs with green checks; who may merge is governed by repository permissions.
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
| `App/` | iOS app target (SwiftUI), `App/SwiftHFR.xcodeproj` — see [App/README](App/README.md) and [ADR 0012](docs/adr/0012-app-project-file-strategy.md) |
| `docs/ARCHITECTURE.md` | Modules, dependency rules, design principles |
| `docs/ROADMAP.md` | Phases and their exit criteria |
| `docs/LOTS.md` | The migration plan: lots with scope, dependencies, model routing, each linked to its issue. Owners and status live on the [issues](https://github.com/ezzz/HFRnow/issues) |
| `docs/agents/` | [ORCHESTRATION](docs/agents/ORCHESTRATION.md) (parallel sessions), [REVIEW-ROUNDS](docs/agents/REVIEW-ROUNDS.md) (bots & reviews), [LESSONS](docs/agents/LESSONS.md) (self-review table), [EXTERNAL-AGENTS](docs/agents/EXTERNAL-AGENTS.md) (brief for contributors' agents: queues, claims, reviews, model matrix) |
| `docs/lots/` | One spec file per lot (`LOT-XXX-name.md`) |
| `docs/FEATURES.md` | App feature backlog (FEAT-XXX, with credit to who proposed it) and status; one spec per feature in `docs/features/FEAT-XXX.md` ([ADR 0011](docs/adr/0011-contribution-model-and-feature-intake.md) §2) |
| `docs/HFR-PROTOCOL.md` | What we know about HFR: URLs, forms, cookies, HTML structure |
| `docs/FIXTURES.md` | How fixtures are captured, anonymized and used |
| `docs/adr/` | Architecture Decision Records. A decision not in an ADR is not a decision |
| `.github/labels.yml` | The label taxonomy (§7) — the only place labels are defined |
| `scripts/configure-repo.sh` | Repository settings as code (protection, security features). Run by the maintainer |

**Documentation rules.** This file is the only entry point: every other document is reached from here. One file, one role (the [README map](README.md#documentation) lists them). A task works from **one** spec file — `docs/lots/LOT-XXX-*.md` for an engine lot, `docs/features/FEAT-XXX.md` for an app feature — plus the guardrails of this file. Do not create a new document when an existing one has that role; a one-off file (runbook, report) is deleted once its outcome is recorded in an ADR or in the file that owns the topic.

**Hosting** ([ADR 0010](docs/adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md)): SwiftHFR lives on the `dev-swift` branch of [ezzz/HFRnow](https://github.com/ezzz/HFRnow).
The default branch `master` of that repository **is the legacy app**: never branch from it, never target it, never let a session's `CLAUDE.md` from `master` drive work on SwiftHFR.

`francoisgn/ios-app_SwiftHFR` is a read-only mirror of `dev-swift`, synced hourly: never open issues or PRs there. Its issues are frozen history: read them for context (each lot issue links its old one), never claim, comment on or close them.

Legacy codebase (read-only reference): the `master` branch of ezzz/HFRnow. Citations written before the move point to <https://github.com/francoisgn/hfrnow> @ `2440d79` and stay valid.
When a behaviour is unclear, **read the legacy code** instead of guessing, and cite the file and line in the lot spec.

## 3. Ground rules

1. **No guessing about HFR.** Every URL, form field, cookie or HTML selector must be traced to the legacy code or a captured fixture, and recorded in `docs/HFR-PROTOCOL.md`.
2. **Respect module boundaries** ([ARCHITECTURE](docs/ARCHITECTURE.md)). `HFRParsing`, `HFRNetwork` and `HFRStorage` never import each other; multi-step flows live in `HFRClient`, which never imports `HFRStorage` ([ADR 0008](docs/adr/0008-hfrclient-orchestration-module.md)). Nothing in `HFRKit` imports SwiftUI or UIKit.
3. **No new dependency** without an ADR and the maintainer's approval. Today the only third-party dependency is SwiftSoup ([ADR 0002](docs/adr/0002-swiftsoup-html-parser.md)).
4. **Secrets never enter the repository**: no tokens, passwords, cookies, session IDs or signing material — not in code, fixtures, logs, tests or commit messages. Secrets live in GitHub Actions secrets; for local builds only in git-ignored configuration files as defined by [ADR 0007](docs/adr/0007-third-party-api-keys.md). Push protection and gitleaks will block you; never bypass them.
5. **Fixtures are anonymized before commit** ([FIXTURES](docs/FIXTURES.md)). A real pseudo, cookie or hash in a fixture is a security incident.
6. **Small, reviewable changes.** One lot or one issue per PR. No drive-by refactors.
7. **Don't work on something already claimed.** Claim its issue (`/claim <session-id>`) before coding (§5, [ORCHESTRATION](docs/agents/ORCHESTRATION.md#claims)).
8. **No hidden state.** Claims and status live on the issues, progress and blockers on issues and PRs, never only in a session's memory. Saw a problem that belongs to another lot? Say it on that lot's issue or PR, or add it to the lot's spec by PR; a new problem gets its own issue.
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

Each lot of `docs/LOTS.md` has one issue (`type: lot`) and follows exactly this loop ([ORCHESTRATION](docs/agents/ORCHESTRATION.md#claims)):

1. **Claim** — comment `/claim <session-id>` on the lot's issue **before** writing code. When an orchestrator session is active, it claims for you instead. The session id is `<host>/<name>`, e.g. `cloud/c12-sonnet`, `mac/M1`, `human/<login>`; keep it for the whole lot. Check first that the issue is `status: ready` (every dependency done, inputs available) and not `status: claimed`; the first claim wins. Until `issue-claims.yml` runs from `master`, the orchestrator or the maintainer sets `status: claimed` by hand (ORCHESTRATION).
   Stuck or stopping? Say on your PR and the issue what is done and what is left, then comment `/release`. A claim that looks abandoned for 24 h: ask the maintainer, never take it over.
2. **Spec** — write/complete `docs/lots/LOT-XXX-*.md`: legacy sources (file:line), inputs/outputs, edge cases, intentional differences from legacy, *pending capture* states. Verified protocol facts go to `docs/HFR-PROTOCOL.md` §6c under the lot's own `###` subsection.
3. **Fixtures** — real pages + legacy parser output (the oracle), anonymized. **Both must exist before you claim a parser lot** (LESSONS 35). A state that was not captured is listed as *pending capture* and opened as a capture issue (`host: mac`, `type: chore`) naming the lots that want it; never hand-build it in the cloud (LESSONS 36).
4. **Port** — implement in the right module, Swift-native, no ObjC.
5. **Differential tests** — the new code must reproduce the oracle output on every fixture. Differences must be justified in the spec (legacy bug fixed on purpose = documented).
6. **CI green** — build, tests, lint, CodeQL, secret scan.
7. **Review** — self-review against [LESSONS](docs/agents/LESSONS.md), then an **adversarial review** by a different model than the author (§6): the reviewer gets the diff, the lot spec and LESSONS, not the author's conclusions, and returns APPROVE or REQUEST CHANGES with numbered findings (severity, file:line, failing scenario, fix). Fix every finding in one commit per round, re-review until APPROVE. Bot rounds follow [REVIEW-ROUNDS](docs/agents/REVIEW-ROUNDS.md); security findings stay open until the operator decides.
8. **Close** — the PR says `LOT-XXX` and `Closes #N`. Merges into `dev-swift` do not close issues (ADR 0010): whoever merges closes it right after the merge (§8). Learnings go to [LESSONS](docs/agents/LESSONS.md).

## 6. Model routing (which agent does what)

Starting hypothesis, adjusted after the first lots (record changes here).

| Work | Model |
|---|---|
| Structuring decisions, ADRs on hard problems, the message parser (`ParseMessagesOperation` port) | Fable 5.1 |
| Audit synthesis, module design, sessions/auth/cookies, posting and other state-changing flows, all reviews of Sonnet work | Opus 5.5 |
| Bulk porting of well-specified lots, simple parsers, read-only fetchers and clients, storage, CI | Sonnet 5.5 |
| Mechanical work: fixture anonymization, renames, doc/label upkeep, convention checks | Haiku 5.5 |

Rule: **the reviewer is never the author model.** Opus-authored work is reviewed by Fable; Sonnet- and Haiku-authored work by Opus; Fable-authored work by Opus.
Sub-agents launched by a session work under the claim they are given, open one PR per lot, and never merge.

## 7. Labels and prioritization

Labels are defined in [`.github/labels.yml`](.github/labels.yml) and synced automatically. Issue forms and the labelling workflow only run from the default branch (the legacy `master`, ADR 0010), so for now labels are set by hand when an issue is opened.
Every issue carries one label per axis:

| Axis | Labels | Meaning |
|---|---|---|
| Type | `type: bug`, `type: feature`, `type: security`, `type: lot`, `type: roadmap`, `type: chore`, `type: docs` | What it is |
| Priority | `priority: high`, `priority: medium`, `priority: low` | How soon |
| Difficulty | `difficulty: trivial`, `difficulty: easy`, `difficulty: medium`, `difficulty: difficult` | Effort/risk — drives model routing (§6) |
| Area | `area: models`, `area: parsing`, `area: network`, `area: storage`, `area: client`, `area: app`, `area: tooling`, `area: ci`, `area: docs` | Where |
| Status | `status: needs-triage`, `status: blocked`, `status: ready`, `status: claimed` | Workflow state; `status: claimed` follows the active `/claim` (by hand until the claim workflow runs from `master`) |
| Host | `host: mac` | Needs the maintainer's Mac (Xcode, legacy app, live captures); cloud sessions leave it alone |

Credit labels: `moust4ki aka bybifok finding` marks work found by Bybifok; the fix credits them.

**Writing an issue:** it starts with `### Summary` (user story or two-line executive summary, §8), then scope, sources and acceptance criteria.

**Picking work:** `status: ready` issues that are not `status: claimed`, in this order: `type: security` first, then `priority: high` → `low`; among lots, the critical path (★ in `docs/LOTS.md`) and the lots that unblock others first.
Within a priority, match `difficulty` to your model tier (§6). Security issues are never reported publicly — see [SECURITY.md](SECURITY.md).

## 8. Git and PR workflow

- Integration branch: `dev-swift` (ruleset: PR + green checks required, squash only, no force push; `strict` is off, so no up-to-date-with-base requirement; auto-merge is allowed since 2026-10-28). `master` is the legacy app.
- Issue and PR numbers restart on ezzz/HFRnow: cite the old ones as `francoisgn/ios-app_SwiftHFR#N`.
- Branch names: `lot/XXX-short-name`, `fix/short-name`, `feat/short-name`, `chore/short-name`, `docs/short-name`.
- Commits: imperative mood, explain *why*. Reference the lot (`LOT-003`).
- **Every issue starts with `### Summary`**: a user story ("As a <who>, I want <what>, so that <why>") or a two-line executive summary, so a human judges the intent at a glance. Scope, sources and acceptance criteria come after. The issue forms ask for it once they run from `master`; meanwhile open a blank issue titled `[SwiftHFR] …` with one label per axis (§7). An issue without it gets `status: needs-triage` and a reminder.
- **Every PR has an issue claimed by its author**: `Closes #N` (or `Refs #N` for partial work, saying what is left) and, on its own line, `Claim: <session-id>` equal to the issue's active claim; a lot PR also names its lot (`LOT-XXX`). Break-glass: `Direct-PR: <reason>` for small fixes, labelled `direct-pr`, never for a lot. Anything that takes more than one session gets an issue first (a new lot also gets its row in `LOTS.md`). Dependabot PRs are exempt. The **Issue and claim** check (francoisgn/ios-app_SwiftHFR#100) enforces this once `pr-issue.yml` runs from `master`; until then reviewers check it. Details in [ORCHESTRATION](docs/agents/ORCHESTRATION.md#claims).
- **A merged PR closes its `Closes #N` issue** (a `Refs #N` issue stays open for the rest of the work). Every PR names its issue (`Closes #N`, or `Refs #N` for partial work), identified before the merge; a PR without one (and without a `Direct-PR:` reason, Dependabot excepted) is still merged, but flagged to the orchestrator as a tracking blind spot (find or open the issue, link and close it, find how the work started without one). Closing keywords do not fire on `dev-swift` (ADR 0010), so whoever merges closes the `Closes #N` issue right after the merge with the comment `Done in #PR (merged as <sha>)` and checks that it is closed: a merge normally means a closed issue. The PR author keeps that closure as a to-do until it is verified, and stays on the CI until it is green. The orchestrator uses a helper that does exactly this.
- **Before opening a PR or an issue, check for duplicates**: synonyms, titles and bodies, open and closed issues and PRs, plus `LOTS.md`. An older issue asking the same thing is the one to keep. A better PR already open → close ours with one sentence and a link.
- **Right before opening a PR**, search the open PRs that cite the same lot or touch the same files (e.g. `docs/HFR-PROTOCOL.md`): coordinate on their PR, or merge `dev-swift` once they land, instead of discovering the conflict at merge time.
- **Public actions outside this repository** (a post on the HFR forum, an issue or comment on another project, a message to another maintainer) are confirmed by the operator first (§0), then recorded on the related issue or PR, in the same work unit: the link, or, for a private channel (e-mail, chat), the channel and the date, never the private content. Other sessions learn our public footprint from there.
- **Legacy fixes**: a PR that fixes or deliberately changes a behaviour of the legacy app adds one line to [docs/CHANGELOG-LEGACY.md](docs/CHANGELOG-LEGACY.md) (French summary, lot/PR, legacy file:line or capture) — the base of the SwiftHFR v1 changelog.
- **PR description**, short, in order: `LOT-XXX` (lot PRs only), `Closes #N` (or `Refs #N` and what is left, for partial work; `Direct-PR: <reason>` for a small fix without an issue) and `Claim:`; the problem; the cause; what changed and why this wide and no wider; the tests (names, what they check, shown to fail without the change).
- **Merge policy** (operator, 2026-10-29): the author merges (squash) as soon as the PR meets the [merge criteria](CONTRIBUTING.md#2-merge-criteria) and has an adversarial APPROVE on its head; a merge-ready PR is never left open. State-changing flows, sessions, auth, cookies, tokens, security findings, `HFRModels` public types, ADRs and every PR whose author has no write access are merged by the core orchestrator or the maintainer. At most 5 open PRs per contributor id; 10 for Bybifok (moust4ki), counted across his `ext/bybifok-*` ids (operator, 2026-10-29). External contributors' agents follow [EXTERNAL-AGENTS](docs/agents/EXTERNAL-AGENTS.md); work open to them carries the `external: ready` label, reviews open to them a `REVIEW WANTED: <model>` comment.
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
- [ ] The PR says `Closes #N`; the issue is closed by hand, with the PR link, once the PR is merged

## 10. Environments

- **Linux cloud agents**: start every session with `git fetch origin dev-swift && git switch dev-swift` (the clone lands on the legacy `master`), then branch from it. They can edit code and docs and run `swift test` on `HFRKit` (keep the engine Foundation-only). The Swift toolchain comes from [`scripts/cloud-setup.sh`](scripts/cloud-setup.sh), pasted into the cloud environment's setup script (needs `download.swift.org` in the allowed domains). Cannot build the app.
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
- 2026-10-26 — LOT-001: Carthage on Xcode 27 needs `XCODE_XCCONFIG_FILE` (deployment target 15.0, no `-Werror`); the iOS 27.1 simulator runtime refuses iPhone 18 Pro, use 27.0. HFR's live behaviour differs from the docs in several places (cookies `md_user`/`md_passs`/`md_id`/`md_data`, two-hop topic redirect, shared flood limit): trust `docs/HFR-PROTOCOL.md` §6b/§7 results over audit notes.
- 2026-10-26 — Hosting move to ezzz/HFRnow `dev-swift` (ADR 0010): issue forms, Dependabot, scheduled workflows, `workflow_dispatch` and Scorecard only work from the default branch, which is the legacy app. The Claude and CodeRabbit GitHub apps on a personal-account repository can only be installed by its owner, whatever the collaborator's rights.
- 2026-10-27 — Hosting move: two sessions designed it in parallel and both wrote an ADR 0010; one branch was never merged and missed the cutover. Before a structural change, run `git fetch --all --prune`, list the branches not merged into the integration branch (`git branch -r --no-merged origin/dev-swift`) and decide the fate of each.
- 2026-10-26 — LOT-001: a first corpus PR leaked member pseudos on the public repo because the anonymizer's `check` reused the redactor's own selectors. Corpus checks must be independent of the redactor, and every corpus change gets an independent reviewer before it is pushed, not after (FIXTURES.md policy, LESSONS 33–34).
- 2026-10-27 — LOT-034: HFR nests the `<div style="clear: both;">` and the `div.edited` trailer **inside** `div#para<numreponse>`, between the body and the signature; the LOT-003 oracle's `html` is cut at the signature (`display_sig=no`) and had every `\n` deleted, so its text is compared with all whitespace removed. SwiftSoup 2.14 always writes void elements as `<br />`; Swift Testing takes literal `#expect` labels only (a `Comment` value is ambiguous with SwiftSoup's on Linux). SwiftSoup's `appendChild` walks up to the owner document recursively: build deep trees bottom-up (attach a subtree once complete), never top-down under an attached root.
- 2026-10-26 — LOT-002..004: the legacy oracle runs real legacy code from a test host via `tooling/legacy-oracle/run-oracle.sh`, with a local patch to hfrnow at 2440d79 (never pushed). Each oracle lot's `hfrnow.patch` is a superset of the previous one, and hfrnow must carry exactly the patch of the branch being run (the script refuses otherwise).
- 2026-10-27 — LOT-083: the reader's `WKWebView` runs no page script (`allowsContentJavaScript = false`, CSP `script-src 'none'` sent as a header by the app's `hfrreader:` scheme handler) while the app's adapter runs as a user script in its own `WKContentWorld`; every image goes through that scheme to policy C and the cookie-less client. App-hosted Swift Testing tests can drive a real `WKWebView`: test security claims there, not only on the HTML string.
- 2026-10-27 — LOT-036: read captures as bytes: a text-mode read turns the CRLF HFR stores in an edit or quote prefill into LF. SwiftSoup decodes entities in attributes and in `<textarea>` but keeps `\r\n` and a leading newline (a browser drops one), so the form parser normalises line breaks itself.
- 2026-10-27 — LOT-024: SwiftSoup `Element.ownerDocument()` is nil for elements of a document nobody retains, and elements of two parses of one page are never identical: keep the `Document` that produced the elements you match against.
- 2026-10-27 — LOT-037: a write answer is `success` only with HFR's own confirmation (refresh to the forum, a link-less `.hop` **and** "avec succès": login failure, empty lists and the search wait page also refresh with a link-less `.hop`); the legacy "no refusal found means success" turned the 99-byte bad-token reply into a success. The same `.hop` + link shape is a refusal after a write and "already alerted" before the alert form, so the classifier takes a context.
- 2026-10-27 — LOT-043: a login is validated in a fresh `HFRSession` and only then installed in the account's session (`LoginFlow`). Profile page 5 sets `md_user` and `md_passs` again (`R55-p5`): read a jar after the last request of a flow, not after the POST.
- 2026-10-27 — LOT-080: the app project uses folder-synchronized groups ([ADR 0012](docs/adr/0012-app-project-file-strategy.md)): add files under `App/SwiftHFR/` without touching `project.pbxproj`. A signed device build needs the team's account in the maintainer's Xcode (no profile on a fresh Mac); CI and agents build unsigned and never pass `-allowProvisioningUpdates`.
- 2026-10-27 — LOT-048: HFR's write bodies follow the form's document order, which `ForumForm` does not keep (`HopFormParser.layout` reads it), and a success-shaped answer is not enough: check the sentence of the write you sent (`W18`, mark unread, is a success too). A write whose POST may have left (a failure of the exchange itself) is `unconfirmed`, never retried; a failure before sending (cancellation checked first, a session refusal) is a plain `network` error.
- 2026-10-27 — LOT-047: the MP poll is one `GET /` in a probe session seeded from the account's cookies (`MPUnreadPoll`; a logged-in home sets cookies, never written back); its `nil` means no information (logged out or another page), never 0 and never proof of expiry: confirm with `SessionRefreshFlow`. The home page is the cheapest page with the entry and cannot mark flags read.
- 2026-10-27 — LOT-082: Swift typed-throws closures and `do` blocks infer `any Error` unless annotated (`() async throws(E) -> T in`, `do throws(E)`). Models keep content on a failed reload through one `ContentLoader`; reuse it for new list screens.
- 2026-10-27 — LOT-081: the app owns account sessions in one `AccountsModel` (`currentSession` = the current account's `HFRSession`, nil when logged out); forum screens take their session from it. Engine flows whose test seam is `internal` (`LoginFlow`'s jar) are wrapped by an app-side protocol for view-model tests. `HFRSession` rounds cookie expiries to the second: compare a jar with what it held before, never with the cookies that seeded it.
- 2026-10-28 — LOT-056: the legacy citations of the LOT-071 inputs are `2440d79` lines; `origin/master` has drifted (about 40 lines in `ReplyService.swift`), so cite the revision with every line range. A host table keeps what is not captured (E26 `Referer`, https support of http-only hosts) as data, not logic.
- 2026-10-28 — LOT-051: a flag write is confirmed only by its own `.hop` sentence (`addflag` "Favori positionné avec succès", `delflag` "Drapeau effacé avec succès"); `W18` confirms a mark unread and `P03d` a `delflag`, so neither confirms an `addflag` (nor `W18` a `delflag`). The `manageaction.php` answer is not captured, so the favourites-list removal stays `unconfirmed` until it is; legacy's body writes the form's end marker at index 1 whatever the list length (`R10` puts it at 2).
- 2026-10-27 — LOT-031: every per-message action link of a topic page lives in `div.toolbar`; legacy searched the whole message row, so when the toolbar lacked an action, a matching link a member posted in the message became that action, followed with the session. Scope per-message lookups to the toolbar.
- 2026-10-28 — LOT-032: SwiftSoup's `select` and `parents()` recurse per nesting level and crash a 512 KB thread at about 500 nested tables: walk a message's tree with an explicit stack.
- 2026-10-28 — LOT-119: a static function whose default argument reads `UIDevice.current` becomes `@MainActor` as a whole; keep the pure rule (idiom + setting → orientation mask) nonisolated and testable, and the device read in a thin overload. `LegacySettingsNormalizer.run` had no caller until the app launch in `SwiftHFRApp`; a "the app calls it at launch" note in a spec needs a grep for the caller.
- 2026-10-28 — LOT-095: a forum link's `page=` is not always the page: with `numreponse=M` the server picks the page (R25) and the topic list rows carry `page=1&numreponse=<last message>`. The router drops `page` then; never read `page=` alone to know where a link lands.
- 2026-10-27 — LOT-044: a `.hop` refusal can hold a non-empty `hash_check` in its replay form although the POST carried no cookies (`W17c`); a non-empty token is evidence of a logged-in session only on the expected profile-page GET, after its URL and `.hop` checks. Session refresh runs in a probe jar and writes back by compare-and-set, so it never undoes a concurrent request nor logs an account out on an unknown page.
- 2026-10-28 — #314: HFR answers a cookie-less `addflag` with the logged-in success bytes (`P03q` = `P03a`) and a repeated `delflag` with the same success (`P03o` = `P03n`). A write whose answer carries no token proves nothing about the session: check the session (LOT-044) before sending it. Test the public entry points with a scripted check (`TopicFlagFlow(refresh:)`) and a session that may only contact the loopback host (`hosts: .exactHost`), so the write itself can never reach HFR. The `manageaction.php` answer is captured now (`P03h`, `P03j`, `P03l`) and confirms the list removal: this supersedes the 2026-10-28 LOT-051 entry above on that point.
