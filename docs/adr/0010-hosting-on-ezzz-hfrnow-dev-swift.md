# 0010 — Hosting on ezzz/HFRnow, branch `dev-swift`

**Status:** Proposed — 2026-10-26 (maintainer; becomes Accepted when the cutover in [EZZZ-CUTOVER](../migration/EZZZ-CUTOVER.md) is done)

## Context
SwiftHFR was developed on `francoisgn/ios-app_SwiftHFR`. The community app lives on [ezzz/HFRnow](https://github.com/ezzz/HFRnow), a personal-account repository whose default branch `master` is the legacy app (Objective-C + Swift). The maintainer is a `write` collaborator there: on a personal-account repository only the owner is admin, so rulesets and security settings are applied by the owner (`.github/rulesets/*.json` are importable from the web UI).
The project moves into that repository so that the successor sits next to the app it replaces, on a dedicated branch.

## Decision
- SwiftHFR lives on **`dev-swift`**, imported with its full history by a direct push (no PR: the code was already reviewed, so CodeRabbit does not re-review it).
- `dev-swift` is protected by a **ruleset scoped to that branch** (PR, the CI checks of ADR 0005, squash only, linear history, no force push, no deletion). Repository-wide settings are not changed without the owner's agreement, because they also govern the legacy `master`.
- Everything in ADR 0005 is kept, with these differences imposed by GitHub, which only reads some files from the default branch:

| Feature | On `dev-swift` | To restore it |
|---|---|---|
| CI, CodeQL on push/PR, gitleaks, dependency review | Works | — |
| CodeRabbit | Works on PRs into `dev-swift` (`base_branches`); owner installs the app | — |
| CodeQL weekly schedule | Inert | Lands with `dev-swift` becoming default, or a copy on `master` |
| Dependabot version updates | Inert | `.github/dependabot.yml` (every entry `target-branch: dev-swift`) copied to `master` by a PR the owner merges |
| Dependabot alerts on our dependencies | Not computed (dependency graph follows the default branch) | Same; dependency review still blocks new vulnerable dependencies on PRs |
| Issue forms, auto-labelling | Inert | `.github/ISSUE_TEMPLATE/` and `issue-triage.yml` on `master`, owner's decision since issues are shared with the legacy app |
| Issue claims (`issue-claims.yml`: `/claim`, `/release`, `status: claimed`) | Inert: `issue_comment` runs the default branch's copy, and Issues are disabled on ezzz/HFRnow | Issues enabled and `issue-claims.yml` + `scripts/issue_claims.py` on `master`, owner's decision. Meanwhile `docs/LOTS.md` is the only tracker (below) |
| Required check **Issue and claim** (`pr-issue.yml`) | Inert: `pull_request_target` runs the default branch's copy (GitHub change of 2025-11); not in the `dev-swift` ruleset, or no PR could merge | Same, then add it to `dev-swift.json` |
| Closing keywords (`Closes #N`) | No effect: GitHub only closes issues on merges into the default branch | Close the issue by hand after the merge, once there are issues |
| Label sync | `push` trigger works; manual dispatch does not | `scripts/configure-repo.sh` syncs labels |
| OpenSSF Scorecard | Removed: it only runs from the default branch and scores it, i.e. the legacy app, and would publish that score and file its findings in the shared Security tab | Re-add when `dev-swift` becomes default |
| Dependabot security updates | Off: they only open PRs against the default branch | Same as Scorecard |
| Repository license detection | GitHub shows the legacy `master`'s license | `dev-swift` carries its own `LICENSE` (ADR 0003) |

## Consequences
- Issue and PR numbers restart at ezzz/HFRnow's counters; older references are written `francoisgn/ios-app_SwiftHFR#N`. Issues cannot be transferred across owners: open ones are recreated once Issues are enabled on ezzz/HFRnow.
- **Tracking until Issues are enabled on ezzz/HFRnow**: `docs/LOTS.md` on `dev-swift` is the only tracker — owner and status per lot, claimed and released by PR, PRs name their lot (`LOT-XXX`). The issue-claim process of francoisgn/ios-app_SwiftHFR#100 stays documented as the target ([ORCHESTRATION](../agents/ORCHESTRATION.md#target-process-once-ezzz-enables-issues)) and its workflows stay inert. The mirror's issues are frozen history: linked from `LOTS.md` for context, never claimed or closed there, and hidden when Issues are disabled on the mirror (cutover step 7).
- Cloud sessions clone the default branch: agents must switch to `dev-swift` first (AGENTS.md §10).
- Nothing of SwiftHFR acts on `master`: Dependabot entries target `dev-swift`, CodeRabbit auto-review on `master` follows the owner's CodeRabbit settings, and an optional ruleset (`configure-repo.sh --guard-master`) keeps every GitHub app, Claude included, from updating `master`.
- `francoisgn/ios-app_SwiftHFR` becomes a read-only mirror of `dev-swift`: `mirror-from-ezzz.yml` fast-forwards its `master` hourly with a deploy key (`GITHUB_TOKEN` cannot push workflow changes), and a ruleset lets only that key and admins update it. PRs go to ezzz/HFRnow; issues too, once enabled there.
