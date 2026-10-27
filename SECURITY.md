# Security policy

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private reporting:
[Report a vulnerability](https://github.com/ezzz/HFRnow/security/advisories/new).

Please include the affected version/commit, reproduction steps and the impact.
You will get an acknowledgement as soon as possible; this is a volunteer project, so please be patient.

## Scope

In scope: the app and the `HFRKit` engine — credential and cookie handling, session storage, HTML/BBCode injection in rendered content, insecure network usage, leaked secrets in the repository or its fixtures.
Out of scope: vulnerabilities of forum.hardware.fr itself (report them to Hardware.fr).

## What protects this repository

- Secret scanning with push protection, plus gitleaks in CI
- CodeQL static analysis (SAST)
- Dependency review on every PR (SCA). Dependabot version updates target `dev-swift` and run once the owner adds `.github/dependabot.yml` to `master`; Dependabot alerts follow the default branch (`master`) and do not cover dependencies that exist only on `dev-swift` ([ADR 0010](docs/adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md))
- Actions pinned by commit SHA, least-privilege workflow tokens
- Protected integration branch (`dev-swift`) with mandatory checks
