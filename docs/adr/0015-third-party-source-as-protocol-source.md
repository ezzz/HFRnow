# 0015 — Third-party open-source code as a protocol source

**Status:** Proposed — 2026-11-09 (session `cloud/i573-opus`, requested by the operator on [#573](https://github.com/ezzz/HFRnow/issues/573), 2026-11-07; merged by the core orchestrator or the maintainer, AGENTS.md §8)

## Context

AGENTS.md ground rule 1 traces every protocol fact to the legacy code or a captured fixture, and [ADR 0004](0004-legacy-app-as-oracle.md) makes captures and the legacy oracle the reference of our tests. Some services the app talks to are not HFR and are run by community members who publish their server code. The first case is the "Alerte Qualitaÿ" service (`aq.super-h.fr`): its operator, roger21, publishes the server (`roger21/toyo`, folder `aq/`) and a reference userscript (`roger21/hfr`), both under AGPL-3.0, and told the operator that the published `aq/` code is what runs in production, connection settings aside (#573).

That source answers questions no capture can answer safely: some refusal states of `addAlerte.php` delete AQs and ban the client's address, so they must never be produced on the live host. It also holds what a capture cannot show (the database's unique keys, the column lengths, what the server stores and e-mails). Two constraints apply: the code is AGPL-3.0 while this repository is PolyForm Noncommercial ([ADR 0003](0003-polyform-noncommercial-license.md)) and our protocol docs are CC BY 4.0 ([ADR 0009](0009-open-protocol-docs-license.md)); and a published repository may also hold personal data (the AQ repository's `aq/sql/db.sql` is a real data dump with real pseudos).

### Options considered

1. **Ignore third-party sources**: captures only. Refusal states that ban or delete stay unknown, or are probed on the live host, which harms the service and its users. Rejected.
2. **Treat the source as an oracle**, like the legacy app. A published repository can differ from what runs, and nothing pins what runs; the oracle must stay something we observed. Rejected.
3. **A secondary source, read at a pinned commit, facts only, captures stay the oracle.** Chosen.

## Decision

1. **Secondary source.** Published source code of a third-party service may document that service's protocol. Every fact cites `owner/repo@<full SHA>:<path>:<line>` (a short SHA in running text once the full one is given), in `docs/HFR-PROTOCOL.md` under a paragraph headed "server source (secondary, not a capture)". The commit is pinned; moving to a newer one is a docs PR that re-reads every cited line.
2. **Facts, never code.** We record what the code does, in our own words: URLs, fields, codes, limits, the order of checks. No code, query or configuration value is copied into this repository (code, docs, fixtures, tests), and none is vendored. Data in a published repository (dumps, logs, keys that identify a person) is never copied: only the lines a doc cites are read, and a schema is described, not pasted.
3. **Captures stay the oracle.** A fact from the source is marked as such; it is **verified** only once a capture shows it. When a capture and the source disagree, the capture wins and the difference is recorded. Tests decode captures, never a state built from the source alone (LESSONS 36).
4. **The safe side.** A state known only from the source is handled as the most cautious reading allows: an unclear answer is a refusal, never a success; a write the source may refuse or punish is sent once and never retried; the client does not depend on a behaviour the source shows but no capture confirms.
5. **Local instance.** A refusal state that would harm the live service or its users (deleting data, banning an address) may be captured from a local instance of the source: the pinned SHA, run unmodified on the loopback address of the maintainer's Mac, with an empty database (schema only) and fake values only. Its fixtures carry `origin: local-instance` in their manifest row and say which host's headers they hold; they never stand for the live host's front server.
6. **No third-party server in CI.** Running a third-party server in CI (a container, a service job) needs its own ADR: licence, supply chain and network rules of [ADR 0005](0005-ci-and-supply-chain-security.md) apply.
7. **People.** Contacting the author of a source is a public action that waits for the operator (AGENTS.md §0); what they say is recorded on the issue as facts, with the channel and the date, never the private content.

## Consequences

- The AQ contract is documented in HFR-PROTOCOL §8 from `roger21/toyo@96c0aea` and `roger21/hfr@b8d110b` (#573); its refusal states come from a local instance (`T52`-`T71`, #574), its success from the live host (`T50`, `T51`, #531).
- A reviewer of such a doc checks each cited line at the pinned SHA, and that nothing was copied.
- When the third-party service changes, our docs may be stale until the pin moves; the captures and the client's safe-side handling bound the risk.
- Nothing of the third-party code enters this repository; any future need that would bring it in (vendoring, a CI service) is the separate ADR of point 6, licence question included.
