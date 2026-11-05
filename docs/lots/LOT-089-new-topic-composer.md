# LOT-089 — New topic composer

- **Module:** App (`App/SwiftHFR/Composer/`, entry point in `App/SwiftHFR/Navigation/TopicListView.swift`)
- **Difficulty / model:** medium (Opus 5.5 → Fable)
- **Issue:** [#181](https://github.com/ezzz/HFRnow/issues/181) (post-MVP, legacy parity)
- **Depends on:** LOT-048 (`PostingFlow.newTopic`, `PostingForm`), LOT-084 / LOT-128 (`ReplyComposerModel`, drafts, messages), LOT-082
  (topic list), LOT-063 (`DraftContext.newTopic`)

As a logged-in member browsing a forum, I start a topic from its list: subject, sub-category, text. Poll creation (LOT-100)
and the BBCode toolbar (LOT-085) are other lots.

## Legacy sources

Legacy app: `master` of ezzz/HFRnow (read-only), citations `2440d79`.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MainWindow.swift:745-757` ("+" toolbar button, disabled when logged out or `newTopicURL == nil`), `:52,76,90-95` (`newTopicURL` of the loaded list), `Common.swift:1531,1562` (`forumNewTopicUrl`, from `md_btn_new_topic`: `Classes/ObjCTopicListParser.m:134-135`) | `TopicListContent.newTopicPath` + `categoryID`, `TopicListModel.newTopicTarget`, "Nouveau sujet" toolbar button (shown to a current account only) |
| `MainWindow.swift:812-835` (`AnswerView(requiresSubject:requiresSubcategory:subjectCharacterLimit: 70)` in a sheet; success clears the text and reloads the list) | `ReplyComposerView` / `ReplyComposerModel` with `ComposerTarget.newTopic`; `TopicListModel.newTopicDidClose` |
| `HFRswift/Swift/ReplyService.swift:96-113,392-412` (`ReplyComposerSubcategoryOption`, options parsed from `<select name="subcat">`), `AnswerView.swift:395-420` (picker, "Chargement…" while loading), `:625-640` (options and preselection read from the form at open: `selectedSubcategoryID ?? first`), `:685-695` (`overrides["subcat"]`) | `NewTopicSubcategories`, `ReplyPosting.newTopicOptions`, `ReplyComposerModel.loadSubcategories` |
| `MainWindow.swift:277,826-831` (one global `newTopicDraftText`, cleared on success) | `DraftContext.newTopic(forum:)`: subject and text kept per forum and account (LOT-063) |

## Legacy counterpart (app lots)

`HFRswift/Swift/MainWindow.swift` ("+" button, new-topic sheet) and `AnswerView.swift` (composer, sub-category `Picker`) @ 2440d79; GAP-098
(`a`, ported with changes).

## UX evolutions (H.1)

- GAP-098 new topic: `a`, persistent draft per forum (was lost on relaunch). No UXD row applies; no other UX change.

## Behaviour

**Entry.** `TopicListPage.newTopicPath` is the list's `#md_btn_new_topic` link (LOT-022), a **category** path
on a category list (`/hfr/Discussions/nouveau_sujet.htm`, `R05a`; HFR-PROTOCOL §6c: the sub-category path answers 404); a sub-category
list (`R06`) links `/message.php?config=hfr.inc&cat=13&sond=0&p=1&subcat=433&dest=&subcatgroup=0` instead, which the app also follows
as given (its form is pending capture). The link is also present on a logged-out
page (`R50b`). `NewTopicTarget(path:forum:)` resolves it to an `https` URL of the forum host (default port, no user info) and keys the
draft with the page's `categoryID`; it is nil without a link, without category, or for the private messages pseudo-category (its
button is the new-MP composer, LOT-128). `TopicListView` shows "Nouveau sujet" (toolbar, primary action) only when the target exists
**and** an account is current (`ComposerServices`, nil logged out). Flags and favourites have no such link.

**Sub-categories.** When the sheet opens, in parallel with the draft restore, `ReplyPosting.newTopicOptions` fetches the composer
through the current session and reads its `subcat` select (`form.subcategories`) and preselection (`FormSelect.effectiveValue`: the
option marked `selected`, else the first; `R45a` marks none, so "Aucune", `value=""`). The picker is a menu. A failed read shows a
warning with "Réessayer"; the topic stays sendable (the engine then sends the form's own choice, LOT-048 §6). Send waits for the read (a failed read ends the wait), so HFR's default never overrides the
user's choice; a second read keeps a choice the form still offers. Only an offered value can be chosen. If HFR
refuses the choice at send (`unknownSubcategory`: the list changed), the picker is read again and the user chooses again.

**Sending** (`ReplyComposerModel.send`, same path as the MP composer). Send needs a non-blank subject and text. Refused locally,
nothing requested: a scalar above U+FFFF in the subject or the text (Q-3). The subject is trimmed; its 70-code-unit limit and line
break rule are the engine's (`tooLong`, `lineBreak`, `R45a`). The composer is fetched **again** at send time (fresh `hash_check`,
LOT-084 rule) and posted with `PostingFlow.newTopic(subject:subcategory:text:with:)`; the write path is unchanged.

- `PostingResult` (HFR's sentence, LOT-048 §8): draft discarded, sheet closes `.sent`; `TopicListModel` shows HFR's sentence in a
  banner for 4 s and reloads **page 1** (legacy reloaded the list).
- Any `PostingError`: text, subject and draft kept, `ComposerMessages` says what happened (texts specific to "sujet": refusal,
  unavailable form, unsupported form, session, unconfirmed → "Vérifiez la liste des sujets avant de renvoyer"). Only `unconfirmed`
  says it may have been posted; "Voir les sujets" closes with the draft kept and reloads page 1. Nothing is resent automatically.

**Opening the new topic.** Not possible: HFR's public new-topic answer (`W40`, HFR-PROTOCOL §7 E14) says "Votre message a été posté
avec succès !" and refreshes to the **category** list `/hfr/<cat>/liste_sujet-1.htm` (even when a sub-category was chosen), with no
topic id. #181's "on success open the new topic" is therefore met as far as HFR allows: the app reloads page 1 of the list on screen
and shows HFR's sentence. The new row appears there (observed on `W40`'s category list); on a sub-category list only if it was posted
in that sub-category.

**Drafts.** Context `.newTopic(forum:)`, same autosave, close choices, warnings and "Fermer sans enregistrer" as the reply composer
(LOT-084). Subject and text are kept; the sub-category is not (a draft has no such field). A subject alone is a draft.

## Edge cases

- Logged out: no button. A session that expired meanwhile: `notLoggedIn` message at the options read (warning) or at send.
- Forum that does not offer a topic (closed, no right; pending capture): HFR's own sentence at the options read or at send
  (`formUnavailable`).
- The composer served is not a new-topic form (`formMismatch`): the options read fails with the warning; send says the form is not
  supported.
- Account switch while the sheet is open: the sheet goes away and the draft is saved for the previous account (LOT-084).
- A list page other than 1 on screen: after a send page 1 is loaded, not the page on screen.

## Fixtures

No new capture. `R05a` and `R50b` hold the `#md_btn_new_topic` link (category path, also logged out); `R45a` (new-topic composer, 16
`subcat` options, none selected) and `W40`'s answer are LOT-048's, tested there (`PostingCaptureTests`, `PostingInputTests`).
App tests use scripted `ReplyPosting` doubles with the sentences of HFR-PROTOCOL §7 E15.

## Tests

`App/SwiftHFRTests/Composer/NewTopicComposerTests` and `TopicListNewTopicTests` (in `TopicListModelTests.swift`): target from the
link (off-forum, missing, no category, private messages); options read and preselection honoured; only an offered value chosen and
sent; a failed read warns, still sends, retry reads the options (the form's preselection); confirmed topic sent once with trimmed subject, draft cleared;
subject and text required, no recipient; non-BMP in the subject refused before any request; unconfirmed: "liste des sujets", never
resent; messages name the topic; draft per forum and restore; a subject alone is a draft; the list offers the target only with link
and category, never on favourites; confirmed → page 1 reloaded and HFR's sentence; unconfirmed → reload without sentence; closing
without sending changes nothing. Not run in the cloud (the app builds on CI and on the Mac); mutation runs are the Mac's, see the
PR's "Mac check needed".

## Pending capture

- New-topic form served at a sub-category list's `message.php` link (`R06`): its shape and preselected `subcat` (the sheet reads
  both from the form, so only the capture is missing).
- Forum where the account may not create a topic (#131): the button follows the page's link; HFR's sentence is shown if it serves no
  form.

## Intentional differences from legacy

- Draft per forum (legacy: one global text, shared with nothing else but cleared on success).
- No "Chargement…" screen: the editor is usable while the options load (only Send waits for them); a failure does not block sending.
- Errors say whether anything was posted (GAP-100); never resent after an uncertain send.
- The 70-character limit is enforced by the engine at send (`tooLong`), not by truncating while typing.
