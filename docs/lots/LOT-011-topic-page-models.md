# LOT-011 — Topic page and message models

- **Module:** HFRModels
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [C §3.2, §3.3, §3.5, §7 (C01)](../audit/C-message-parsing.md), [ADR 0006](../adr/0006-content-normalization-in-parsing.md) with amendment 1, [B §3.6 and 2.1](../audit/B-list-parsing-models.md) (poll), [redface2 comparison](../research/redface2-comparison.md) §4.3 E18 and E20.

| Legacy | What it gives the models |
|---|---|
| `HFRswift/Wrapped/LinkItem.m:23-303`, `ParseMessagesOperation.m:137-404` | message fields: `postID`, author, deleted flag, avatar, date, content, quoted count/link, edit trailer |
| `ParseMessagesOperation.m:371-390` | action links: quote, edit, alert, profile, MP, `addflag`, `quoteJS` |
| `ParseMessagesOperation.m:191-224` | quote blocks (author, class, nesting) |
| `ObjCTopicPageWorker.m:150-179` | page-level data: answer form URL, hidden fields, `nonlu`, poll, in-topic search form |
| `HFRswift/Swift/ObjCMessageActionsBuilder.m:9-62`, `Common.swift:1615-1636` | the "actions" dictionary that `MessageActions` types |
| `HFRswift/Swift/PollData.swift:12-36` | `PollOption`, `PollResult`, `PollData` |
| `HFRswift/Wrapped/LinkItem.m:96-190`, ADR 0006 | images, smileys, links, embeds the normaliser emits |

## Behaviour
Value types, all `Sendable`, `Hashable`, `Codable` (oracle JSON and tests). Output of LOT-030/031/032/033/034/035/026.

| Type | Role |
|---|---|
| `TopicPage` | title, `currentPage`, `maxPage`, answer form URL and hidden fields, `isUnreadable`, poll, in-topic search fields, messages |
| `Message` | `id` (= `numreponse`), author, deleted, avatar URL, date text, `MessageContent`, quotes, edit note, quoted-by count and link, `MessageActions` |
| `MessageContent` | sanitised `html`, `signatureHTML?`, typed `images`, `smileys`, `links`, `embeds` (ADR 0006) |
| `MessageImage`, `MessageSmiley`, `MessageLink`, `MessageEmbed`, `EmbedProvider` | the typed lists; `URL`s only, http(s) by construction of the parser (ADR 0006 amendment 1) |
| `MessageActions`, `QuoteSelectionToken` | absolute, de-obfuscated action URLs; multi-quote arguments |
| `MessageQuote` | author (nil if anonymous), depth, cited message number from the `#t<id>` fragment (E20) |
| `Poll`, `PollOption`, `PollResult` | `Poll.Kind` is `.votable(options:hiddenFields:)` or `.results(_)` |
| `PostID` | (`TopicID`, `numreponse`): the cross-topic message key (E18) |

Decisions:

1. **Key design (E18).** `numreponse` is unique per category only. `Message.id` is the bare number (unique within a page, always available); `TopicPage.postID(of:)` builds the full `PostID`, nil when the topic is unknown. This avoids a non-optional composite id that would need a topic the parser cannot always provide.
2. **`CategoryID` / `TopicID`** are shared with LOT-010 and added byte for byte in both PRs (see the LOT-010 spec); `Support.swift` (test helper) likewise.
3. **Absolute `URL`s** in these models (ADR 0006 amendment 1), unlike the relative `String` paths of LOT-010.
4. **`Poll.Kind` carries its data.** The audit proposed `PollData` with both `options` and `results` plus a kind; an enum with payloads makes "votable with results" unrepresentable. The `String`-keyed `id` of `PollData` (the question text, not unique) is dropped.
5. **UI-policy flags stay out** (`canAQ`, `canBookmark`, `canDelete`, `canBeFavorite`, `isOwnMessage`; audit C 7.2 C04/C15). `isOwnMessage` is `actions.editURL != nil` for whoever needs it. No avatar cache path, no `MessageRenderOptions` (ADR 0006), no permalink (derived by LOT-020 helpers).
6. `dateText` stays text (audit C 3.2: no `Date`); a `Date` accessor can be added with LOT-020's HFR date helpers.
7. The form field dictionaries (`answerFormFields`, `searchFormFields`) hold `hash_check`: documented as secrets, and `TopicPage` and `Poll.Kind` print and reflect them as a count with values redacted (`description`, `debugDescription`, `customMirror`); `Codable` still carries them.
8. The initializers floor `currentPage`, `maxPage`, `Poll.maxChoices` and `MessageQuote.depth` at 1. Unlike LOT-010's `pageCount`, decoding does not re-apply the floors: these values come from our own parsers, not from persisted user data.

## Edge cases
- Anonymous quotes: `MessageQuote.author == nil`.
- Messages without a toolbar date: `dateText == ""`.
- Topics whose category/number cannot be read: `topicID == nil`, `postID(of:)` returns nil.
- Poll results with decimal percentages round-trip as `Double`.
- Private conversations: `TopicID.category == .privateMessages`.

## Fixtures
None (fixture-free lot). Differential tests arrive with LOT-030 and following.

## Intentional differences from legacy
- Reference types and string dictionaries (`swiftMessageActionsByIndex`) become typed values.
- `MessageContent` replaces `dicoHTML` raw text plus string surgery (audit C 4.2); no libxml2 byte-for-byte HTML.
- The `index`-keyed action dictionary disappears: actions live on the message.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- Keep a model's identity separate from the context it is looked up in: `numreponse` alone identifies a message on a page, the (category, topic, numreponse) triple identifies it everywhere.
