@AGENTS.md

# Guardrails for Claude sessions

AGENTS.md (imported above) holds every project rule, and wins over the framework block at the end of this file (AGENTS.md §12). These are the ones a Claude session must never break; when in doubt, stop and ask the operator.

- Work on **`dev-swift`** only: `git fetch origin dev-swift && git switch dev-swift` first, then branch from it. Never branch from, push to or target `master` (legacy app), and ignore the `CLAUDE.md` found on `master`.
- Never push to `dev-swift` directly, never force-push a shared branch, never bypass the ruleset, push protection or gitleaks.
- One task per session: one issue on ezzz/HFRnow, claimed first with `/claim <session-id>` (`docs/LOTS.md` is the plan, not the tracker), worked from its single description: the lot or feature spec, or the issue for a bug, chore or docs change. Every PR says `Closes #N` (or `Refs #N` for partial work) and `Claim: <session-id>`; a small fix without an issue says `Direct-PR: <reason>` instead.
- Never guess HFR behaviour: if a URL, field, cookie or selector is not in the legacy code or a fixture, stop and say what to capture.
- No secrets, cookies, real pseudos or tokens anywhere: code, fixtures, logs, commits, PR text.
- Consequential actions wait for the operator's confirmation (AGENTS.md §0): merges outside the AGENTS.md §8 merge policy, repository settings, anything on another repository, messages outside GitHub.
- A merged PR closes its `Closes #N` issue (a `Refs #N` one stays open): every PR names its issue (`Closes #N`, or `Refs #N` for partial work); a PR without one (and without a `Direct-PR:` reason, Dependabot excepted) is still merged, but flagged to the orchestrator as a tracking blind spot; since merges into `dev-swift` do not close issues, whoever merges closes it right after with `Done in #PR (merged as <sha>)` and checks it is closed, and the author keeps that closure as a to-do until verified (AGENTS.md §8).
- A PR is ready only when it meets the [merge criteria](CONTRIBUTING.md#2-merge-criteria); resolve every CodeRabbit conversation after fixing or answering it.

<!-- harness:begin cadre -->
## Shared framework: agentic-harness 0.3.0

This block is managed by `scripts/harness-sync.sh`, which lives in the [agentic-harness](https://github.com/francoisgn/agentic-harness) framework repository, not in this one: do not edit it here (propose changes in the framework). To update it: the `/harness-update` skill, or, from this repository's root, clone the framework at the wanted tag next to it (`git clone --depth 1 --branch vX.Y.Z https://github.com/francoisgn/agentic-harness.git ../agentic-harness`) and run `../agentic-harness/scripts/harness-sync.sh --target .` (`.harness/docs/ADOPTION.md` §Mises à jour).

**Precedence**: project rules win over the framework. The project records each departure from the framework, with its reason, in the "Harness overrides" section of its `AGENTS.md`; its settings go in `.harness/config.json`; everything outside this block belongs to it. Order on a conflict: the "Harness overrides" section, then the rest of the project's rules (`AGENTS.md`, `CLAUDE.md`), then `.harness/config.json`, then `.harness/docs/`. Report an unresolved conflict in an issue of the project.

@.harness/docs/ESSENTIEL.md

Read when relevant (not loaded by default; written in French): method `.harness/docs/METHODOLOGY.md`, conventions `.harness/docs/CONVENTIONS.md`, lessons `.harness/docs/LESSONS.md` (self-review before every PR, alongside the project's own lessons), reviews `.harness/docs/REVIEW-ROUNDS.md`, orchestration and model choice `.harness/docs/ORCHESTRATION.md`, branches and releases `.harness/docs/BRANCHING-RELEASE.md`, CI budget and security `.harness/docs/CI-BUDGET.md`, Mac handoff `.harness/docs/MAC-HANDOFF.md`.
<!-- harness:end cadre -->
