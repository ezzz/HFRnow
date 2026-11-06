# 0007 — Third-party API keys are injected, never committed

**Status:** Accepted — 2026-10-24 (maintainer, after the LOT-000 reviews)

## Context
The legacy app hard-codes the Giphy and image-rehost API keys in its Swift sources (audit E §5, D §5). In a public repository they are exposed to anyone.

## Threat model
Keeping keys out of the repository stops casual reuse from the source, **not** extraction from the shipped app: anyone can pull a key out of the IPA. The real mitigations are provider-side (quotas, rotation, restrictions) or a relay the project operates. A client app cannot keep an embedded key secret.

## Key ownership
| Key | Owner | Rotation |
|---|---|---|
| Image rehost (Chevereto, `img3.super-h.fr`) | Community host operator, not this project | Requires its operator |
| Giphy | The developer account that created it | That account's owner |

## Decision
- Keys are provided at build time through an untracked configuration file (git-ignored `.xcconfig`, with a committed `*.example`; the only local exception to AGENTS.md ground rule 4, guarded by `.gitignore`, gitleaks and push protection) and, in CI, through GitHub Actions secrets used **only by the app build job**.
- Engine clients take keys and base URLs as parameters; `swift test` on Linux never needs a real key (tests use fakes).
- **For now the legacy key values are reused** (maintainer decision, 2026-10-24): they are placed in the local untracked configuration and in a GitHub Actions secret, never in the repository. Replacing them later only means changing those two places; rotation by each key's owner remains recommended since the values are public in the legacy repository history.
- Hard-coded third-party endpoints and personal addresses (`aq.super-h.fr`, `marc@hardware.fr`, the account-deletion recipient) are configuration too, decided per feature (Q-4, Q-10).

## Alternatives considered
- **User-supplied key in Settings** (works for Giphy's free tier): kept as an option for Giphy in Phase 4.
- **Maintainer-run relay** holding the keys server-side: strongest, but adds an operated service. Out of scope for now.
- **Drop the features** (GIF picker, rehost) if no acceptable key arrangement exists.

## Consequences
- A fresh clone builds without keys; features needing them are disabled with a clear message.
- gitleaks and push protection guard against regressions.
