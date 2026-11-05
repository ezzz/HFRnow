# LOT-087 — Message actions menu and typed JS bridge

- **Module:** App (`App/SwiftHFR/Reader/Actions/`)
- **Difficulty / model:** medium (Opus → Fable; coded by a cloud child, reviewed by Opus)
- **Issue:** [#179](https://github.com/ezzz/HFRnow/issues/179) (old [francoisgn/ios-app_SwiftHFR#](https://github.com/francoisgn/ios-app_SwiftHFR) lot issue linked from it)
- **Depends on:** LOT-083 (reader), LOT-031 (`MessageActions`). Absorbs Phase 4 backlog C14 (typed JS bridge) and C15 (message action policy).

## Legacy counterpart

Legacy repository <https://github.com/ezzz/HFRnow> at `2440d79`.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MessagesView.swift:111-193` (`MessagePopupMenuActionKind`: 13 actions, titles, symbols, destructive) | `MessageMenuAction` |
| `:196-275` (`MessagePopupMenuPolicy.orderedActionKinds`, `priority`) | `MessageMenuPolicy.orderedActions` |
| `:1169-1235` (`Coordinator` `WKScriptMessageHandler`, `scrollState` / `textInteractionState`, bodies read as `Any`) | `ReaderBridgeMessage.decode` (closed set, typed) |
| `:1722-1775` (entries built per action, each calling a `parent.on…Request` closure) | `MessageActionHandler` registry |
| `Classes/ObjCMessageActionsBuilder.m:91-104` (`permalinkURLForPostID`: page URL without fragment + `#<post>`) | `TopicReaderModel.permalink(of:on:)` |
| `HFRswiftTests/MessagePopupMenuPolicyTests.swift` | `MessageMenuPolicyTests` (same cases) |

## Behaviour

- **Bridge.** `reader.js` posts `{type, token, …}`. The app decodes five names (`images`, `tap`, `ready`, `video`, `menu`) into
  `ReaderBridgeMessage`; an unknown name, a body that is not an object, a non-integer or boolean number, a missing field, a post
  below 1 or an unknown `source` is rejected whole (nothing is partly read). The page never supplies code or a selector.
- **Menu button.** When a handler is registered, each non-continuation message draws a `⋯` button (`data-menu="message"`) and
  its author becomes a button (`data-menu="avatar"`, legacy: the avatar tap). The page sends `menu` with the number and one of those
  two names; the model checks the document token and that the page holds the message, then asks the registry.
- **Policy** (pure, `MessageMenuPolicy`): ported from legacy, same order and titles (`Link` stays `Link`). `isOwnMessage`,
  `canBeFavorite` and `canDelete` are derived from `MessageActions` as LOT-031 decides (edit link ⇒ own; flag link ⇒ favourite; edit
  link and not the topic's first message ⇒ delete). The first message is the first non-continuation block of page 1.
- **Registry.** `MessageActionRegistry` holds `MessageActionHandler`s by `MessageMenuAction.Kind`. An action without handler, or
  whose handler declines (`isAvailable`), is hidden. `canAQ` and `canBookmark` are the AQ / bookmark handlers' answer. A later lot adds
  its handler in `TopicReaderView.installMenuActions()`; the policy is untouched.
- **Link.** `LinkActionHandler` copies the permalink and shows "Lien copié". Permalink = the page's final URL (forum `https`,
  fragment dropped) + `#t<numreponse>` (HFR-PROTOCOL §6c: permalinks are `#t<message>` on a canonical URL); nil when the page URL is unknown.
- Only **Link** has a handler in this lot, so the avatar menu is empty and opens nothing until profile / MP / BL / WL land.

## Edge cases

- Logged out: LOT-031 gives only quote and profile links, so only Link (and Alerter, which needs the handler of its lot) can show.
- Stale token, unknown or continuation message, empty entry list: nothing opens.
- Own message: no MP, BL/WL, alert. First message of the topic: no delete.
- The dialog closes before the action runs, so `perform(_:in:)` takes the menu the user saw.

## Fixtures

`R20` (logged out) and `R21` (logged in) through `LiveTopicPageSource` (`messagesCarryTheirToolbarActions`). No new capture.

**Pending capture:** #273 (own post on a public topic: edit link shape, which MP / flag / alert links remain). Until it lands the
own-post rules are LOT-031's (`RA4`: edit on own posts of a private thread) and the legacy policy above; review #330 checks them.
Not decided here, left to the lot of each handler: the alert mail fallback (legacy `onPopupAlertMailRequest`), the multi-quote cookie
state (`isQuoteSelectionEnabled` stays false until LOT-086), and the "flag here" action (`favorite`: a state-changing GET, needs the
session check of LOT-044 and `TopicFlagFlow`; no handler yet, so hidden).

## Intentional differences from legacy

1. The bridge decodes into a closed enum (legacy read untyped `Any` bodies, silently ignoring bad shapes).
2. Actions without a merged handler are hidden, never shown and ignored.
3. "Link" copies to the pasteboard (issue scope); legacy opened the share sheet.
4. A message's `page=` / `delete` rules come from LOT-031's derived fields, not from legacy `ObjCMessageActionsBuilder` flags.

## Learnings

- A SwiftUI `confirmationDialog` clears its presenting state before the button's action runs: hand the action the item it was
  shown for, never read it back from the model.
- `NSNumber` from WebKit's bridge also holds booleans: reject `CFBoolean` explicitly or `true` decodes as `1`.
