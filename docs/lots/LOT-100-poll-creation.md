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
To write by the author: one line per SwiftHFR file (`// Port of HFRswift/Swift/TopicPollDraft.swift (TopicPollCreationSheet) @ 2fe43da3. Differences: …`, GAP-099).

## UX evolutions (app lots)
None planned: same UX as legacy at `2fe43da3`.

## Behaviour
To write, on top of LOT-089 and LOT-088. The poll block of the first-post edit form is captured (`R63b`, `docs/HFR-PROTOCOL.md` edit form); the new-topic form's poll section is not: capture [#170](https://github.com/ezzz/HFRnow/issues/170) (`status: blocked` until it lands, never hand-built, LESSONS 36). The answer to a post with a poll is not captured either: list it as *pending capture*.

## Edge cases
To write (sub-category required on a new topic, form without the poll block, closing date in the past at send, 10 answers).

## Fixtures
`R63b`; #170 pending.

## Intentional differences from legacy
To write.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
