# FEAT-019 — Upload history (local)

- **Issue:** [#163](https://github.com/ezzz/HFRnow/issues/163) · **Proposed by:** Bybifok (credit kept, see [CREDITS.md](../../CREDITS.md))
- **Lots:** [LOT-102](../lots/LOT-102-image-upload.md) (the list and the reinsertion) · [LOT-103](../lots/LOT-103-upload-history.md) (removal; last lot of this feature)

## What and why
A poster reinserts an image uploaded before instead of uploading it twice, and can forget an entry. Readers asked for it (≈14 messages: [user feedback p. 450-510](../research/user-feedback-p450-510.md), "Cannot delete uploaded images").
The proposal also asked for a **server-side delete**: not evidenced (HFR-PROTOCOL §7b B12: the host's `delete_url` answered 404 once without a browser session, not captured), so it is **out of scope**. The app never says or implies the image is deleted.

## Screens and states
- Section "Images envoyées" of the image panel (LOT-102): newest first, thumbnail, size, address, one button per rendition, reinsertion at the caret in the chosen BBCode mode.
- Empty: "Aucune image envoyée."
- Removal: swipe "Retirer" asks "Retirer de l'historique ?" with the text "Seule l'entrée de cet historique est effacée. L'image reste en ligne et publique chez l'hébergeur, son adresse reste valable." (**Retirer de l'historique** / **Annuler**). After the removal a line says "Entrée retirée de l'historique. L'image reste en ligne chez l'hébergeur."
- Unreadable or unwritable history: the panel warns (LOT-102); nothing is overwritten.
- Light/dark and Dynamic Type XL: system text and list rows.

## Store
One store over the file: the engine's `RehostUploadHistoryStore` (LOT-064), one instance per process (`ImageUploadServices.liveHistory`). LOT-103 adds no second store and no schema change.

## HFR facts
None new. Legacy removed an entry silently (`AnswerView.swift:1909` @ 2440d79) and never called the host.

## Edge cases
- Removal confirmed while the save fails: the entry leaves the list for the session, the panel shows the save warning and no "removed" notice; the entry may come back after a relaunch.
- Removing the entry of an image still referenced in the composer text changes nothing in the text.
- No de-duplication by content: one entry per answered address (an entry with the same `id` replaces the older one).
