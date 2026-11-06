# 0004 — Legacy app as oracle, differential testing

**Status:** Accepted — 2026-10-24

## Context
HFR's HTML has many undocumented edge cases. The legacy parsers encode years of fixes. Porting "by reading" risks silent regressions.

## Decision
- Real pages are captured as fixtures, and the legacy parser's output on them is exported as JSON (the oracle).
- Each ported parser must reproduce the oracle on every fixture. Deviations are allowed only when documented in the lot spec (legacy bug fixed on purpose).
- Fixtures are anonymized before commit (`docs/FIXTURES.md`).

## Consequences
- Requires a capture harness in the legacy app (Phase 2), run on a Mac.
- Parity is measurable; reviewers check tests, not intuition.
