# LOT-127 — MP actions: mark unread

- **Module:** App
- **Difficulty / model:** easy (Opus → Fable)
- **Issue:** [#218](https://github.com/ezzz/HFRnow/issues/218). Its title still lists delete and group members: both moved to [LOT-181](LOT-181-mp-delete-members.md) (#421, M5, split 127b of `docs/LOTS.md`), so the issue's delete criterion and CAP-N1 are that lot's. Since the operator decision of 2026-11-09 on [#676](https://github.com/ezzz/HFRnow/issues/676), the MP list row menu ("Marquer non lu" on read rows, "Supprimer" with a confirmation) is legacy parity at `2fe43da3` and is done under #676 (M4); LOT-181 keeps group members only (M5).
- **Depends on:** LOT-058 (#84, `TopicFlagFlow.markUnread`, `TopicPageMetadata.markUnreadURL`), LOT-094, LOT-126 (#217, the list and the reader column), LOT-125 (`TopicFlagActions`), LOT-185 (surfaces, kept as they are).

## Legacy sources
`ezzz/HFRnow` @ `2440d79`:

| Legacy | Used for |
|---|---|
| `Classes/OnlineMessagesTableViewController.m:805-807` | the entry "Marquer comme non lu" of the conversation's action sheet, only when the page has the link (`isUnreadable`) |
| `Classes/OnlineMessagesTableViewController.m:888-913` (`markUnread`), same in `HFRswift/Wrapped/MessagesTableViewController.m:1250-1272` | one GET of the link; on an answer, back to the list and a refetch; on an error, nothing is shown and the conversation stays |
| `HFRswift/Swift/MessagesView.swift:4694-4722, 4942-4970` | the Swift layer's reader menu has no such entry (a difference of that layer, not ported) |

At `2440d79` the MP list has no such action (GAP-116). The reason given here, that the list cannot have it because its rows carry no `nonlu.php` link (`R13u1`; the link is on the thread page, `RA1`-`RA4`) and fetching a thread page to get it could mark the thread read, **is no longer true at `2fe43da3`**: legacy builds the URL itself from the row's topic id (`HFRswift/Swift/MPListView.swift:85-111` @ `2fe43da3`, `user/nonlu.php` with `config=hfr.inc&cat=prive&subcat=0&post=<id>&page=<page>&p=1&sondage=0&owntopic=0&new=0`, `page` from the row's links, `:211-217`), the same parameters as the captured header link with `page=1` (`RA1`-`RA4`, HFR-PROTOCOL §6c). Its row context menu (`4a4f493f`) offers "Marquer non lu" on read rows only and "Supprimer" with a confirmation (`:800-826`, alert `:711-722`). That list part is [#676](https://github.com/ezzz/HFRnow/issues/676) (M4, operator decision 2026-11-09), not this lot: this lot shipped the reader entry and adds no list action.

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `Messages/ReaderMarkUnreadFlow.swift` (`markUnread`, entry and alert) | `OnlineMessagesTableViewController.m` (`markUnread`, entry `:805-807`) |
| `Messages/MessageListModel.swift` (`markUnreadEnded`) | `OnlineMessagesTableViewController.m:900-903` (pop, `fetchContent`) |
| `Navigation/TopicFlagActions.swift` (`markUnread`) | `OnlineMessagesTableViewController.m:889-899` (the request), through LOT-058 |

## UX evolutions (app lots)
None: same UX as legacy (GAP-116, class `a`). The entry is in the reader's secondary menu, next to the offline save, the reader's counterpart of legacy's action sheet. Failures now say why and HFR's sentence is shown (see "Intentional differences").

## Behaviour
- **Entry:** "Marquer comme non lu" in the reader's secondary menu, when the page has `ReaderPage.markUnreadURL` (LOT-058: the page's own header link, never a link a member posted) and an account is current (`ReaderServices.flagActions`; nil logged out and in the offline reader).
- **Write:** `TopicReaderModel.markUnread` sends the link once through `TopicFlagActions.markUnread` (LOT-058: the session is checked first, then one GET, redirects not followed, never retried). While it runs the entry is disabled and a second call sends nothing.
- **Confirmed** (HFR's own sentence, `W18`), in the Messages list (`MessageListModel.markUnreadEnded`): the sentence is shown in the list's banner (the LOT-128 one), the conversation closes (compact width: back to the list, regular width: "Choisissez une conversation") and the page on screen reloads. Keeping the reader would show a thread HFR now holds unread, and its next load could read it again (LOT-126 pending capture). `R13b` shows the row unread after `W18`.
- **Row state:** a confirmed row shows unread at once, also when it was read locally (`markOpened`) and when the reload fails: HFR's confirmation stays true, so the banner and the mark stay. The next load applied brings HFR's state back. The reload that follows the confirmation supersedes any older load, so that next load started after the write (LESSONS 57). Seeing the conversation's last page again drops the mark, as for any row.
- **Failed or unconfirmed** (`rejected`, `W137a`'s notice included; `unconfirmed`; `sessionNotConfirmed`; `notLoggedIn`; `network`; `invalidLink`): an "Action impossible" alert in the reader with `TopicFlagActions.reason(for:)`. The row, the banner and the conversation do not change, nothing is resent. An unconfirmed write says to check first.
- **Reader left before the answer:** a confirmation works the same; a failure is shown by the list (`actionFailure`), since the reader that holds it is gone. The same conversation opened again meanwhile has a new reader, so the list says it there too.
- **A reader no list hosts** (a conversation reached by a followed link, `onMarkUnread` nil): the same entry; HFR's sentence is shown in the reader (`menuFeedback`) and the reader stays. The list reads HFR's state at its next load.

## Edge cases
- Another conversation opened while the write ran (iPad): it stays open, only the marked row changes.
- A multi-page conversation: the link is the page's as served; what its `page` means is pending capture (LOT-058).
- Tab badge: it is the home page count (LOT-170), read at the next home load; this lot does not touch it.

## Fixtures
None new. `MarkUnreadTests` reads `RA1` (the link equals the URL `W18` requested), `R21` (no link), `R13b` (the row unread after the write); the write's answers are scripted, LOT-058's tests run them on `W18`, `W17b`, `W17c`, `W137a`. No write reaches HFR: the only real session in the tests never logged in and stops at the check, which needs no request.

## Pending capture
LOT-058's: `nonlu.php` sent twice while logged in (#137), a multi-page conversation's link. LOT-126's: what a thread page fetch does to the unread state.

## Mac check needed
iPhone and iPad, light, dark, Dynamic Type XL: on a test account, open an MP, secondary menu, "Marquer comme non lu": back to the list (compact width), banner, row unread. In airplane mode: the alert, the conversation stays. A topic page has no entry; logged out and in the offline reader neither.

## Intentional differences from legacy
1. A failure is shown; legacy dropped it and stayed on the conversation without a word.
2. HFR's sentence is shown over the list; legacy returned without a word. LOT-058's differences (answer read, header link only, session checked first) stay.
3. The list's reload is the page on screen (paged list, LOT-126); legacy has page 1 only.
4. CHANGELOG-LEGACY row 91.

## Learnings
- A list action whose link only exists on the detail page cannot be a row action when fetching that page has a side effect: read where the link lives before planning swipes. (Superseded at `2fe43da3`: legacy builds that link from the row's topic id, #676. Check whether the client can build a link before ruling a row action out.)
