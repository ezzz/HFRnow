# 0003 — PolyForm Noncommercial license

**Status:** Accepted — 2026-10-24

## Context
SwiftHFR is a community app, successor of a chain of forks, meant to be freely reused but not monetized, with credit to its authors.
OSI licenses (MIT, GPL) allow commercial use; Creative Commons licenses are not designed for software.

## Decision
License the project under [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0). Credits are kept in `CREDITS.md`.

## Consequences
- Not "open source" in the OSI sense (source-available, noncommercial). Some tools free "for open source" judge eligibility on public visibility, not license; to be checked per tool.
- Legacy code had no explicit license; we can license our own contributions. Reused legacy code is credited, and its authors are acknowledged in `CREDITS.md`.
- Third-party dependencies keep their own licenses (SwiftSoup: MIT).
