# LOT-108 — Video placeholder, player on tap

- **Module:** App
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#199](https://github.com/ezzz/HFRnow/issues/199)
- **Depends on:** LOT-035 (embeds, merged), LOT-083 (reader, merged)

## Legacy counterpart
Port of `Wrapped/LinkItem.m:148-158` (the `<iframe src=…>` builder) and `Wrapped/ParseMessagesOperation.m:238-300`
(`embedded_videos`) @ 2440d79 (GAP-058). Legacy auto-loaded one player iframe per link; the live app dropped embeds in `d645f52`
(see LOT-071). Intentional difference: placeholder, player on tap (LOT-071 D-071-2, decided 2026-10-27).

## What LOT-083 already shipped (not redone here)
Placeholder `button.video` per `MessageContent.embeds` entry (`TopicHTMLBuilder.videos`, no provider URL in the page),
`ReaderWebController` `video` event, `TopicReaderModel.video(post:index:token:)`, `VideoPlayerSheet` (own web view, JavaScript on,
non-persistent store, `https` on the provider's hosts only, main frame kept on that host).

## What this lot adds
- **"Ouvrir le lien" fallback** in `VideoPlayerSheet`: a toolbar button opening the member's original link (`MessageEmbed.sourceURL`)
  through `openURL`, limited to `http`/`https` with a host (`fallbackURL(for:)`). It stays available when the player cannot load
  (`playerURL` nil), where the sheet now explains it. The button deliberately goes straight to the system `openURL`, not through
  the reader's "open links in the default browser" setting: it is an explicit tap on a video, and "open in app" is the system's
  choice (a YouTube link goes to the installed app by universal link, else Safari). No provider-specific scheme is built.
- **Tests**: `VideoPlayerSheetTests` (player URL and fallback rules); `ReaderWebControllerTests` drives the real web view. A loopback
  `ConnectionCounter` stands for the provider (the embed and source URLs of one video point at it, as in `noRemoteRequestLeavesThePage`):
  before and after the tap it counts no connection from WebKit itself, the page holds no `iframe` and names no provider URL, the web
  view stays on its reader page, and a tap reports exactly `(post, index, token)`. A positive control loads that server in a plain
  `WKWebView` and must see a connection, so the zero is not a blind spot.

## Edge cases
- Embed whose player URL fails the host check: unavailable view + browser fallback.
- Source link with another scheme (`tel:`, `file:`): no fallback button.
- Tap on a stale document: `video(...)` returns nil, nothing opens (existing test).

## Pending capture / Mac check
Rendering of placeholder and sheet (light, dark, Dynamic Type XL, iPad), real YouTube/Vimeo/Streamable playback, and what `openURL`
does on a device with the YouTube app: listed in the PR's "Mac check needed".

## Learnings
none yet.
