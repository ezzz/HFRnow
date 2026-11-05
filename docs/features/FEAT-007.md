# FEAT-007 — First-unread landing and "Nouveau" banner

- **Issue:** [#151](https://github.com/ezzz/HFRnow/issues/151) · **Proposed by:** Bybifok ([`moust4ki`](https://github.com/moust4ki), credit kept, see [CREDITS.md](../../CREDITS.md))
- **Lots:** [LOT-090](../lots/LOT-090-reading-position-store.md) (position store, merged), [LOT-111](../lots/LOT-111-first-unread.md) (landing, stability, recording), LOT-178 (#418, the banner itself, M5)

## What and why
Opening a flagged topic lands on the first unread message and stays there while late images load; the reading position is kept per account. The visible "Nouveau" banner is a UX change legacy never had (UXD-11, 2026-11-02): it is split to LOT-178 (M5).

## Screens and states
- Reader opened from a flagged row: the page of the flag link, scrolled to the flag's message (`#t<numreponse>`).
- While images load the message stays at the top; the first touch, wheel or key press releases it.
- The flag message is followed by the legacy dashed separator (not after the last message).
- Network error after landing: the page on screen stays (LOT-083 rule), the position is untouched.

## HFR facts
Flag link and `numreponse` rules: HFR-PROTOCOL §6c LOT-095 and `R25` (HFR picks the page of a `numreponse` link, so `page=` is never read alone). No new fact.

## Edge cases
Flag message deleted: the first message after it (no separator); anchor past the end of the page: top of the page. A refresh reloads without the anchor, so the separator goes with it (as the scroll position is kept instead). Continuation block: never recorded. Logged out: nothing recorded.

## Engine lots needed
LOT-090 (done). App side: LOT-111.

## Legacy settings kept
None.
