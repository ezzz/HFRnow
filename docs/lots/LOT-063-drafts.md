# LOT-063 — Drafts per context

- **Module:** HFRStorage
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [D §4, §8 (D12)](../audit/D-posting.md), [E §3.2, §8 (E-4)](../audit/E-storage-vendors.md), [redface2 comparison](../research/redface2-comparison.md) (per-account drafts with a retention TTL).

| Legacy | What it gives the store |
|---|---|
| `HFRswift/Swift/MessagesView.swift:2668`, `AnswerView.swift:28-35, 262-267, 702-705` | one global `@AppStorage("composerDraftText")`; saved on dismiss, cleared after a successful post, only for the plain reply composer |
| `HFRswift/Swift/MessagesView.swift:3512, 3542-3548, 3842-3849` | quote, edit and MP composers do not persist (they must not touch the reply draft) |
| `HFRswift/Swift/MainWindow.swift:277, 828` | new-topic draft is `@State`: lost on relaunch |
| `Classes/AddMessageViewController.m:69, 481-484, 601-603` | legacy-of-legacy global `brouillon` key |

## Behaviour
Code in `Sources/HFRStorage/Drafts/`, tests in `Tests/HFRStorageTests/Drafts/`.

- **`DraftContext`**: `reply(topic:page:)`, `newTopic(forum:)`, `privateMessage(recipient:)`, `edit(topic:post:)` and `legacyGlobal` (the old single draft, filled by LOT-067). `storageKey` is the identity; the recipient is compared without case and zero-width spaces.
- **`Draft`**: context, account, text, optional subject (new topics and MPs), `updatedAt`.
- **`DraftStore`** (actor): `draft(for:account:)`, `drafts(account:)` (newest first), `save(_:subject:for:account:)`, `discard(for:account:)` (after a successful post), `discardAll(account:)` (logout), `purgeExpired()`, `reload()`. Drafts are scoped per account (normalised like pseudos).
- **Saving empty text and empty subject removes the draft**; nothing empty is stored, and no write happens when nothing changed.
- **TTL**: 30 days from the last save (`defaultTimeToLive`); reads ignore expired drafts, every save also drops them from the file, `purgeExpired()` is for launch. A draft exactly at the TTL is still live.
- **Size bound**: at most 100 drafts (`defaultMaximumCount`); the least recently saved are dropped. Text length is not capped (a forum post is bounded by the forum).
- **Persistence**: `DraftPersistence` protocol, `FileDraftPersistence` (atomic JSON write, ISO 8601 dates), `InMemoryDraftPersistence`. Every save rewrites the file: the composer should debounce (for example one save per second and on dismiss).
- **Recovery**: undecodable data or a newer format version is moved to `drafts.json.corrupt` (an earlier one is renamed with a unique suffix, never deleted) and the store starts empty (`didRecoverFromCorruptData()`): a draft is not worth blocking the composer. An I/O failure while reading (not a decoding problem) blocks writes until `reload()` succeeds, so a transient error never replaces good data. A failed save leaves memory unchanged.

## Edge cases
- The clock is injected (`clock:`) so TTL tests are deterministic.
- Dates are written with second precision; TTL arithmetic does not depend on the sub-second part.
- Subject-only drafts count as drafts.
- Private message recipients containing `:` or any character cannot collide with other kinds: the key prefix (`mp:`) differs and the recipient is the last component.
- `reply` keeps the page in the key (brief: reply per topic and page); an app that wants one reply draft per topic passes a constant page.

## Fixtures
None (synthetic). Cursor position and attachment metadata (E-4 "optional") are not stored: no consumer yet.

## Intentional differences from legacy
- The global draft is replaced by per-context drafts; the new-topic draft now survives a kill; edit and MP composers get drafts instead of none.
- The "ephemeral composers never touch the reply draft" rule holds by construction (separate contexts) and is tested.
- The pseudo comparison form is duplicated in a private helper (`DraftNameNormalizer`) so that this lot does not depend on LOT-061; the two can be unified later.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- Distinguish "cannot decode" (set the data aside, carry on) from "cannot read" (stop writing) when a load fails.
