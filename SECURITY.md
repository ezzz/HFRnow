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
- Dependabot alerts and updates, dependency review on every PR (SCA)
- Actions pinned by commit SHA, least-privilege workflow tokens
- Protected integration branch (`dev-swift`) with mandatory checks
