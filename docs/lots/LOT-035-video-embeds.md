# LOT-035 — Video embed detection

- **Module:** HFRParsing
- **Difficulty / model:** easy (the plan routes Sonnet → Opus; taken by an Opus contributor, `ext/bybifok-opus-1`, so the reviewer is Fable)
- **Issue:** [#62](https://github.com/ezzz/HFRnow/issues/62)
- **Depends on:** LOT-034 (#61): `MessageContentNormalizer`, `MessageContent.html`; LOT-011 types `MessageEmbed`, `EmbedProvider` (unchanged).
- **Audit:** C09 (`docs/audit/C-message-parsing.md:383`).

## Legacy sources

Legacy app: `francoisgn/hfrnow` at `2440d79` (an ancestor of `origin/master`).

| Legacy | What it gives this lot |
|---|---|
| `HFRswift/Wrapped/ParseMessagesOperation.m:241-244` | the four patterns: YouTube `…be.com/…v=<id>` on `www.`/`m.`/`gaming.`, `youtu.be/<id>`, Vimeo `vimeo.com/[<word>/…]<number>`, Streamable `https://streamable.com/<id>` |
| `:247-257` | Dailymotion, Coub and Twitch commented out |
| `:260-265` | candidates: every `a.cLink` of the page whose third ancestor is `messCase2` and whose parent is not `.signature` |
| `:274-283` | YouTube player `https://www.youtube.com/embed/<id>`, start from `(?:\?\|&)t=(?:(\d+)h)?(?:(\d+)m)?(\d+)s$`, hours counted as minutes × 3600 (`:281`) |
| `:287`, `:297` | Vimeo player `https://player.vimeo.com/video/<id>`, Streamable `https://streamable.com/s/<id>` |
| LOT-003 spec Q25 | `t=1h2m3s` gives `start=7323`; `youtu.be/…?t=90` gets no start |

## Behaviour

`Sources/HFRParsing/Topic/MessageEmbedDetector.swift`, called by `MessageContentNormalizer.normalize` at the end: `MessageContent.embeds` is filled whatever the display settings (LOT-034); showing a player is app policy (LOT-071, LOT-108).

- **Candidates** (`embeds(inNormalizedHTML:)`, on LOT-034's `html`): an `a.cLink` that is a child of a top-level element of the content (legacy's third ancestor `messCase2`: link → paragraph → `div#para` → cell) and has no child element.
  - A link nested deeper (bold, a quote, a spoiler, a list) stays a link, as in legacy.
  - So does a link around an image or with formatted text.
  - The signature is outside `html` (LOT-034), so a video link there never becomes an embed (`:263`).
  - The link stays in `html` and `links`, so the text is unchanged; the app adds a player placeholder per embed (LOT-071 D-071-2).
- **Hosts** (`embed(for:)`): legacy's four patterns, anchored at the start of the absolute URL, with their dots escaped. On `youtube.com` the id is the `v` query parameter itself (legacy's `.+v=` also matched the end of `notv=`). Any other host, or a look-alike (`youtubeXcom`, `youtube.com.example.org`), stays a link.
- **Player URL** built from the extracted id only (`[\w-]+` or digits), never copied from the page: `https://www.youtube.com/embed/<id>`, `https://player.vimeo.com/video/<number>`, `https://streamable.com/s/<id>`.
- **Start** (YouTube only, as in legacy): the link's last `t` query parameter, appended to the player as `?start=<seconds>` and kept in `startSeconds`.
  - Accepted forms: plain seconds (`t=706`, up to 6 digits) or `[<h>h][<m>m][<s>s]` (`t=1h2m3s` is 3723 s).
  - No start for zero, an empty value, any other form, or `start=`.

## Edge cases

- `R20`'s `https://youtu.be/RrGdyybzPVA?t=1m5s` (message 2666649) plays from 65 s; legacy's player started at 3665 s (one hour later).
- `R28`'s `https://youtu.be/L_2ggcnsMog?t=706` (message 75482040) plays from 706 s; legacy embedded it without a start, because its pattern needed a final `s`.
- An `a.cLink` without text is no candidate (legacy's `>([^<]+)</a>`, `LinkItem.m:149`).
- `t=1h2m3s&feature=share`: start 3723 (legacy read only a `t=` at the very end of the URL).
- `t=10&t=20`: the last one, 20.
- A second link to the same video in the message gets its own embed, as legacy embedded each link.
- Vimeo's `#t=` and Streamable starts are not read (legacy read none).

## Fixtures

Captures and oracles only, nothing new: the 21 LOT-003 topic oracles (run with `embedded_videos=yes`): 133 `div.embedvideo` iframes over 8 pages. Message 2666649 of `R20`, `R21` and `P03m` alone holds 42 (34 `youtube.com/watch`, 6 `youtu.be`, 2 Vimeo), including `youtu.be/RrGdyybzPVA?t=1m5s`, which legacy embedded with `start=3665`. `R28` holds the plain-seconds start. The candidate rule's other edges are small content fragments (a link in bold, in a quote, in a signature, around formatted text): no page state, the structure the rule reads. The corpus has `youtube.com/watch?v=`, `youtu.be` (with `t=1m5s` and `t=706`) and `vimeo.com/<number>` links (`R20`, `R22a`, `R22b`, `R27`, `R28`); Streamable, a `t=` with hours and a video link inside a signature are not in it (pending capture).

## Tests

- `MessageContentOracleTests` (differential, the 21 LOT-003 topic oracles, LESSONS 51): on every message, `embeds` are exactly the links legacy replaced by an iframe (the source links, in order), and their players equal the iframes' `src` once the query is dropped.
- `MessageEmbedDetectorTests`:
  - each host form (8 cases) and 14 links that stay links, `watch?notv=` among them;
  - starts (7 forms) and no-start cases (7);
  - no start on Vimeo and Streamable;
  - the captured starts: `R20`'s `t=1m5s` gives 65 s where legacy's iframe says 3665, `R28`'s `t=706` gives 706 s;
  - an empty `a.cLink` is no candidate (legacy's `>([^<]+)</a>`, `LinkItem.m:149`);
  - the candidate rule on fragments;
  - the corpus count: exactly 133 embeds, 6 of them Vimeo.

Shown to fail with the behaviour removed (each mutation caught): legacy's hour bug, plain seconds refused, the first `t` instead of the last, the first `v` instead of the last, a `…v` suffix (`notv=`) read as `v`, a partial id match (`v=a%20b`), a zero start kept, no start in the player URL, any depth accepted, links with elements accepted, an empty link accepted, Streamable over `http`, unescaped dots, Vimeo without path segments, the detector not called by `normalize`, a start on Vimeo.

## Pending capture

- Streamable links and a `t=` with hours in a captured message (unit cases from the legacy patterns until then).
- A video link inside a signature, with the oracle re-run with `display_sig=yes` and `embedded_videos=no` (#268).

## Intentional differences from legacy

1. **Hours are hours**: `t=1h2m3s` starts at 3723 s (legacy 7323, minutes × 3600, `:281`), and `R20`'s `t=1m5s` at 65 s (legacy 3665). [CHANGELOG-LEGACY](../CHANGELOG-LEGACY.md) row 49.
2. **Plain seconds and a `t` anywhere in the query give a start** (`t=706`, `R28`; legacy needed `t=…s` at the end of the URL, `:275`). Row 49.
3. **Host dots are literal** (legacy's `.` matched any character), and a `youtube.com` id comes from the last `v` parameter only (legacy's greedy `.+v=` took the last `v=` too, but any `…v=` suffix as well, so `notv=abc` gave a player); both only concern look-alike links.
4. **Depth on the normalized tree**: unknown wrappers are unwrapped by LOT-034, so a text link inside one (`<center><p><a class="cLink">`) is a candidate here; legacy counted three real ancestors. No capture has one.
5. **The link stays in the text**: legacy replaced it by an iframe that loaded at once; here the app shows a placeholder and loads nothing before a tap (LOT-071 D-071-2).

## Learnings

- A rule legacy applied by position (third ancestor) needs the structure, not just the list of links: read it on the normalized HTML, where the oracle test of LOT-034 already found it.
