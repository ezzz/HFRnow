# LOT-171 — MP and group MP lists (setting, switch)

- **Module:** App (plus one `HFRModels` enum and one `HFRStorage` key)
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#297](https://github.com/ezzz/HFRnow/issues/297)

## Legacy counterpart
Legacy `2440d79` of <https://github.com/ezzz/HFRnow>; the issue cites `origin/master` lines.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MPListView.swift:359-377` (`hasMultipleInterlocutors`: `aAuthorOrInter` contains "multiples") | `PrivateMessageThread.isGroup` (LOT-023 D4), `MPSegment.contains` |
| `MPListView.swift:773-780` (group row: "Interlocuteurs multiples", group avatar) | `MessageRowView` (LOT-126, unchanged) |
| `Classes/HFRMPViewController.m:134-135, 234` (same "multiples" test) | `isGroup` |
| none | the setting, the switch and the per-segment counts: **new** (operator decision 2026-10-28, UXD-free) |

## Behaviour
| Piece | Rule |
|---|---|
| Setting | `MPListDisplay` (HFRModels) stored under the **new** key `mp_list_display` (`SettingKey.mpListDisplay`): `single` "Tout en un" (default) / `split` "Deux listes". Absent or unknown reads `single`, so nothing changes for anyone who does not opt in. Réglages, section "Messages", picker "Affichage des MP" |
| Reading it | `MessageListModel.onAppear` reads the store (`settings:`, given by `RootModel`) before it loads, so a change made in Réglages applies when the list is shown again |
| Default | `visibleThreads` is every row of the page: LOT-126's list, no extra request (test `defaultShowsEveryRowOfTheListUnchanged`) |
| Two lists | A segmented control above the list: "MP" (`!isGroup`) and "MP multiples" (`isGroup`). The split is client-side over the page on screen: no server filter of the MP list is known, so none is guessed |
| Counts | Each segment shows its own unread count (`unreadCount(in:)`: HFR's state, minus what was read here, LOT-126 `isUnread`). **Page-bounded**, like `MessageListContent.unreadCount`: the mailbox total is the tab badge (LOT-170, home page count) and stays the total |
| Empty segment | A page without a row of the segment, with a next page: the next pages are loaded by the model (`advanceWhileSegmentEmpty`), at most `maxAutoAdvance` (5) pages per trigger (appear, refresh, next, switch), stopping at the last page, on a failure (rows kept, banner) or when another load supersedes it. Progress is shown meanwhile, never "empty". When the bound is hit the segment may still be empty with a next page: the pager stays and "Aucun MP multiple" / "Aucun MP individuel" is shown. Going to the previous page never searches forward |
| Group rows | LOT-126's row plus, for a group only, a line "N réponses · M pages" from `TopicSummary.repliesCount` / `pageCount` (shown when replies > 0; one-to-one rows are unchanged). Whether the MP list's reply count is the thread's real count is not verified against a capture: **Mac check** |
| Participants | Names come only from the list row (`<span title>` of "Interlocuteurs multiples", HFR-PROTOCOL §6c, #336): the thread pages carry no roster. Not shown in the row yet (legacy shows none) |

## Group thread reading and participation: which topic features apply
A group thread opens in the same reader as a one-to-one MP (`MessageListModel.reader(for:)`, last page, `#bas`, LOT-126), so every feature the reader gains applies to it unless listed as not applying.

| Topic feature | MP group | Source |
|---|---|---|
| Page navigator (LOT-110 #201), message actions (LOT-087 #179), quote and multi-quote (LOT-086 #178), quick reply (LOT-153 #243) | apply, as those lots land; nothing in this lot blocks them | reader shared with topics |
| Reply composer | **LOT-128 (#219)**, not here: `MessageReaderColumn` still gets `composer: nil` (the refresh after posting on a `cat=prive` thread is not captured, LOT-126 spec). A group member's reply form has no `newdest` field, the owner's has (#336, `R123a`-`R123f`) | HFR-PROTOCOL §6c "M2 write captures" |
| First-unread landing (LOT-111 #202) | **does not apply as such**: MP rows have no flag link (`sujetCase5` is `&nbsp;`, `R13u1`), so there is no resume position; the reader opens on the latest message | LOT-126 spec |
| Flags / favourites (`addflag`, `delflag`, `W18` mark unread) | **do not exist for MPs** | `R13u1`; legacy `MPListView.swift` has no flag action |

## Edge cases
- A mailbox of only group threads: "MP" is empty after the bounded search; "MP multiples" shows them.
- Logged out or empty mailbox: no row, so the switch is hidden (`showsSegmentSwitch`); "Connexion requise" / "Aucun message privé" shown.
- Switching segment during a search: the search is cancelled and restarted for the new segment from the page on screen (`searchCount`); a refresh supersedes it through `loadCount`.
- A switch during a search also cancels a pull to refresh that started in the same window (the loader holds one load); the rows stay, the member pulls again.
- A conversation the new segment hides is closed (`selected = nil`), so the reader never shows a row the list does not offer.
- Known limit: once the bound of 5 pages is hit, each appearance of the list reloads the page on screen and may search 5 pages further, so the page can move forward without a tap. Accepted for now; **Mac check** whether it surprises on a real mailbox.

## Fixtures
Existing captures only (`R13u1`: group and one-to-one rows, 7 pages; `R04`, `R08-2`). Tests over the fake source cover paging; the parser's `isGroup` is LOT-023's oracle-tested fact.
**Pending capture** (none hand-built): a paged MP list mixing group and one-to-one threads over several pages in the order a real mailbox has them (to measure how often the bound of 5 is hit); a group thread page with three or more participants.

## Intentional differences from legacy
| # | Legacy | Port | Why |
|---|---|---|---|
| D1 | one list | optional split, default "Tout en un" | operator decision 2026-10-28 |
| D2 | group detected by the text "multiples" | `isGroup` (LOT-023 D4) | LOT-023 |

## Learnings
- A client-side split of a paged list needs a bounded forward search, or a segment looks empty while later pages hold its rows; make the bound and the stop conditions (last page, failure, superseded) explicit and test each.
