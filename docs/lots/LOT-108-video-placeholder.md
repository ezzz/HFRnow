# LOT-108 — Video placeholder, player on tap

- **Module:** App
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#199](https://github.com/ezzz/HFRnow/issues/199)
- **Depends on:** LOT-035 (embeds, merged), LOT-083 (reader, merged)

## Legacy counterpart
Port of `Wrapped/LinkItem.m:148-158` (the `<iframe src=…>` builder) and `Wrapped/ParseMessagesOperation.m:238-300`
(`embedded_videos`) @ 2440d79 (GAP-058). Legacy auto-loaded one player iframe per link; the live app dropped embeds in `d645f52`
(see LOT-071). Intentional difference: placeholder, player on tap (LOT-071 D-071-2, decided 2026-10-27).

**Legacy at `2fe43da3`** (the parity reference since #655): no embeds at all. `d645f525` removed the `embedded_videos` block of
`ParseMessagesOperation.m` and the iframe builder of `LinkItem.m`, and the "Afficher les vidéos" setting (`Root.inApp.plist`; its `AppSettingsView.swift` picker was
already commented out at `2440d79`): a video link is a plain link. Against that reference the placeholder and its player are a SwiftHFR
addition, not a privacy fix of a legacy behaviour (GAP-058).

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

## Added by #752 (YouTube Referer, unavailable state)
- The YouTube player request carries the app's `Referer` (LOT-071 R3 exception); without it the player shows "Erreur 153" (Mac check of
  2026-11-10 on #499). `VideoPlayerSheet.playerRequest(for:)` is the one place that sets it, for YouTube's player hosts only.
- The player web view reports a failure to the sheet when the main frame answers a status of 400 or more (the Vimeo 401 of a removed or
  private video) or cannot load; the sheet then shows "Vidéo indisponible" with the "Ouvrir le lien" button, never a blank page.
  WebKit does not resend the `Referer` after a redirect (probed on a 302 to the same host, review of #761): a future YouTube redirect on
  the player URL would bring error 153 back; re-check then.
  A YouTube error drawn inside a page that answered 200 is not detected: the player's own "Regarder la vidéo sur YouTube" link stays.

## Edge cases
- Embed whose player URL fails the host check: unavailable view + browser fallback.
- Source link with another scheme (`tel:`, `file:`): no fallback button.
- Tap on a stale document: `video(...)` returns nil, nothing opens (existing test).

## Pending capture / Mac check
Rendering of placeholder and sheet (light, dark, Dynamic Type XL, iPad), real YouTube/Vimeo/Streamable playback, and what `openURL`
does on a device with the YouTube app: listed in the PR's "Mac check needed".

## Learnings
none yet.
