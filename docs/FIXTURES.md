# Fixtures

Fixtures are real HFR pages used to test parsers, paired with the **oracle**: the output of the legacy parser on the same page.

## Layout
`Packages/HFRKit/Tests/HFRParsingTests/Fixtures/<lot>/<case>.html` and `<case>.oracle.json`.

## Anonymization (mandatory before commit)
Replace, consistently within a fixture:
- pseudos and profile links of real members → `user1`, `user2`, …
- cookies, session IDs, `hash_check` and any form token → `REDACTED`
- private message content → placeholder text
- e-mail addresses, IPs → placeholders

Public forum post content may stay when needed for the test; prefer neutral excerpts.
A reviewer must check anonymization; gitleaks runs on every push as a safety net.

## Capture
Done in Phase 2 with a harness in the legacy app, run on the maintainer's Mac. Procedure documented here when built.
