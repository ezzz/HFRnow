# LOT-097 — BBCode preview renderer

- **Module:** HFRParsing
- **Difficulty / model:** difficult (Fable → Opus)
- **Issue:** [#189](https://github.com/ezzz/HFRnow/issues/189) · implements FEAT-013 ([#157](https://github.com/ezzz/HFRnow/issues/157), proposed by Bybifok, credit in CREDITS.md); the app half is LOT-152 ([#242](https://github.com/ezzz/HFRnow/issues/242)); captures wanted: CAP-N4 ([#172](https://github.com/ezzz/HFRnow/issues/172), done in #400: `W61` / `R95d`, `W62` / `R95h`) and the batch 2 of [#443](https://github.com/ezzz/HFRnow/issues/443)
- **Depends on:** LOT-034 (`MessageContentNormalizer`), LOT-020 (`HFRURL`)
- **Decision:** [ADR 0014](../adr/0014-bbcode-preview-renderer.md) — HFR's own rendering model in `HFRParsing` (text escaped once, rewritten tag by tag into HFR's HTML string), output through the LOT-034 normalizer so the reader shows a preview exactly as it will show the posted message; the operator's choice O-1 (local preview, on-demand server preview, or both) is recorded on #189.

As a poster, I want to preview my message as HFR will render it, so that I fix formatting before sending.

## Legacy sources

None: the legacy app has no preview. Reference only, at `2440d79` of <https://github.com/ezzz/HFRnow>:

| Legacy | Role here |
|---|---|
| `HFRswift/Swift/ReplyComposer.swift:99-205` (`ReplyTextInsertionEngine`: wraps a selection in `[b]…[/b]`, splits a quote) | the tags the composer produces; the engine itself is LOT-085 / LOT-174, nothing of it renders |
| `HFRswift/Wrapped/LinkItem.m:96-141, 163-247` (rendering of posted messages) | already ported by LOT-034; the renderer reuses that port instead of a second rendering |
| ultra-hfr `HFRContent` (`BBCodeParser`, `BBCodeWriter`, MPL-2.0), redface2 `BbcodeContentParser` | ideas only (ADR 0014 option 6), no copy |

HFR facts (all in `Fixtures/captures/`): the composer toolbar help (`R40a`: `TAinsert('[b]','[/b]')` … for `b i u strike spoiler quote url img fixed email cpp` and `[*]`, the colour button inserting `'['+bgColor+']'`); the round trip of run 9 (`W61` source posted, `R95c` edit form with the source byte for byte and two "Vue Rapide" reviews, `R95d` = `POST /apercu.php`, HFR's own preview; `W62` / `R95h` for BMP emoji), [HFR-PROTOCOL §6b "BBCode round trip"](../HFR-PROTOCOL.md#6b-live-observations-from-the-capture-corpus-lot-001-2026-10-26); the quote prefills of the LOT-001 corpus (`R41a`, `R42`: message 2666649; `R42`: 2666682; `R41b`: 2666695, `[quotemsg=…]<source>[/quotemsg]`) against their rendering on the thread page `R20` (`div#para<numreponse>`); `R27b` for a multi-line code block.

## Behaviour

### API

| Type | Members | Rules |
|---|---|---|
| `BBCodeRenderer` (public) | `render(_ source: String, options: BBCodeRenderOptions = .init(), relativeTo page: URL = HFRURL.base) throws(ParsingError) -> MessageContent` | `source` is the composer text; line breaks are read as CRLF whatever it holds (`PostingBody` sends CRLF); U+FFFF dropped; `page` is the topic the message goes to (relative links resolve as on the posted message). Pure; only a backend failure throws (`malformedDocument`). `signatureHTML` is always nil |
| `BBCodeRenderOptions` (public) | `smileysEnabled: Bool = true`, `smileys: [String: URL] = [:]` | `smileysEnabled` is the composer's `smiley` checkbox read as HFR does (checked = disabled, §6b "Checkbox values"), sent to HFR's own preview as `apercu_smiley`. `smileys` maps a code (`:jap:`, `:D`, `[:user]`, `[:user:1]`) to its image URL; the app builds it from `CommonSmileyCatalog` and the member's personal smileys. Matched whatever the case: `alt` is the text as typed, `title` the table's code (`R20`: `alt=":d" title=":D"`, the member typed `:d`, shown by the `R41a` review) |
| `HFRBBCodeWriter` (internal) | `html(for source: String) -> String` | HFR's HTML string for the source, by the passes below, each one scan of the text; then `MessageContentNormalizer.normalize(contentHTML:relativeTo:)` |

### Passes of the writer (HFR's own model, ADR 0014 §1)

1. Line breaks normalized to CRLF, U+FFFF dropped, the four characters escaped as HFR does (`&amp;`, `&lt;`, `&gt;`, `&#034;`; `R95d`).
2. Raw blocks, `cpp` then `code` then `fixed` (HFR numbers the `cpp` block `code1` before the `code` block `code2`, `R95d`): each `[tag]…[/tag]` pair, non-greedy, its content taken as typed (brackets inside are text: default, pending 8), held in a placeholder.
3. Whitespace (rule below), LF → `<br />`.
4. `[url=U]text[/url]`, `[url]U[/url]`, `[img]U[/img]`: `U` without bracket or line break, not empty; held in placeholders.
5. Smileys when enabled: longest code first, any case, held in placeholders (a code inside a URL is never touched: default, pending 1).
6. `[quote]`, then `[spoiler]`: a `[/tag]` closes the innermost open `[tag]` (nested quotes written inside out: default, pending 8); an open or close without its match stays text.
7. `[#RRGGBB]…[/#RRGGBB]`, the closing tag naming the same colour, non-greedy.
8. `b`, `i`, `u`, `strike`: each in one non-greedy pass, left to right (a pair closes at the first `[/tag]` after its `[tag]`), so crossed tags come out crossed as HFR writes them and `[b][b]x[/b][/b]` gives `<strong>[b]x</strong>[/b]` (default, pending 8).
9. `[*]`: the first of a line opens `</p><ul><li>` for the rest of the line, the line's `<br />` consumed.
10. `<p>` + text + `</p>`; placeholders restored.

### Rendering table (one shape per tag; `R95d` unless noted)

The message is a sequence of paragraphs and blocks. Text and inline tags live in a `<p>`; a block tag closes the paragraph, writes its block, and opens a new paragraph (`</p>…<p>`). The thread page wraps the message in an opening `<p>` that `/apercu.php` omits (`R20` `para2666649` against the `R41a` review; the raw pages of #400). The HTML5 tree builder adds a `tbody` to every table and repairs crossed tags on both sides.

| Source | HFR writes | Note |
|---|---|---|
| `[b]x[/b]` · `[i]x[/i]` · `[u]x[/u]` · `[strike]x[/strike]` | `<strong>x</strong>` · `<em>x</em>` · `<span class="u">x</span>` · `<strike>x</strike>` | |
| `[b][i]x[/i][/b]` | `<strong><em>x</em></strong>` | nesting |
| `[u][b]x[/u][/b]` | `<span class="u"><strong>x</span></strong>` | **crossed as typed** (`R41a` → `R20`, 16 times in message 2666649); the tree builder repairs it alike on both sides |
| `[#0055aa] x[/#0055aa]` | `<span style="color:#0055aa"> x</span>` | the toolbar's colour syntax (`R40a`, `R41a` → `R20`); `[color=#FF0000]x[/color]` stays text (`R95d`) |
| `[spoiler]x[/spoiler]` | `</p><div class="container"><table class="spoiler"><tr class="none"><td><b class="s1Topic">Spoiler :</b><br /><br /><div class="Topic masque"><p>x</p></div></td></tr></table></div><p>` | HFR's `onclick` and `style="cursor:pointer;"` are dropped by the normalizer and not written |
| `[quote]x[/quote]` | `</p><div class="container"><table class="quote"><tr class="none"><td><b class="s1">Citation :</b><br /><br /><p>x<br /></p></td></tr></table></div><p>` | a trailing `<br />` inside the body (none in a spoiler) |
| `[url]U[/url]` | `<a href="U" class="cLink">U</a>` | `target="_blank"` and `rel="nofollow"` (external links, `R20`) dropped by the normalizer; the text trimmed of its spaces; `http://` added when `U` has no `://` (`[url]G3Ferrari / Optima [/url]` → `href="http://G3Ferrari / Optima "`, `R41a` → `R20`); then `normalizedURL` decides (http(s) only, else the link is unwrapped to its text) |
| `[url=U]x[/url]` | `<a href="U" class="cLink">x</a>` | `x` formatted, trimmed of its leading and trailing spaces (`[url=…] Solea[/url]` → `>Solea</a>`, `napoletana [/url]` → `napoletana</a>`, `R41a` → `R20`) |
| `[img]U[/img]` | `<img src="U" alt="U" title="U" />` | HFR adds `onload="md_verif_size(…)"` and `style="margin: 5px"`, dropped; the normalizer classifies it (`images`, or `smileys` for a `forum-images.hardware.fr` smiley path) |
| `:ange:` · `:d` · `[:user]` (code of the table) | `<img src="https://forum-images.hardware.fr/icones/smilies/ange.gif" alt=":ange:" title=":ange:" />` · `<img src="…/icones/biggrin.gif" alt=":d" title=":D" />` · `<img src="…/images/perso/user.gif" alt="[:user]" title="[:user]" />` | `R41a`/`R42`/`R41b` → `R20`; the normalizer makes them `smileys` (`.standard`, `.custom` with `class="smileycustom"`) |
| `[fixed]x[/fixed]` | `</p><table class="fixed"><tr class="none"><td><p>x</p></td></tr></table><p>` | no `container`; raw `<`, `>`, `&`, `"` in `x` are text; lines separated by `<br />` (default, pending 7) |
| `[code]x[/code]` | `</p><table class="code"><tr class="none"><td><b class="s1">Code :</b><br /><ol class="olcode"><li>line</li>…</ol></td></tr></table><p>` | one `li` per line, the CRLF removed, an empty line `<li></li>` (`R27b`); HFR's `id="codeN"` and the header's `font-family` dropped |
| `[cpp]x[/cpp]` | same as `code` | **without** HFR's syntax colours (pending 5) |
| `[*]x` | `</p><ul><li>x</li></ul><p>` | the first `[*]` of a line opens the bullet, which holds the rest of the line (a second `[*]` on it is text); the line's own break is consumed (`[list]</p><ul><li>item one[*]item two[/list]</li></ul><p>`; the `R95c` review keeps a `\r` inside the `li`, `/apercu.php` does not) |
| `[color=#FF0000]x[/color]`, `[list]`, `[/list]`, `[b]` never closed, `[/b]` never opened, `[email]`, `[B]`, any other `[…]` | the text itself | `R95d` for the first five; the rule extends to every bracket the table does not match |
| `a\r\nb` | `a\r<br />b` | the CR kept as text, the LF written `<br />` |
| `<b> & "` in text | `&lt;b&gt; &amp; &#034;` | serialized back by SwiftSoup as `&lt;b&gt; &amp; "` on both sides |
| BMP emoji, U+FE0F | the characters, as text | `R95h`; characters above U+FFFF are text too (LOT-048 refuses them before sending) |

### Whitespace rule (one rule; `R20` `para2666649` against the `R41a` prefill, `R27b`, `R95d`)

In a run of spaces and CRs: the first character becomes U+00A0 when the run starts a line (right after a LF; in `code`, every run of two or more); then the run is read two by two, the first of a pair kept (a space as itself, a CR as the `\r` HFR leaves in the text), the second U+00A0; a last one alone kept. A LF becomes `<br />`.

| Source | HFR writes | Where |
|---|---|---|
| `[/url]  :ange:` | ` &nbsp;<img…` | `R20` byte 37735 |
| `)  \r\n\r\n* on` | ` &nbsp;\r<br />&nbsp;<br />* on` | `R20` (message 2666649) |
| `(pro)   5.75` | `(pro) &nbsp; 5.75` | `R20` |
| `:ange: \r\n\r\n\r\n [#0055aa]` | ` &nbsp;<br />&nbsp;<br />&nbsp;<br />&nbsp;<span…` | `R20` byte 37735 |
| `Bonjour,\r\n\r\nPour` | `Bonjour,\r<br />&nbsp;<br />Pour` | `R27b` `para2542632` |
| nine leading spaces after a line break | `&nbsp; &nbsp; &nbsp; &nbsp; &nbsp;` | `R20` |
| `[fixed]fixed   text  <tag>[/fixed]` | `fixed &nbsp; text &nbsp;&lt;tag&gt;` | `R95d` |
| `[code]code   text[/code]` · four leading spaces in a code line · `int x = 1;` | `code&nbsp; &nbsp;text` · `&nbsp; &nbsp; ` · `int x = 1;` | `R95d`, `R27b` |

### Differential tests (ADR 0004)

`BBCodeRendererOracleTests`, one test per pair; every reduction is counted (LESSONS 51):

| Pair | Source | Oracle | Reductions |
|---|---|---|---|
| `W61` → `R95d` | `content_form` of `W61.meta.json`, form-decoded; equal to `apercu_contenu` of `R95d.meta.json` (asserted) | inner HTML of `body.reponse`, the template's leading line break removed, prefixed with `<p>`, normalized | `\r` removed on both sides; the one `[cpp]` colour span unwrapped from the oracle (counted: 1) |
| `W62` → `R95h` | same, `W62` / `R95h` | same | `\r` |
| `R41a` → `R20` 2666649 | the `[quotemsg=2666649,…]` prefill without its wrapper | `MessageBlockParser` block 2666649 of `R20`, normalized | `\r`; the 11 `[url]` of the prefill that the thread shows as images given back to `[img]` (the prefill rewrites images); the one `[/b]` HFR did not render (37 `<strong>` for 36 `</strong>` on the thread, cause unknown, pending 8) given back to the thread as `</strong>` |
| `R42` → `R20` 2666682 | the `[quotemsg=2666682,…]` prefill | block 2666682 | `\r`; 1 image given back; the anonymizer's per-fixture folder name mapped (`user38` → `user37`) |
| `R41b` → `R20` 2666695 | the `[quotemsg=2666695,…]` prefill (HFR drops the citation the message starts with) | the message's own paragraph after its `table.citation`, before the clear trailer | `\r`; per-fixture pseudonym mapped (`user5` → `user6`) |

Each test fails without the renderer (the source as text gives another `html`) and asserts the pair's own facts (`W61`: 2 links, 1 smiley-path image, spoiler and code blocks; 2666649: 11 images, over 10 links, `:ange:`, the crossed colour heading; 2666682: `alt=":d" title=":D"`; 2666695: a `.custom` smiley) so an equality on an empty page is noticed.

`BBCodeRendererSanitizationTests` (inline sources): every rejected scheme in `[url=…]` and `[url]` (text, no link), in `[img]` (removed); a line break inside a tag's brackets; raw HTML and `on*` text; quotes in a URL (one `href` attribute, percent-encoded); the normalizer's URL rules through the renderer; a smiley-path `[img]`; 10 000 nested `[b]`, 1 000 nested `[quote]` and 10 000 unclosed tags on a cooperative-pool thread in bounded time. `HFRBBCodeWriterTests`: every row of the two tables on inline sources, 21 text-fallback cases, smiley case and order, escaping.

## Edge cases

- **Crossed tags** come out crossed and are repaired by the tree builder as on the thread page; the repair reopens the outer formatting element around what follows (`R20`: `<strong>` reconstructed around the next lines after `[u][b]x[/u][/b]`), which the renderer reproduces because it writes the same string, `\r` included.
- **Line break after a block**: `<p>\r<br />…` at the start of the next paragraph; before a block, `…\r<br /></p><div`. Two blocks separated by one line break give a paragraph holding `\r<br />`, kept by the normalizer; two adjacent blocks give an empty `<p>`, dropped on both sides.
- **Bullet line**: the line's `<br />` is consumed by the `</li></ul>`; the `\r` stays inside the `li` (as the `R95c` review) and is removed by the tests.
- **URL schemes**: the renderer never decides; `normalizedURL` does (http(s), absolute against `page`, `hardware.fr` upgraded to https, `hfr-rehost.net` → `reho.st`); `http://` is added first to a URL without `://`, as HFR does (`G3Ferrari`). A protocol-relative `//host` therefore becomes `http:////host` and is unwrapped: HFR's own answer is pending 6.
- **Message cut by HFR**: a character above U+FFFF is rendered as text; LOT-048 refuses the send, so no preview of a text HFR would truncate (`W12`) is ever sent.
- **Depth and size**: every pass is one scan; checked at 10 000 nested and unclosed tags (robustness bound, not an observed HFR limit).
- **Defaults for uncaptured cases** (each named in Pending capture): `[b]` across a line break is a pair (`<strong>a\r<br />b</strong>`); `[b][quote]x[/quote][/b]` gives a block inside `<strong>…</strong>`, crossed, repaired by the tree builder; `[url=…]` around `[b]` formats the text; `[b]` inside `[code]` is text; `[quote]` in `[quote]` nests; `[quote]` never closed is text; `[b][/b]` is `<strong></strong>`; a `[*]` inside `[b]…[/b]` opens a bullet in the middle of the pair (crossed, repaired).

## Pending capture

Opened as one `host: mac` capture issue, [#443](https://github.com/ezzz/HFRnow/issues/443) (batch 2; every item readable through `POST /apercu.php`, which renders without posting, `R95d`; item 10 posts once). Every row is a fidelity gap of the preview until its pair exists; the default the renderer applies meanwhile is in the table or in Edge cases.

1. **Smileys**: the set of codes HFR knows against `CommonSmileyCatalog`; a code glued to a word; codes inside `[code]`, `[fixed]`, `[url]`, `[img]`; `apercu_smiley=1`; whether `/apercu.php` substitutes smileys as the thread does (the reviews do not: `R41a` leaves `:ange:` as text).
2. **Colour**: a named colour the palette offers, `[color=red]`, a 3-digit hex.
3. **Email**: `[email]a@b.c[/email]` and an address in plain text.
4. **Bullets**: `[*]` on three consecutive lines, with and without `[list]…[/list]`, a `[*]` mid-line, an empty `[*]`.
5. **Syntax colours**: `[cpp]` with several keywords, strings, comments, several lines (`R27b` shows `#include` and `int` in `span[style=color:blue]`, comments in `span[style=color:green] > i` holding the line's `\r`, in a `table.code` whose tag is unknown); whether `[code]` colours too; `[c]`, `[java]`, `[php]`, `[html]`.
6. **URLs**: `[url]` and `[img]` with `http://`, `ftp://`, `javascript:`, `//host`, a non-image target, `&` and `"` in the URL; a bare `https://…` in text (auto-link or not).
7. **Whitespace**: tabs; a space run of one at a line start in `code`; line breaks inside `[fixed]`; trailing line breaks; leading spaces before a tag.
8. **Nesting and malformed**: `[b]` across a line break, `[b][quote]x[/quote][/b]`, `[quote][b]x[/quote][/b]`, `[b]` inside `[url=]`, `[quote]` in `[quote]`, `[quote]` never closed, `[/quote]` alone, `[b][/b]`, `[b][b]x[/b][/b]`, `[b]` inside `[code]`, `[quotemsg=1,1,1]x[/quotemsg]`; and the `[/b]` of message 2666649 that the thread page does not render (`R41a` line `[u][b]Méthode traditionnelle à température ambiante [/u][/b]`, `R20` `…ambiante </span>\r<br />`): post that line again and read its preview.
9. **Limits**: the longest message HFR accepts, the deepest nesting it renders (also #268).
10. **Thread vs preview**: one public post holding items 1, 4 and 7 with its `/apercu.php` answer, both published, so the "whitespace aside, opening `<p>`" identity measured on the private raw pages of #400 is asserted by a test (gating for any "exact" label, ADR 0014 O-1).

## Intentional differences from HFR

1. **Attributes outside the ADR 0006 contract are not written** (`onclick`, `style="cursor:pointer;"`, `onload`, `style="margin: 5px"`, `target="_blank"`, `rel="nofollow"`, `id="codeN"`, the header's `font-family`): the normalizer drops them from posted messages, so the preview equals the posted message, not HFR's bytes.
2. **Non-http(s) URLs** are text (links) or removed (images), whatever HFR renders: the preview is sanitized by the same rules as every message.
3. **`[cpp]` has no syntax colours** until pending 5.
4. **`tbody`** is not written: the tree builder adds it on both sides.

## Fixtures

`W61.meta.json`, `R95c-mp-edit-form-bbcode-source.html`, `R95d-apercu-bbcode-preview.html`, `R95d.meta.json`, `W62.meta.json`, `R95h-apercu-bmp-emoji-preview.html`, `R95h.meta.json` (#400, run 9); `R41a-quote-form.html`, `R41b-quote-form-of-quoting-post.html`, `R42-multiquote-form-cookie.html`, `R20-topic-p1-anon.html`, `R27b-…` (LOT-001 corpus); `R40a` (toolbar help). No legacy oracle exists for a preview (legacy has none): the oracle is HFR's own rendering through LOT-034 (ADR 0014 §2).

## Learnings

To copy into AGENTS.md §11 when the lot closes:

- HFR renders BBCode by rewriting the text tag by tag, not by matching a tree: crossed tags come out crossed (`<span class="u"><strong>x</span></strong>`) and the browser repairs them. A renderer that wants the same display writes the same string and lets the same tree builder repair it; a DOM-building renderer diverges on every crossed case.
- The quote prefill (`[quotemsg=…]`) is a source → rendering pair for every message of the corpus whose quote form was captured, so BBCode facts can be read from `R41a`/`R41b`/`R42` against `R20` without a new capture; it rewrites `[img]` as `[url]` and drops the citation the message starts with.
- HFR has several renderings of one source: the message (= `/apercu.php` modulo whitespace and the opening `<p>`) and the "Vue Rapide" reviews (`[img]` as a link, no smiley). A rendering fact names which one it comes from.
- The composer's colour button inserts `[<colour>]…[/<colour>]`, not `[color=…]`: read the toolbar's `TAinsert` calls before writing a capture checklist of tags.
- Swift reads `\r\n` as one `Character`: a `replacing("\n", …)` on a `String` never matches inside a CRLF; work on `unicodeScalars` when CR and LF must be told apart.
