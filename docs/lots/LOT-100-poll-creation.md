# LOT-100 — Poll creation (M4)

- **Module:** App (engine additions in `HFRClient` if the posting flow needs them)
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** [#191](https://github.com/ezzz/HFRnow/issues/191) · **Milestone:** M4, backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655))
- **Depends on:** LOT-089 (#181, new-topic composer), LOT-088 (#180, edit own messages, the first post too)

Stub written with the M4 move of #655. Absent at `2440d79` (only the `have_sondage` flag was read, `Classes/AddMessageViewController.m:521` @ `2440d79`), added by legacy at `2fe43da3` (`c7693a88`), so a port of legacy evolution, not an evolution. The author of the lot completes it before coding (AGENTS.md §5).

## Legacy sources
At `2fe43da3` (`git show 2fe43da3:<path>`, `HFRswift/Swift/`):

| Legacy @ `2fe43da3` | Behaviour |
|---|---|
| `MainWindow.swift:892`, `MessagesView.swift:5363` | the composer offers a poll when it creates a topic, and when it edits a topic's first post (`offersPollConfiguration`) |
| `AnswerView.swift:873-906` | "Ajouter un sondage" / "Modifier le sondage" and "Retirer"; the button is disabled until the forum form allows a poll, with "Chargement des options de sondage...", a load error with "Réessayer", or a reason: on a new topic whose sub-category is required, "Le forum ne propose pas de sondage à cette étape. Créez le sujet, puis éditez son premier message."; once set, the question and "Le sondage sera créé lors de l'envoi du message." |
| `AnswerView.swift:1388-1412` | the form's capability is read when the composer opens (`fetchComposerContext`: `canCreatePoll`) |
| `AnswerView.swift:1480-1486` | at send, an invalid poll stops the post ("Sondage invalide"); a valid one adds its fields to the form |
| `TopicPollDraft.swift:4-53` | the draft: question, 2 to 10 answers, maximum choices, visitors allowed, optional closing date; validation messages (question and each answer at most 255 UTF-16 units, at least two answers, choices within the answers, closing date in the future); form fields `have_sondage=1`, `textreponse0` (question), `textreponse1…` (non-empty answers), `max_votes`, `allowvisitor=1`, `jour` `mois` `annee` `heure` `minute` |
| `TopicPollDraft.swift:56-144` | the sheet "Créer un sondage": sections Question, Réponses ("Ajouter une réponse", delete), Options ("Autoriser les visiteurs à voter", "Date de clôture") |
| `ReplyService.swift:154-156, 279-281, 332-340` | the form allows a poll when it has `have_sondage` and `textreponse0` and the box is unchecked; a poll sent to a form that no longer allows one fails with "Ce formulaire ne permet plus de créer un sondage sur ce sujet." (`:42-43`); inactive `have_sondage`, `allowvisitor`, `sticky` flags are not sent |

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ `87fe0d1c` | Differences |
|---|---|---|
| `HFRClient/Posting/PollDraft.swift` (`PollDraft`, `PollProblem`, `ForumForm.offersPollCreation`) | `TopicPollDraft.swift:4-53` (`TopicPollDraft`), `ReplyService.swift:279-281` (`canCreatePoll`) | a line break or a character outside the BMP in the question or an answer is refused (one-line inputs; Q-3) |
| `HFRClient/Posting/PostingFlow.swift` (`edit(_:subject:subcategory:poll:…)`) | `ReplyService.swift:154-156` (`pollCreationUnavailable`), `AnswerView.swift:1480-1486` | the poll is checked against the fetched form: each field must be one it serves (`max_votes` among its options, text inputs within `maxlength`) |
| `App/SwiftHFR/Composer/ComposerPoll.swift`, `ReplyComposerModel+Poll.swift` | `AnswerView.swift:324-328`, `:434`, `MainWindow.swift:892`, `MessagesView.swift:5434` (`offersPollConfiguration`) | not offered on a private thread's first post, whose form never holds the poll block (`R43a`) |
| `App/SwiftHFR/Composer/ComposerPollRow.swift` | `AnswerView.swift:873-906`, `:523-528` | a failed read is retried from the sub-category row (same failure, same "Réessayer") |
| `App/SwiftHFR/Composer/PollCreationSheet.swift` | `TopicPollDraft.swift:56-144` (`TopicPollCreationSheet`) | answers keep their identity when one is deleted (legacy bound `options[index]`) |

## UX evolutions (app lots)
None: same UX as legacy at `87fe0d1c`.

## Behaviour
- **Where**: the poll row ("Ajouter un sondage" / "Modifier le sondage", "Retirer") shows in the composer of a new topic and of the edit of a public topic's first post (its title is editable). The button is on only when the form allows a poll (`ForumForm.offersPollCreation`: an unchecked `have_sondage` box and a `textreponse0` input, legacy's test). Otherwise legacy's reason is shown: "Le forum ne propose pas de sondage à cette étape. Créez le sujet, puis éditez son premier message." on a new topic, "Le formulaire du forum ne propose pas la création d'un sondage pour ce message." elsewhere; "Chargement des options de sondage…" while a new topic's form is read.
- **New topic**: neither new-topic form has a `have_sondage` input (`R45a`, `R170a`, HFR-PROTOCOL §6b "New poll"), so, as in legacy, the button stays off and no poll is sent with a new topic. Sending one through `nouveau_sondage.htm` (`sond=1`) waits for its answer to be captured (#1100).
- **First-post edit** (`R63b` → `W41`): the edit form is fetched again at send (fresh token, `LiveReplyPoster`), the flow refuses a poll unless that form allows one (`pollNotOffered`), then sends the form in document order with `have_sondage=1`, `textreponse0` = the trimmed question, the non-blank answers packed from `textreponse1`, the empty slots as served, `max_votes`, `allowvisitor=1` when visitors may vote (else left out, browser semantics), and the closing date in `jour` `mois` `annee` `heure` `minute` (zero-padded, device calendar and time zone, legacy `TopicPollDraft.swift:42-48`), left empty without one (`W41`). Success is the edit's own sentence (`W41`); like every write it is sent once, never retried.
- **Validation** (legacy order and sentences, `TopicPollDraft.swift:16-30`): question required, ≤ 255 UTF-16 units; at least two non-blank answers; at most ten slots; each answer ≤ 255; 1 ≤ choices ≤ filled answers; closing date in the future. Plus: no line break, no character outside the BMP (refused before sending). The sheet's "Ajouter" and the composer's Send are off while the poll has a problem, which is shown; the engine checks again (`invalidPoll`).
- **With a poll set**, an untouched first-post edit can be sent (the poll is the change). A poll refused at send because the form no longer offers one keeps the poll on screen, with the reason; Send stays off until it is removed.
- The poll is not kept in the draft (legacy kept it in the view only).

## Edge cases
- Sub-category required on a new topic: the poll is off there anyway (no `have_sondage`, `R45a`).
- A form without the poll block (later post `R62a`, private first post `R43a`, reply composers): `offersPollCreation` is false; a poll given to the flow is refused locally, nothing sent (`PollCreationTests.laterPostRefused`).
- A topic that already has a poll: no capture shows its first-post form; a `have_sondage` box served checked is read as "no new poll" (`existingPollRefused`).
- A closing date that passed between the sheet and Send: refused at Send (`closingDateNotInFuture`), nothing sent.
- Ten answers: all ten slots are filled in order (`fullPoll`); an eleventh slot cannot be added.

## Fixtures
`R63b` (edit form), `W41` (its answer, and the request body the poll test reproduces), `R170a` (new-poll form), `R45a` (new-topic form without a poll block), `R62a`, `R43a`, `R40a`, `R61b` (forms without one).

## Pending capture (#1100)
- The answer to a new topic posted from `nouveau_sondage.htm` with its poll, and HFR's refusal of an incomplete poll.
- A poll with a closing date (sent today on legacy's format alone), and one in the past.

## Intentional differences from legacy
- Question and answers with a line break or a non-BMP character are refused before sending (legacy sent them; HFR cuts the text at the first non-BMP character, Q-3).
- Every poll field is checked against the form fetched at send (a field it does not serve fails as an unsupported form, nothing sent).
- No poll row on a private thread's first post (its form never offers one).
- An unchecked `allowvisitor` is left out of the body (browser semantics) where legacy sent `allowvisitor=0`; `W41` itself sent `0`, and HFR reads both (HFR-PROTOCOL §6b "Checkbox values").

## Learnings
To copy into AGENTS.md §11 when the lot closes.
