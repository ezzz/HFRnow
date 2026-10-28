# LOT-036 — `hop` form parser

- **Module:** HFRParsing
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`; old [#69](https://github.com/francoisgn/ios-app_SwiftHFR/issues/69) is frozen history; audit D1 in [D](../audit/D-posting.md))

Reads the write forms HFR serves (reply, quote, edit, new topic, MP, moderator alert) into the `ForumForm` of [LOT-012](LOT-012-form-write-models.md).
It reports what the page contains and decides nothing: which fields are sent, how an unchecked box is encoded and the reply text are `HFRClient` (LOT-048). The answer to a write is LOT-037.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79` (`origin/master` of ezzz/HFRnow). Oracle: [LOT-004](LOT-004-forms-storage-oracle.md), kind `form`.

| Legacy | Replaced by |
|---|---|
| `Classes/QuoteMessageViewController.m:127-133` (login test from `hash_check`) | not ported: see "Not modelled" |
| `QuoteMessageViewController.m:135-185` (`#dynamic_smilies` images: `src`, `alt`) | `ForumForm.dynamicSmileys` |
| `QuoteMessageViewController.m:187-190` (element named `hop`, its `input` and `select` descendants) | `HopFormParser.parse` |
| `QuoteMessageViewController.m:192-290` (value per name; `MsgIcon` only when checked; checkbox `"1"`/`"0"`; select selected or first option; `haveTitle`, `haveTo`, `haveCategory`, sub-category list) | `fields`, `selects`, derived `isSubjectEditable`, `recipient`, `isSubcategoryEditable`, `subcategories` (LOT-012) |
| `QuoteMessageViewController.m:459` (`content_form` contents, `\r\n` to `\n`) | `textareaContent` |
| `QuoteMessageViewController.m:532` (action appended to the forum URL) | `action`: the HTML attribute is the input, `ForumForm.action` the resolved, forum-origin output (never the raw attribute) |
| `Classes/AlerteModoViewController.m:144-178` (element whose `action` contains `modo.php`, its inputs) | `HopFormParser.parseModerationForm` |

Not ported: the selection-quote logic (`QuoteMessageViewController.m:460-520`), which builds a prefill client-side from a web selection.

## Behaviour

`HopFormParser` (`Sources/HFRParsing/Forms/HopFormParser.swift`), pure functions `(String, pageURL: URL) throws(ParsingError) -> ForumForm`.

| Call | Form | Missing form |
|---|---|---|
| `parse` | the first `<form>` whose `name` is exactly `hop` | `missingElement("form name=hop")` |
| `parseModerationForm` | the first `<form>` whose `action` contains `modo.php` | `missingElement("form action*=modo.php")` |

| `ForumForm` | Rule |
|---|---|
| `action` | the `action` attribute, entity-decoded, **resolved against `pageURL`** (default the forum root for `parse`, `/user/modo.php` for `parseModerationForm`) and returned as a forum-origin path (`/bddpost.php?config=hfr.inc`, `/bdd.php?config=hfr.inc`, `/user/modo.php?…`) through `HFRURL.forumRelativePath` (LESSONS 37, 43). Nil when the attribute is absent or empty, or when the action is off-origin (another host, `//host` to another host, an `http` URL that is not upgraded, a port other than 443, user info, `javascript:`); `http://forum.hardware.fr/…` without a port is upgraded to `https` and accepted: the session, `hash_check` and the text would go there. The rest of the form is still returned; **LOT-048 must not post when `action` is nil** and must not substitute a default silently |
| `fields` | every `<input>` with a `name` inside the form, in page order, duplicates kept (16 `MsgIcon` radios); `value` entity-decoded, `""` when absent; `kind` from `type` (LOT-012); `isChecked` = the `checked` attribute is present, whatever its value |
| `selects` | every `<select>` with a `name`, in page order; options (also inside `<optgroup>`) with `value` (the text when the attribute is absent, as a browser does) and trimmed text label; `selectedValue` = the first option with `selected`, nil when none |
| `textareaContent` | text of the `<textarea id="content_form">` of the form: entities decoded (by the HTML tokenizer), `\r\n` and lone `\r` read as `\n`, leading newline kept; nil when the textarea is empty or absent. It holds the quote or edit prefill, `[quotemsg=<numreponse>,<ref>,<author id>]` blocks included, untouched |
| `dynamicSmileys` | the `<img>` of the element `id="dynamic_smilies"` anywhere on the page: `alt` (non-empty) as `code`, `src` made absolute by `HFRURL.absolute`; an image without `alt` or with an unusable `src` is skipped |

The moderation form has no `content_form` and no `select`: `fields` is `hash_check`, `referer_page`, `Submit`.

### Not modelled
- **Login state.** `hash_check` is present on anonymous pages too (the header search form carries one), so legacy's "any `hash_check` with a value" is not a login test, and the model has no such flag (LOT-004 quirk 10). The anonymous composer (`R40b`) has an **empty** `hash_check` and `pseudo`; `HFRClient` decides what to do with that.
- **What is sent** (LOT-048): unchecked boxes, `MsgIcon` handling, `content_form` re-encoding to `\r\n`, overrides of `pseudo`, `hash_check`, `sujet`, `subcat`, `dest`. Also, a browser would: skip controls with `disabled` (`FormField` has no such flag); send only the clicked submit button (the form has one, `submit`); send every repeated name, e.g. the two identical hidden `subcat` inputs of `R40a` (`fields` keeps both, a name-keyed map keeps one); read `<button name>` (not read here, none in the captures).
- **A `.hop` message page** (rejection, logged-out wall, "already alerted", success) is not a form: both calls throw `missingElement`, and LOT-037 classifies the page.

## Edge cases
- Both calls look at `<form>` elements only (legacy took any element named `hop`): `<a name="hop">` is not an empty form. The real pages have a form.
- Controls outside the form (the `#fastsearch` form with its own `hash_check`, a second `content_form`) are not read; the smiley container is looked up on the whole page, like legacy.
- An input with no `name` (and `type="image"` without `name`) is skipped; `type="file"` and other types are kept with kind `.other`.
- A select with no option is kept (`effectiveValue` nil); two options with `selected`: the first wins, as in legacy (a browser would take the last; no captured page has two).
- A textarea starting with a newline keeps it (legacy, libxml, did too; a browser drops one newline after the tag). Every capture writes the text right after the tag, so HFR adds no newline of its own: a leading `\n` can only be part of the stored text, and keeping it makes the round trip exact. Verified: no capture starts with a newline; pending: a stored text that does (see "Pending capture").
- Option values are not trimmed (legacy trimmed the id of a sub-category; captured values have no whitespace).

## Fixtures
Captures `R40a, R40b, R41a, R41b, R42, R43a, R43b, R43c, R44, R45a, R45b, R46, R47a, R47b, R47c, R47u1` and their LOT-004 oracles (`Fixtures/LOT-004/<id>.oracle.json`, `result.legacy`); no new fixture. Tests: `HopFormOracleTests` (differential, every case of the oracle map, checked by a coverage test) and `HopFormParserTests` (facts of each capture, rules on small inline pages).

The differential test compares, per case: `action` with `formAction`; the legacy value-per-name map rebuilt from the parsed fields with the legacy rules (`MsgIcon`, checkbox `"1"`/`"0"`, select effective value) with `inputData`; field and select order with `loopOrder`; `textareaContent` with `contentForm` and with `contentFormRaw` after CRLF to LF; `isSubjectEditable`, `isSubcategoryEditable`, `recipient`, `subcategories` with `haveTitle`, `haveCategory`, `haveTo`, `subcats`; `dynamicSmileys` with `smileys`; `parseModerationForm` with the R46 case.

## Intentional differences from legacy
1. `fields` keep every named input, including those with no `value` attribute and the unchecked boxes with their `value`; legacy dropped inputs without a `value` attribute and replaced a checkbox value by `"1"`/`"0"`. The legacy map is a pure function of the parsed fields (`HopFormOracleTests.legacyInputData`), so LOT-048 can choose its semantics (LOT-012 decision 2; browser rule in HFR-PROTOCOL §3.1).
2. `isChecked` is true for a bare `checked` attribute; legacy needed `checked="checked"` (LOT-004 quirk 4; both agree on the captures).
3. Attribute values, option labels and the `action` are entity-decoded (legacy decoded through libxml; the live Swift service did not: bug B1, quirks 1 and 5).
4. Only `<form>` elements match `hop` and `modo.php`.
5. A select option without `value` reads as its text (browser rule); legacy sent nothing.
6. Option elements are found at any depth (`<optgroup>`); legacy walked the direct children and raised on whitespace between options (quirk 11, never seen on real pages).
7. `action` is resolved and restricted to the forum origin (legacy built `ForumURL + action`, `QuoteMessageViewController.m:532`, which also made an off-origin absolute action a broken URL, not a post elsewhere); the moderation action gains its `/user/` prefix (`AlerteModoViewController.m:176`).
8. No `isLogged`/`username` (see "Not modelled"); legacy `username` is the `pseudo` field.

## Pending capture
Not hand-built (LESSONS 36); each is a parser state or a protocol fact, none blocks this lot:
- **A new-topic form reached with a sub-category preselected** (`R45a` has no `selected` option, so `selectedValue` on HFR pages is only tested on inline pages).
- **An edit or quote form whose stored text starts with a newline**: confirms that HFR does not add its own newline (all captures suggest so) and so that a browser would drop a real one.
- **The reply form of a locked topic and of a topic where the account may not post**, to learn what the page serves instead of the form (LOT-037 reads the message).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- A capture read through a text-mode tool loses its CRLF: check line endings on the bytes (`R43a` stores `\r\n` as sent, only the oracle and a byte read show it).
- SwiftSoup decodes entities in attributes and in `<textarea>` (RCDATA) and keeps `\r\n` and a leading newline, unlike a browser: the parser normalises line breaks itself.
