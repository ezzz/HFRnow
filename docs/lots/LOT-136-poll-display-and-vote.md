# LOT-136 — Poll display and vote

- **Module:** App (`App/SwiftHFR/Polls/`, hooks in `Reader/` and `Composer/ReplyPosting.swift`)
- **Difficulty / model:** medium · Sonnet (author, cloud child of cloud/orch) → Opus (reviewer, as the orchestrator's brief). LOTS.md routes the lot Opus → Fable; the routing deviation is the orchestrator's. A state-changing flow: merged by the orchestrator or the maintainer (AGENTS §8)
- **Issue:** [#226](https://github.com/ezzz/HFRnow/issues/226)
- **Depends on:** LOT-026 (`PollParser`), LOT-054 (`PollVoteFlow`), LOT-083 (reader)

## Legacy sources
`HFRswift/Swift/PollView.swift` (`PollViewModel`, `PollToolbarButton`, `PollSheet`, `PollContentView`, `PollResultRow`, lines 1-305) and `HFRswift/Swift/MessagesView.swift:4675-4680` (toolbar button) @ 2440d79. Vote write path: `PollVoteSubmitter` (`PollData.swift:45-99`), replaced by LOT-054, not touched here.

## Legacy counterpart
| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `Polls/PollModel.swift` | `PollView.swift` (`PollViewModel`: selection, `submitVote`) |
| `Polls/PollSheet.swift` (`ReaderPollFlow`, `PollSheet`) | `PollView.swift` (`PollToolbarButton`, `PollSheet`, `PollContentView`, `PollResultRow`); `MessagesView.swift:4675-4680` |
| `Polls/PollVoting.swift` | none (legacy called `PollVoteSubmitter` directly) |

## UX evolutions
GAP-059 (port, ezzz Swift layer).
- The "Sondage" button shows for a results poll too; legacy showed it only for a poll not yet voted (`MessagesView.swift:4675`). `b` (optional, small).
- HFR's closed / multi-pseudo notice and total line are shown (LOT-026 `Poll.notice`, `Poll.footer`). `b·needed`: it explains why a poll cannot be voted.
- After a vote the topic page is reloaded and the sheet shows the results from it; legacy closed the sheet and called `onVoteSucceeded`.
- A vote that may have been counted (`unconfirmed`) or that HFR says is already given reloads the topic and **cannot be sent again** from that sheet.

## Behaviour
- `ReaderPage.poll` is `PollParser.poll(in:)` of the page when `TopicPageMetadata.hasPoll`; a poll shape the parser refuses gives `nil` (LOT-026 "Callers": it never fails the page).
- `ReaderPollFlow` adds the "Sondage" toolbar button when the page has a poll, and the sheet.
- `PollModel` holds the choice and the phase (`idle`, `sending`, `voted`, `settled`, `failed`). Single choice only; choosing the chosen answer again clears it (legacy `toggle`).
- Vote = `PollVoting.vote` = engine `PollVoteFlow.vote(_:in:session:)` in the current account's session (`LivePollVoter`, from `ComposerServices.pollVoter`; nil logged out: answers shown, no button, "Connectez-vous pour voter.").
- Outcomes: `PollVoteResult` → "voted" with HFR's sentence, topic reloaded. `unconfirmed`, `alreadyVoted` → "settled", topic reloaded, no new vote. Everything else (`network`, `sessionNotConfirmed`, `loginChanged`, `missingToken`, `rejected`, `notLoggedIn`, `unsupportedPoll`, `invalidChoice`) → "failed", sheet stays, another try allowed; HFR's own sentence is shown for `rejected`.
- The reload is the reader's `refresh()` of the page on screen, not HFR's refresh URL (`PollVoteResult.refreshURL`, page 1 in `W42`; whether it echoes another form page is pending capture, LOT-054 spec).
- The held model follows every loaded page's poll (`TopicReaderModel` → `PollModel.pageDidReload`): after the reload it shows the results. The sheet cannot be closed while sending; a reopened sheet reuses the held model while it holds a vote (`sending`, `voted`, `settled`), so a possibly-counted vote is never offered from a fresh form.
- Cost: when the page has a poll, `PollParser` parses the page a second time (whether HFR prints the poll beyond page 1 is not asserted, so no page-1 shortcut); polls are rare, measured: not.

## Edge cases
Poll absent on later pages (the poll is read from each page; whether HFR prints it beyond page 1 is not asserted); poll on a page that fails to parse it; logged out; closed poll; poll voted with a linked pseudo (`R33b` notice); double tap on "Voter" (`sending` blocks it); a vote in flight (the sheet cannot be closed), a sheet reopened or a topic reselected after a vote that may have been counted (the model is held by `TopicReaderModel.pollModel`, keyed on the account: it is reused while it holds a vote, so no fresh form is offered; re-voting after an unconfirmed vote needs leaving the topic reader), another account (fresh model).

## Pending capture
- Multi-choice polls (#111): not offered; the sheet says to vote on the site. The engine refuses them (`unsupportedPoll`).
- Guest votes (LOT-054): not offered.
- The page HFR refreshes to after a vote from a form at `page` ≠ 1.

## Fixtures
Reused: `R32b` (voting form, logged in), `R33a` (closed), `R20` (no poll), read in `LiveTopicPageSourceTests`. Vote answers are engine fixtures (`W42`, `W43`, `W44`).

## Tests
`App/SwiftHFRTests/Polls/PollModelTests.swift` (every `PollVoteError` case (and the session-health variants), reload counts; reopen keeps a vote in flight or possibly counted (`holdsVote`, `TopicReaderModel.pollModel`), one send, reload counts, no account, results/multi-choice), `LiveTopicPageSourceTests` (poll reaches `ReaderPage`; none on `R20`).

## Intentional differences from legacy
Success only on HFR's confirmation and a body that is the captured one (LOT-054); no multi-choice checkboxes (legacy offered up to `maxChoices`, never captured).

## Learnings
- A write flow's `unconfirmed` must end in a reload of the page, not in a "retry" button.
