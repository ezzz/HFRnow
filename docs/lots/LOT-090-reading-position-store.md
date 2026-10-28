# LOT-090 — Reading-position store

- **Module:** HFRStorage
- **Difficulty / model:** easy (Opus 5.5 → Fable; the plan routes Sonnet → Opus, this lot was taken by an Opus helper)
- **Issue:** [#182](https://github.com/ezzz/HFRnow/issues/182)
- **Depends on:** LOT-013 (#46): `TopicID`, `CategoryID` (HFRModels)
- **Implements:** FEAT-001 (#145), FEAT-007 (#151), FEAT-015 (#159), all proposed by Bybifok ([`moust4ki`](https://github.com/moust4ki)); credit in [CREDITS.md](../../CREDITS.md)

## Legacy sources

Legacy app: `origin/master` of ezzz/HFRnow @ `21173e7`. Legacy never persisted a reading position: this is a new capability.

| Legacy | What it gives this lot |
|---|---|
| `HFRswift/Swift/MessagesView.swift:796-801` (`WebView.ScrollPosition`) | the position legacy tracked: scroll `y`, viewport and content height, and `visibleAnchor`, held in `@State` (`lastWebViewScrollPosition`, `:3091`, set at `:5240-5241`) and lost when the screen or the app closes |
| `MessagesView.swift:979-1005` (`postAnchorForMessage`, `visiblePostAnchor`) | the anchor is the `t<numreponse>` of the topmost visible message |
| `backlog.md:72, 78` (HFR-002, HFR-009) | legacy moved from restoring a scroll offset to restoring a message anchor, because offsets broke after a reply or a refresh: the message number is the primary key of a position, the offset only refines it |
| `MessagesView.swift:3484-3494` (`updateMPStorageFlagIfNeeded`) | the one forward-only rule legacy had: the MPStorage flag of a multi-recipient MP is written only when the page is not lower than the stored one (`guard pageToSave >= currentStoredPage`) |

## Behaviour

Code in `Sources/HFRStorage/ReadingPositions/`, tests in `Tests/HFRStorageTests/ReadingPositions/`.

- **`ReadingPosition`** (`Codable`, ids and integers only, operator note on #182): `page` (from 1), `messageNumber` (`numreponse` of the topmost message seen, optional), `offset` (inside that message, the app's own unit, optional), `updatedAt` (when recorded; LOT-172's iCloud mirror keeps the newest per topic).
- **Order** (`isAhead(of:)`): when both positions have a message number, the message number decides, then the offset (nil = 0); otherwise the page decides, and on the same page a known message beats an unknown one. `updatedAt` plays no part. Message numbers grow in posting order (HFR-PROTOCOL §6c LOT-090), and they survive what moves pages (deletions), so a later message on an earlier page is still ahead.
- **`ReadingPositionStore`** (actor), keyed by account identifier and `TopicID` (category **and** topic number):
  - `advance(_:to:account:)` records the position only when it is ahead of the stored one (or none is stored); otherwise it returns false and writes nothing. `reset(_:to:account:)` records it whatever the stored one (explicit backwards move).
  - `position(of:account:)`, `records(for:)` (most recently updated first: what the iCloud mirror will take the head of).
  - `remove(_:account:)`, `removeAccount(_:)` (account removed from the app).
  - **Bounded per account**: `limitPerAccount` (default 500, at least 1). Writing a new topic beyond the limit evicts the least recently updated topics of that account; the record just written is always kept, even if its date is the oldest (device clock moved back). Other accounts are never evicted.
- **Accounts** are the caller's `Account.id` (the `md_user` value), compared exactly. No normalisation, unlike LOT-061's `PseudoNormalizer`: the app's own identifier is already exact, and a normaliser that changes later (LOT-072, #96) would re-key every position.
- **Persistence** (`ReadingPositionPersistence`: `load`, `save`, `quarantineUnreadableData`): `FileReadingPositionPersistence` (one JSON document, `Data.write(options: .atomic)`, dates as seconds since 1970) and `InMemoryReadingPositionPersistence`.
- **Failure guard** (same rule as LOT-061): a document that cannot be read or decoded, or whose `version` is newer than this code, makes reads answer nothing and every write throw (`loadFailed`, `unsupportedVersion`); nothing is saved over it. Ways out: `reload()` or `discardUnreadableData()` (moves the file to `<name>.corrupt`, an earlier backup kept under a unique name, never deleted). A failed save throws `saveFailed` and leaves memory unchanged.

## Edge cases

- Same position again (equal message and offset, or equal page without message numbers): `advance` returns false and does not save; the date is not refreshed, so `updatedAt` stays the time the position last moved.
- Invalid input is refused before anything is written: empty account (`emptyAccount`), topic number ≤ 0, page < 1, message number ≤ 0 or negative offset (`invalidPosition`).
- Same topic number in two categories, or a private-message thread with the number of a forum topic: different topics.
- Removing an account's last topic removes the account's key from the document.
- Concurrent calls are serialised by the actor; memory never gets ahead of the file.

## Fixtures

None for the store (synthetic documents, temporary directories). The message-number order it relies on is measured on the corpus topic pages (`R20`, `R21`, `R22a`, `R22b`, `R23`, `R24`, `R26`-`R28` and the others with two messages or more), recorded in HFR-PROTOCOL §6c.

## Tests

- `ReadingPositionOrderTests`: message beats page, offset within a message, page without both numbers, known beats unknown, date ignored, validity bounds.
- `ReadingPositionStoreTests`: first record saved, never backwards, explicit reset, accounts apart and compared exactly, category part of the key, newest-first records, per-account eviction, a new record kept despite an old date, limit below 1, removal of a topic and of an account, invalid input unsaved.
- `ReadingPositionStoreFailureTests`: unreadable data answers nothing and refuses writes, discard and reload, newer format never overwritten, failed save leaves memory unchanged.
- `FileReadingPositionPersistenceTests`: missing file, round trip without temporary files, exact JSON of a record (ids and numbers only), corrupt file kept and set aside, earlier backup kept.

Shown to fail with the behaviour removed: an `advance` that always accepts, no eviction, a failed load treated as an empty store, and a page-first order each make the matching tests fail.

## Pending capture

- A topic page after messages were deleted: whether later messages move to an earlier page. The order rule does not depend on it.

## Intentional differences from legacy

- Positions survive the screen, the window and a relaunch (legacy kept them in `@State` only), per account.
- The forward-only rule covers every topic and compares messages, not only pages (legacy compared pages, for the MPStorage flag only).

## Learnings

- A position that must survive deletions is keyed by message number, not by page: the page of a message is the server's to decide (see LOT-095 on `numreponse`).
