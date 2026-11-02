# LOT-097 — BBCode preview renderer

- **Module:** HFRParsing
- **Difficulty / model:** difficult (Fable → Opus)
- **Issue:** [#189](https://github.com/ezzz/HFRnow/issues/189) · implements FEAT-013 ([#157](https://github.com/ezzz/HFRnow/issues/157), proposed by Bybifok, credit in CREDITS.md); the app half is LOT-152 ([#242](https://github.com/ezzz/HFRnow/issues/242))
- **Depends on:** LOT-034 (`MessageContentNormalizer`), LOT-020 (`HFRURL`)
- **Decision:** [ADR 0014](../adr/0014-bbcode-preview-renderer.md) — a local renderer in `HFRParsing`, whose output goes through the LOT-034 normalizer so the reader shows a preview exactly as it will show the posted message.

As a poster, I want to preview my message as HFR will render it, so that I fix formatting before sending.

## Legacy sources

None: the legacy app has no preview. Reference only, at `2440d79` of <https://github.com/ezzz/HFRnow>:

| Legacy | Role here |
|---|---|
| `HFRswift/Swift/ReplyComposer.swift:99-205` (`ReplyTextInsertionEngine`: wraps a selection in `[b]…[/b]`, splits a quote) | the tags the composer produces; the engine itself is LOT-085 / LOT-174, nothing of it renders |
| `HFRswift/Wrapped/LinkItem.m:96-141, 163-247` (rendering of posted messages) | already ported by LOT-034; the renderer reuses that port instead of a second rendering |
| ultra-hfr `HFRContent` (`BBCodeParser`, `BBCodeWriter`, MPL-2.0), redface2 `BbcodeContentParser` | ideas only (ADR 0014 option 5), no copy |

HFR facts: the composer toolbar help (`R40a`: `TAinsert('[b]','[/b]')` … for `b i u strike spoiler quote url img fixed email cpp` and `[*]`, the colour button inserting `'['+bgColor+']'`), the round-trip captures `W61` (source posted), `R95c` (edit form, source byte for byte) and `R95d` (`POST /apercu.php`, HFR's own preview), `R95h` (BMP emoji), [HFR-PROTOCOL §6b "BBCode round trip"](../HFR-PROTOCOL.md#6b-live-observations-from-the-capture-corpus-lot-001-2026-10-26).

## Behaviour

### API

| Type | Members | Rules |
|---|---|---|
| `BBCodeRenderer` (public) | `render(_ source: String, options: BBCodeRenderOptions = .init()) throws(ParsingError) -> MessageContent` | `source` is the composer text as the posting flow will send it; `\r\n`, `\n` and `\r` are one line break each. Pure; only a backend failure throws (`malformedDocument`). `signatureHTML` is always nil |
| `BBCodeRenderOptions` (public) | `smileysEnabled: Bool = true`, `smileys: [String: URL] = [:]` | `smileysEnabled` is the composer's `smiley` checkbox read as HFR does (checked = disabled, §6b "Checkbox values"), sent to HFR's own preview as `apercu_smiley`. `smileys` maps a code as typed (`:jap:`, `[:user]`) to its image URL; the app builds it from `CommonSmileyCatalog` and the member's personal smileys. **Inactive until the smiley pair is captured** (Pending capture 1): the table is read by nothing, codes stay text |
| `BBCodeParser` (internal) | `parse(_ source: String) -> [BBCodeNode]` | text, line break, inline tag with its content, block tag with its content; every bracket that is not a known, matched tag is text |
| `HFRMarkupWriter` (internal) | `tree(for nodes: [BBCodeNode]) -> Element` | the HFR shapes below, assembled bottom-up on an explicit stack (LOT-034 learning), then `MessageContentNormalizer.normalize(_:relativeTo:)` |

### Rendering table (one shape per tag, from `R95d` unless noted)

The message is a sequence of paragraphs and blocks. Text and inline tags live in a `<p>`; a block tag closes the paragraph, writes its block, and opens a new paragraph (`</p>…<p>` in `R95d`). A line break is `<br />` (HFR writes `\r<br />`: the CR is kept as text and is a reduction of the tests). The thread page wraps the message in an opening `<p>` that `/apercu.php` omits (measured on the raw pages, #400).

| Source | Shape | Note |
|---|---|---|
| `[b]x[/b]` | `<strong>x</strong>` | |
| `[i]x[/i]` | `<em>x</em>` | |
| `[u]x[/u]` | `<span class="u">x</span>` | |
| `[strike]x[/strike]` | `<strike>x</strike>` | |
| `[b][i]x[/i][/b]` | `<strong><em>x</em></strong>` | nesting of inline tags |
| `[spoiler]x[/spoiler]` | `<div class="container"><table class="spoiler"><tr class="none"><td><b class="s1Topic">Spoiler :</b><br /><br /><div class="Topic masque"><p>x</p></div></td></tr></table></div>` | block; HFR's `onclick` and `style="cursor:pointer;"` are dropped by the normalizer and not emitted |
| `[quote]x[/quote]` | `<div class="container"><table class="quote"><tr class="none"><td><b class="s1">Citation :</b><br /><br /><p>x<br /></p></td></tr></table></div>` | block; a trailing `<br />` inside the body (none in a spoiler) |
| `[url]U[/url]` | `<a href="U" class="cLink">U</a>` | `target="_blank"` dropped by the normalizer; `U` goes through `normalizedURL` (http(s) only, else the link is unwrapped to its text) |
| `[url=U]x[/url]` | `<a href="U" class="cLink">x</a>` | same |
| `[img]U[/img]` | `<img src="U" alt="U" title="U" />` | HFR adds `onload="md_verif_size(…)"` and `style="margin: 5px"`, dropped; the normalizer classifies it (`images`, or `smileys` for a `forum-images.hardware.fr` smiley path, as for a posted message) |
| `[fixed]x[/fixed]` | `<table class="fixed"><tr class="none"><td><p>x</p></td></tr></table>` | block, no `container`; raw `<`, `>`, `&`, `"` in `x` are text; spaces: see Edge cases |
| `[code]x[/code]` | `<table class="code"><tr class="none"><td><b class="s1">Code :</b><br /><ol class="olcode"><li>line</li>…</ol></td></tr></table>` | block; one `li` per line (`R27b` for several lines); HFR's `id="codeN"` and the header's `font-family` style are dropped |
| `[cpp]x[/cpp]` | same as `code` | **without** HFR's syntax colours (Pending capture 5) |
| `[*]x` | `<ul><li>x</li></ul>` | block: the first `[*]` of a line opens the bullet, which holds the rest of the line (a second `[*]` on it is text); the line's own break is consumed (`R95d`: no `<br />` after `[/list]`; the "Vue Rapide" keeps a `\r` inside the `li`) |
| `[color=#FF0000]x[/color]`, `[list]`, `[/list]`, `[b]` never closed, `[/b]` never opened, any other `[…]` | the text itself | `R95d` for the first four; the rule extends to every bracket the table does not match |
| `a\r\nb` | `a<br />b` | |
| `<b> & "` in text | `&lt;b&gt; &amp; &quot;` as serialized by SwiftSoup | HFR writes `&#034;`: same text after parsing |
| BMP emoji, U+FE0F | the characters, as text | `R95h`; characters above U+FFFF are text too (LOT-048 refuses them before sending) |

### Differential tests (ADR 0004)

`BBCodeRendererOracleTests`, one test per captured pair:

| Pair | Source | Oracle | Comparison |
|---|---|---|---|
| `W61` → `R95d` | `content_form` of `W61.meta.json` (percent-decoded; equal to the `textarea` of `R95c`, CRLF) | inner HTML of `body.reponse` in `R95d`, without the template's leading line break and the `<div style="clear: both;"> </div>` trailer, prefixed with `<p>` (thread shape), then `MessageContentNormalizer.normalize(contentHTML:)` | every field of `MessageContent` equal; `html` compared after removing `\r` from the oracle (nothing removed on the renderer's side) |
| `W62` → `R95h` | `content_form` of `W62.meta.json` | same extraction | same |

Both tests fail without the renderer (a renderer returning the source as text gives another `html`), and count their expectations (`links` 2, `images` 0, `smileys` 1 — the `jap.gif` image is on a smiley path — for `W61`) so a vacuous equality is noticed (LESSONS 51).

`BBCodeRendererSanitizationTests` (inline sources, no capture): `[url=javascript:alert(1)]x[/url]` → text `x`, no link; `[img]data:…[/img]` → no image; `JaVaScRiPt:` and `java\nscript:` variants; `<script>` and `onload=` in text stay text; `[url]` with user info; 10 000 nested `[b]` on a 512 KB-stack thread. `BBCodeParserTests`: every text-fallback rule (unknown tag, unclosed, stray closing, `[/b]` before `[b]`, bracket inside a word, `[` alone, empty source, source made of line breaks only).

## Edge cases

- **Spaces in `fixed` and `code`** (`R95d`, one sample each): `fixed   text  <tag>` → `fixed &nbsp; text &nbsp;&lt;tag&gt;` (3 spaces → space, NBSP, space; 2 spaces → space, NBSP); `code   text` → `code&nbsp; &nbsp;text` (3 spaces → NBSP, space, NBSP). Narrowest rule reproducing both: inside a run of two or more spaces, alternate NBSP and space, starting with a space in `fixed` and with an NBSP in `code`; a single space stays a space (`int x = 1;`). Other run lengths, leading spaces and tabs: Pending capture 7.
- **Line break after a block**: the break that follows `[/spoiler]`, `[/quote]`, `[/fixed]`, `[/code]` or `[/cpp]` is rendered as `<br />` at the start of the next paragraph (`<p>\r<br />…`), the break before a block tag as `<br />` at the end of the previous one (`…\r<br /></p><div`). Two blocks separated by one line break give a paragraph holding only a `<br />`, kept by the normalizer (it has a child); two adjacent blocks give an empty `<p>`, dropped by the normalizer on both sides.
- **Bullet line**: the line's own break is consumed by the `</li></ul>`; the paragraph that follows opens directly on the next line's text (`<p><strong>` in `R95d`).
- **URL schemes**: the renderer never decides; `normalizedURL` does (http(s), absolute, `hardware.fr` upgraded to https, `hfr-rehost.net` → `reho.st`). What HFR does with another scheme is Pending capture 6 and does not change our output (ADR 0014 §4).
- **Unclosed block**: `[quote]x` without `[/quote]` is text (same rule as `[b]unclosed bold`); whether HFR closes it is Pending capture 8.
- **Message cut by HFR**: a character above U+FFFF is rendered as text; LOT-048 refuses the send, so no preview of a text HFR would truncate (`W12`) is ever sent.
- **Depth and size**: linear parse; bottom-up tree; checked at 10 000 nested tags (robustness bound, not an observed HFR limit).

## Pending capture

Opened as one `host: mac` capture issue by this lot (ADR 0014 §3); every row is a fidelity gap of the preview until its pair exists. All are readable through `POST /apercu.php` (`R95d`: renders without posting).

1. **Smileys** with `apercu_smiley=0`: standard codes (`:)`, `:D`, `:o`, `:jap:`, `:??:`), a personal `[:user]` and `[:user:1]`, a code glued to a word, inside `[code]`, `[fixed]`, `[url]` and `[img]`; the same source with `apercu_smiley=1`. Until then `smileys` of `BBCodeRenderOptions` is read by nothing.
2. **Colour**: the toolbar's own syntax `[#FF0000]x[/#FF0000]` (`R40a`), a named colour, `[color=red]`.
3. **`[email]a@b.c[/email]`** and an email in plain text.
4. **Bullets**: `[*]` on three consecutive lines, with and without `[list]…[/list]`, a `[*]` mid-line, an empty `[*]`.
5. **`[cpp]`** with several keywords, strings, comments, several lines (the colour table), and whether `[c]`, `[java]` or another language tag exists.
6. **URLs**: `[url]` and `[img]` with `http://`, `ftp://`, `javascript:`, `www.` without scheme, a non-image target, a URL holding `&` and `"`; a bare `https://…` in text (auto-link or not).
7. **Whitespace**: runs of 1 to 6 spaces in plain text, `fixed` and `code`; leading spaces; a tab; an empty line; three consecutive line breaks; trailing line breaks.
8. **Nesting and malformed**: quote in quote, spoiler in quote, code in quote, `[b]` across a line break, `[b]` inside `[url=]`, `[url]` inside `[b]`, `[quote]` never closed, `[/quote]` alone, `[b][/b]`, `[b]` inside `[code]` (escaped or rendered), `[quotemsg=1,1,1]x[/quotemsg]` (the prefill shape of `R41a`: its header link).
9. **Limits**: the longest message HFR accepts and the deepest nesting it renders (also wanted by #268).
10. **Thread vs preview**: one public pair (a post on the test topic and its `/apercu.php`) published together, so the "whitespace aside, opening `<p>`" difference measured on private raw pages in #400 is checked by a test.

## Intentional differences from HFR

1. **Attributes outside the ADR 0006 contract are not emitted** (`onclick`, `style="cursor:pointer;"`, `onload`, `style="margin: 5px"`, `target="_blank"`, `id="codeN"`, the header's `font-family`): the normalizer drops them from posted messages, so the preview equals the posted message, not HFR's bytes.
2. **Non-http(s) URLs** are text (links) or removed (images), whatever HFR renders: the preview is sanitized by the same rules as every message.
3. **`[cpp]` has no syntax colours** until Pending capture 5.
4. **Smiley codes are text** until Pending capture 1.
5. **`\r` is not emitted** before a `<br />`: invisible whitespace that the tests remove from the oracle.

## Fixtures

`W61.meta.json`, `R95c-mp-edit-form-bbcode-source.html`, `R95d-apercu-bbcode-preview.html`, `W62.meta.json`, `R95h-apercu-bmp-emoji-preview.html` (captures of #400, run 9, `Fixtures/captures/`). No legacy oracle exists for `/apercu.php` (legacy has no preview): the oracle is HFR's own rendering through LOT-034, as ADR 0014 §2 says. `R27b` (several code lines) and `R20`/`R26` (quotes, smileys) are the rendered shapes the table cites for what one pair does not show.

## Learnings

To copy into AGENTS.md §11 when the lot closes:

- HFR renders one source at least three ways: the message (= `/apercu.php` modulo whitespace and the opening `<p>`) and the "Vue Rapide" review (`[img]` as a link). A rendering fact names which one it comes from.
- The composer's colour button inserts `[<colour>]…[/<colour>]`, not `[color=…]`: read the toolbar's `TAinsert` calls before writing a capture checklist of tags.
