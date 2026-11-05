# 0005 — CI and supply-chain security baseline

**Status:** Accepted — 2026-10-24

## Decision
| Concern | Tool |
|---|---|
| Build & tests | GitHub Actions: Linux (`swift:6.2` container) + macOS runner `xcode-27` |
| Lint | SwiftLint (container image pinned by version) |
| SAST | CodeQL (Swift, Actions) |
| SCA | Dependabot (Swift, GitHub Actions) + dependency review on PRs (fails on moderate+) |
| Secrets | GitHub secret scanning + push protection, gitleaks in CI |
| Supply chain | Actions pinned by commit SHA, `permissions: read-all` by default, OpenSSF Scorecard |
| Review | CodeRabbit on every PR + branch protection |
| Triage | Issue forms + label sync + deterministic auto-labelling (`actions/github-script`) |

## Consequences
- Xcode 27 is only available on the preview `xcode-27` runner label as of 2026-10; switch to a stable label when GitHub publishes one.
- An AI triage layer (duplicates, severity suggestion) may be added later (separate ADR; needs an API key secret).

## Amendment — 2026-11-05 (#477, operator decision)
macOS runners are the scarce resource: on 2026-11-05 the required `Analyze (swift)` was cancelled for lack of a runner on every PR for hours, while the app build, the check that caught the day's bugs, was not required.
- CodeQL Swift (SAST) stays, but runs on every push to `dev-swift` and on a PR only when it carries the `codeql` label (session, cookies, tokens, posting). It is no longer a required PR check; a finding on `dev-swift` is handled like any other.
- `App build + tests (iOS 27 simulator)` becomes a required check (skipped, and passed, when the app is untouched).
- The macOS jobs of CI that a change needs do not run on draft PRs (a Linux gate fails them at once, so a draft run can never report them green) and run on `ready_for_review`; Linux jobs run on every push.
