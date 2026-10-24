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
