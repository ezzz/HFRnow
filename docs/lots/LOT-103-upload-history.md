# LOT-103 — Upload history (local)

- **Module:** App · **Difficulty / model:** easy (Sonnet 5.5 in the cloud, reviewed by Opus)
- **Issue:** [#194](https://github.com/ezzz/HFRnow/issues/194) (host: mac, coded in the cloud, Mac check list in the PR) · **Feature spec:** [FEAT-019](../features/FEAT-019.md) (Bybifok's proposal)
- **Inputs:** [LOT-102](LOT-102-image-upload.md) (`ImageUploadModel`, the list and the reinsertion already shipped there) · [LOT-064](LOT-064-small-stores.md) (`RehostUploadHistoryStore`)

## Legacy counterpart (app lots)

| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `ImageUploadView` history section, removal dialog | `HFRswift/Swift/AnswerView.swift:1801-1982, 1984-2046`; silent removal at `:1909` |
| `ImageUploadModel.requestRemoval / confirmRemoval` | `AnswerView.swift:1909` (`uploadedImages.removeAll`), `ReplyService.swift:1895-1920` (`RehostUploadHistoryStore`) |

Implements FEAT-019 (#163), last lot of the feature.

## Scope
LOT-102 already lists, persists and reinserts. This lot adds only what FEAT-019 still needs: a **confirmed removal** that says the image stays online. See the feature spec.

## UX evolutions (GAP-091)
- **b·operator** — Removal asks first and states that the image stays public on the host. Legacy's "Supprimer" (silent) suggested the image was deleted, which misleads users about their data; ≈14 user messages asked for a disclaimer ([user-feedback-p450-510.md](../research/user-feedback-p450-510.md), "Cannot delete uploaded images") and issue #194 (acceptance criterion 1) requires it. GAP-091 updated (same → UX change, b·operator).

## Behaviour
- `requestRemoval(_:)` sets `pendingRemoval`; nothing changes until `confirmRemoval(_:)`. `cancelRemoval()` drops it.
- `confirmRemoval(_:)` takes the entry the dialog was shown for (SwiftUI clears its state before the button runs), removes the entry and writes the store like `remove(_:)` does, and sets `removalNotice` before that write is awaited. A refused save keeps the existing history warning and no "removed" notice (the entry is only hidden for the session). The notice is set before the write is awaited, so a later request or upload clears it for good.
- The swipe button has no destructive role (the row must not slide out before the confirmation) and no full swipe.
- Any new upload or removal request, and reopening the panel (`load()`), clears the previous notice.

## Pending capture
Server-side delete of a guest upload (B12): not captured, not offered.

## Fixtures
None.

## Left for later
Server-side delete, if a capture ever shows an API.
