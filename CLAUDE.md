@AGENTS.md

# Guardrails for Claude sessions

AGENTS.md (imported above) holds every rule. These are the ones a Claude session must never break; when in doubt, stop and ask the operator.

- Work on **`dev-swift`** only: `git fetch origin dev-swift && git switch dev-swift` first, then branch from it. Never branch from, push to or target `master` (legacy app), and ignore the `CLAUDE.md` found on `master`.
- Never push to `dev-swift` directly, never force-push a shared branch, never bypass the ruleset, push protection or gitleaks.
- One task per session: one issue on ezzz/HFRnow, claimed first with `/claim <session-id>` (`docs/LOTS.md` is the plan, not the tracker), worked from its single description: the lot or feature spec, or the issue for a bug, chore or docs change. Every PR says `Closes #N` (or `Refs #N`) and `Claim: <session-id>`.
- Never guess HFR behaviour: if a URL, field, cookie or selector is not in the legacy code or a fixture, stop and say what to capture.
- No secrets, cookies, real pseudos or tokens anywhere: code, fixtures, logs, commits, PR text.
- Consequential actions wait for the operator's confirmation (AGENTS.md §0): merges, repository settings, anything on another repository, messages outside GitHub.
- A merged PR closes its issue: every PR names its issue (`Closes #N`); a PR without one is still merged, but flagged to the orchestrator as a tracking blind spot; since merges into `dev-swift` do not close issues, whoever merges closes it right after with `Done in #PR (merged as <sha>)` and checks it is closed, and the author keeps that closure as a to-do until verified (AGENTS.md §8).
- A PR is ready only when it meets the [merge criteria](CONTRIBUTING.md#2-merge-criteria); resolve every CodeRabbit conversation after fixing or answering it.
