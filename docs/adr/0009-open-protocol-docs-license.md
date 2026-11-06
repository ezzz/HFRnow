# 0009 — Protocol documentation and fixtures under CC BY 4.0

**Status:** Accepted — 2026-10-25 (maintainer)

## Context
Knowledge of the HFR protocol is the most reusable asset of this project, and other community clients (notably the redface2 Android app, GPL-3.0) hold complementary knowledge. Our code license (PolyForm Noncommercial, ADR 0003) and theirs are incompatible, so neither project can copy the other's code or text. Code would be rewritten in Swift anyway; what is worth sharing is documentation and test data.

Options: switch the code to GPL-3.0 (loses the noncommercial clause, App Store friction, little gain since code is rewritten), switch to MIT/Apache (cannot absorb GPL either), or open only the documentation and fixtures.

## Decision
- Code stays under PolyForm Noncommercial 1.0.0.
- `docs/HFR-PROTOCOL.md` and the parsing fixtures (`Packages/HFRKit/Tests/**/Fixtures/`) are licensed under **Creative Commons Attribution 4.0 International (CC BY 4.0)**, see `LICENSE-docs.md`.
- Facts learned from other projects are rewritten in our own words and marked by source until verified with our own fixtures; their text, code and fixtures are not copied unless their authors grant a compatible license.
- We propose the same arrangement to the redface2 maintainer, aiming at a shared protocol specification and a shared MPStorage contract.

## Consequences
- Anyone, including GPL projects, can reuse our protocol documentation and fixtures with attribution.
- Contributions to these files are accepted under CC BY 4.0 (CONTRIBUTING.md).
