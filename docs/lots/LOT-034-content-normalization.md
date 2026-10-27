# LOT-034 — Content normalization (smileys, images, links, signature, code, spoilers)

- **Module:** HFRParsing
- **Difficulty / model:** difficult (Fable → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`; old issue francoisgn/ios-app_SwiftHFR#67; audit item C08 in [C](../audit/C-message-parsing.md) §4, §7.2; [ADR 0006](../adr/0006-content-normalization-in-parsing.md) with amendment 1)

Chain: LOT-003 (oracle) → LOT-030 (blocks) → **LOT-034** → LOT-035 (embeds), LOT-083 (the app's message HTML builder).
Siblings on the same tree, untouched here: LOT-031 (action links, outside the content element), LOT-032 (quote analysis).

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79` (the code the LOT-003 oracle ran).

| Legacy | Replaced by |
|---|---|
| `HFRswift/Wrapped/LinkItem.m:72` (trim of `dicoHTML`) | tree built from the content element; leading and trailing whitespace is a DOM text node, kept |
| `:74` (delete the literal `---------------`) | **not ported** (no capture shows it; see Intentional differences 8) |
| `:96-134` (personal smileys `images/perso/<file>` with `alt="[:<code>]"` → `img.smileycustom` + `onClick` custom scheme) | `MessageSmiley(kind: .custom)` in `smileys`, `<img class="smileycustom" src alt title>` in the HTML |
| `:138-141, 228-231` (standard smileys `http://forum-images.hardware.fr/…/<file>` → bundled file) | `MessageSmiley(kind: .standard)` in `smileys`, the `<img src alt title>` kept (the app decides whether to use a bundled copy, `CommonSmileyCatalog`) |
| `:163` (`hfr-rehost.net` → `reho.st`, a global string replace) | host rewrite of every `href` and `src` whose host is `hfr-rehost.net` or ends with `.hfr-rehost.net` (**pending capture**) |
| `:167, 268-269` (`href="/forum2.php…` and `<a href="/hfr/…` made absolute) | every `href` and `src` resolved against the forum base (`HFRURL.absolute`), http(s) only, `http` upgraded to `https` on `*.hardware.fr` hosts (ADR 0006 amendment 1) |
| `:169-226` (images: `display_images` modes; `yes` wraps bare images in a link to themselves and adds `class="hfrplusimg"`, `title=<index>`, `longdesc`, `onClick`) | `MessageImage` in `images` (`url`, `linkURL` of a wrapping link, `altText`, `isInSignature`), `<img class="hfrplusimg" src alt title>` kept bare or inside its own link; display modes are the app's (ADR 0006) |
| `:233-247` (signature: cut the string at `<span class="signature">` unless `display_sig == yes`) | `span.signature` split out: its inner HTML becomes `signatureHTML`, the rest is `html`, both always produced; `isInSignature` on images and links |
| `:265` (`<span style="color:blue">` → `color:var( --color-action)`) | **not ported**: `style="color:blue"` kept; a theme concern of the app's stylesheet (LOT-083) |
| `:271-279` (template, `\n` removed from the whole message) | newlines kept (Intentional differences 6) |
| `ParseMessagesOperation.m:191-194` (`oldcitation` → `citation`) | **not ported**: both class names are kept and are part of the contract (ADR 0006); LOT-032 reads the quotes |
| `:238-317` (video links marked `embedvideo`) | LOT-035; `embeds` stays empty here |
| `ObjCTopicHTMLRenderer.m:40` (`swap_spoiler_states`), `style-liste-light.css:130` (`div.masque { visibility: hidden }`) | spoiler markup kept (`table.spoiler`, `div.Topic.masque`), its `onclick` and `style` dropped: the toggle belongs to the app (LOT-083) |
| `ObjCTopicHTMLRenderer.m:10,32` (`nosig` class), `style-liste-light.css:99` (`.nosig span.signature, div.edited { display: none }`) | `div.edited` removed from the content (its facts are `MessageBlock.editNote`, `quotedByCount`, `quotedByURL`, LOT-030) |

Not ported here, by design (audit C 7.1, ADR 0006): blacklist and whitelist quote classes and their show/hide UI (`LinkItem.m:76-94`, app-side C10),
the `quotedhfrlink`, `editedhfrlink` and `filteredpostlink` trailers (`:249-262`, app builder C12 from `MessageBlock`), the custom URL schemes
and `onClick` handlers (`oijlkajsdoihjlkjasdo…`, C §5.3), avatar and template placeholders, the `iosversion` and `%%ID%%` replacements (C quirk 2).

## Behaviour

### API

| Type | Members | Rules |
|---|---|---|
| `MessageContentNormalizer` (public) | `normalize(contentHTML: String, relativeTo: URL = HFRURL.base) throws(ParsingError) -> MessageContent` | `contentHTML` is `MessageBlock.contentHTML` (the inner HTML of `div#para<numreponse>`); the page URL resolves fragment-only links. Only a backend failure throws (`malformedDocument`) |
| `MessageContentNormalizer` (internal) | `normalize(_ content: Element, relativeTo: URL) -> MessageContent` | Same from the `ExtractedMessageBlock.content` element, for the `TopicPage` orchestration; the source tree is read, never mutated |

The output `MessageContent` (LOT-011) is **rendered from a new tree**, never copied from the page: every node of the source is either
copied into an allow-listed element with allow-listed attributes, unwrapped (its children kept), or dropped. SwiftSoup serializes the new tree
(`prettyPrint` off, base escape mode), so every text and attribute value is escaped by the serializer (Bybifok's "everything escaped",
[research §3](../research/bybifok-proposals.md), within ADR 0006 option 1).

### Sanitization (the contract of ADR 0006)

| Rule | Detail |
|---|---|
| Elements kept | `p br b strong i em u s strike span a img table tbody tr td th div ol ul li blockquote pre code hr sub sup` |
| Elements dropped with their content | `script style iframe object embed applet template noscript svg math form input button select textarea link meta base frame frameset video audio source track canvas head title` |
| Other elements | unwrapped: the element disappears, its children are processed in place (`font`, `center`, `h3`…) |
| Other nodes | comments, data and declarations are dropped; text nodes are copied |
| Attributes kept | `a`: `href`, `title`, `class` · `img`: `src`, `alt`, `title`, `class` · `span`: `class`, `style` · every other kept element: `class`. Everything else is dropped, in particular every `on*` handler, `id`, `name`, `style` elsewhere, `target`, `rel`, `onload`, `longdesc`, sizes |
| `class` | tokens filtered through the allow-list `cLink Topic citation oldcitation quote spoiler code fixed container masque s1 s1Topic signature u olcode none hfrplusimg smileycustom`; no attribute when no token survives |
| `style` on `span` | kept only as `color:<value>` with `<value>` a `#` followed by 3 or 6 hex digits, or 1 to 20 ASCII letters (user colours and the `olcode` syntax colours); anything else (`url(`, `expression(`, `position`, several declarations) is dropped |
| `href` | `HFRURL.absolute(raw, relativeTo: page)` plus the rules below; nil (empty, `javascript:`, `data:`, `file:`, `blob:`, `vbscript:`, user info…) → the link is **unwrapped**: its text stays, the `<a>` goes |
| `src` | same resolution; nil → the image is **removed** (ADR 0006 amendment 1) |
| URL rules | after `HFRURL.absolute`: `http` → `https` when the host is `hardware.fr` or ends with `.hardware.fr` (`forum-images.hardware.fr` serves every smiley over https in the corpus); host `hfr-rehost.net` → `reho.st` and `<x>.hfr-rehost.net` → `<x>.reho.st` (legacy `:163`) |

### Structure rewrites, in document order

1. `div.edited` (the LOT-030 trailer HFR nests inside the content element) is dropped.
2. The **first** `span.signature` is cut out: its inner content, normalized, is `signatureHTML` (nil when the message has none; `""` never);
   later `span.signature` elements are dropped (legacy cut everything after the first). Images and links inside it carry `isInSignature`.
3. `div` with no class whose `style` is exactly `clear: both;` (HFR's layout trailer) and no element child is dropped.
4. `<p>` without any child node is dropped (HFR's `<p></p>` before a quote block, and the empty paragraph the HTML5 tree builder makes of
   the stray `</p>` that follows the clear trailer, LOT-030 difference 5).
5. Smileys: an `img` whose URL host is `forum-images.hardware.fr` and path starts with `/icones/` (standard) or `/images/perso/` (personal) is
   a `MessageSmiley`: `code` is the `alt` attribute as served (`:ange:`, `[:user13]`, the form of `ForumSmiley.code` and `CommonSmiley.code`),
   `kind` `.standard` or `.custom`. The HTML keeps `<img src alt title>`, with `class="smileycustom"` on personal ones (legacy CSS hook).
6. Images: every other `img` is a `MessageImage`; its HTML gets `class="hfrplusimg"`. When the image is the only element content of an
   `<a>` whose link survives (whitespace allowed), that link is the image's `linkURL` and is **not** a `MessageLink`.
7. Links: every other surviving `<a>` is a `MessageLink` (`url`, `text` = its normalized text, `isInSignature`), quote headers `a.Topic` included.
8. Spoilers and code: `table.spoiler` (with `div.Topic.masque`), `table.code`, `table.fixed`, `ol.olcode`, `li`, `span[style=color]`
   keep their structure and classes; the spoiler's `onclick`/`style` and the code header's `font-family` go with the attribute rules.
9. Quotes: `table.citation`, `table.oldcitation`, `table.quote`, `div.container`, `tr.none`, `b.s1`, `a.Topic` are kept as served.
10. `embeds` is always empty (LOT-035).

### What the following lots build on

- **LOT-035**: `links` (not in the signature) are the candidates; `embeds` is filled from them.
- **LOT-032**: works on `ExtractedMessageBlock.content`, the untouched source tree.
- **LOT-083** (app builder): `html` + `signatureHTML` go into the template; display modes are applied from the lists (image mode from
  `images`, signature visibility by choosing to append `signatureHTML`, bundled smileys from `smileys`); it must provide the spoiler toggle
  (click on `table.spoiler` toggles `div.masque`, CSS `div.masque { visibility: hidden }`), the `blue` → action colour tweak for `olcode`,
  tap handling on `img.hfrplusimg` and `img.smileycustom`, and the `quotedhfrlink`/`editedhfrlink` trailers from `MessageBlock`.

## Edge cases

Checked on the 20 LOT-003 captures (358 messages; facts in HFR-PROTOCOL §6c "LOT-034"):

- Signature present on 125 messages (`span.signature` after the clear trailer, preceded by a `<br />` that stays in `html` as legacy kept it).
- Personal smileys (`images/perso/<alias>.gif`, `alt="[:<alias>]"`) and standard ones (`icones/smilies/<name>.gif` or `icones/<name>.gif`,
  `alt=":<name>:"` or `:o`, `:d`); `title` may differ from `alt` in case (`alt=":d" title=":D"`, R20).
- Images: bare `<img src alt title onload="md_verif_size(…)" style="margin: 5px">` (R20, R28) or inside `<a rel="nofollow" href target="_blank"
  class="cLink">`; `alt` and `title` repeat the URL; `style` may add `width`/`height` (R28). `http` image hosts stay `http` (not `hardware.fr`).
- Links: external `a.cLink` with `rel="nofollow" target="_blank"`; `http://forum.hardware.fr/hfr/…` links (upgraded to `https`); quote headers
  `a.Topic` with a relative `/hfr/…#t<n>` path; an `href` with raw spaces in its host (`http://G3Ferrari / Optima`, R20 message 0) is not a
  URL: the link is unwrapped to its text where legacy kept a broken link (libxml2 percent-encoded the spaces).
- Spoilers (`R27`, `R28`): `<table class="spoiler" onclick="javascript:swap_spoiler_states(this)" style="cursor:pointer;">` →
  `<b class="s1Topic">Spoiler :</b>` and `<div class="Topic masque">`.
- Code (`R27b`): `table.code` / `table.fixed`, `<b class="s1" style="font-family: …">Code :</b>`, `<ol id="code1" class="olcode">` with one
  `<li>` per line, `<span style="color:blue|green">`, `<i>` comments holding a newline, `&#034;` and `&lt;` entities.
- Quotes (`R20`, `R26`, `R27`): `div.container` → `table.citation` → `tr.none` → `td` → `b.s1 > a.Topic` then `<p>`; `table.quote` for
  anonymous citations (`<b class="s1">Citation :</b>`); nested quotes.
- Formatting: `strong`, `em`, `i`, `strike`, `span.u`, `span[style=color:#0055aa]`, `ul`/`li`; `&nbsp;` lines.
- Error paths (inline snippets, no page state): every rejected scheme (`javascript:`, `JaVaScRiPt:`, `java\nscript:`, `&#106;avascript:`,
  `data:`, `file:`, `blob:`, `vbscript:`), a protocol-relative `//host` (resolved to `https`), user info, `on*` attributes, `<script>`,
  `<iframe>`, `style` injections, `id`s, unknown classes, unknown elements, a comment, nested and repeated signatures, an image without `src`.

**Pending capture** (ported from legacy code, no positive fixture; the corpus is checked negative):

- `hfr-rehost.net` links and images (legacy `:163`); no capture holds the host (`reho.st` neither).
- The `---------------` separator (legacy `:74`): not in any capture, not ported (Intentional differences 8).
- Oracle settings: the LOT-003 oracle runs one combination only (`display_images=yes`, `display_sig=no`, `embedded_videos=yes`). Untested
  against legacy output: signatures shown (`display_sig=yes`: legacy keeps `<span class="signature">` inline, our `signatureHTML` is its inner
  HTML), images off (`display_images=no`: legacy swaps the image for the theme's `landscape` placeholder and moves the URL to `longdesc`,
  an app decision from `images`), videos off (LOT-035).

## Fixtures

Captures (`Fixtures/captures/`, LOT-001) and the LOT-003 oracles, through `oracle-map.json` (same 20 cases as LOT-030):

| Case | Covers here |
|---|---|
| R20, R21 | signatures, personal and standard smileys, external links, bare images, quotes, `table.quote`, spaces in an `href` |
| R26 | many personal smileys, nested quotes, signatures |
| R27 | spoilers, quotes, YouTube links (plain links here) |
| R27b | code blocks (`table.code`, `olcode`, colours, entities) |
| R28 | 42 images, bare and linked, spoiler, `http` image hosts |
| R22a, R22b, R23, R24, R31, R32a, R32b | ordinary content, continuation block, locked and poll topics |
| RA1–RA5, RU1, RU2 | private threads: short posts, smileys, quotes; `RA5` has no message |

### Oracle coverage (ADR 0004)

`MessageContentOracleTests` compares, for every message of the 20 oracles, our output with the legacy `toHTML:isMP:` result
(`result.messages[].html`, computed with `display_sig=no`, `display_images=yes`), reduced to its `div#para…` element minus `div.edited`:

| Oracle | Compared with | Note |
|---|---|---|
| `div.embedvideo` count | the `a.cLink` links of `html` two levels under the root, text-only, matching the four legacy video regexes (`ParseMessagesOperation.m:241-244, 260-264`) | the oracle ran with `embedded_videos=yes`: legacy replaced those links by an iframe, text included (LOT-035). They are set aside from the text and link comparisons below, and their number must equal the oracle's iframes (LESSONS 50) |
| visible text | text of `html`, embedded links removed | whitespace removed on both sides: legacy deleted every `\n` (quirk 2) and libxml2 wrote U+00A0 raw |
| `img.smileycustom` (`src`, code in the `onClick` scheme) | `smileys` of kind `.custom` (`url`, `code == "[:<code>]"`) | legacy dropped `alt`/`title` and escaped `'` in the code |
| `img.hfrplusimg` (`src`, `longdesc`) | `images` (`url`, `linkURL`) | `longdesc` is the wrapping link's URL, empty for a bare image that legacy wrapped in a link to itself |
| every other `img` (`src`, `alt`) | `smileys` of kind `.standard` | https standard smileys are not rewritten by legacy (LOT-003 Q23) |
| `a` elements other than the ones around `hfrplusimg` images (`href`, text) | `links`, embedded links removed | through `HFRURL.absolute` and the same host rules on both sides (legacy made only `/forum2.php` and `/hfr/` absolute and kept `http://forum.hardware.fr`); a legacy link whose `href` is not a URL (the `G3Ferrari` one) is left out, the text comparison shows its text survived |
| signature cut | `signatureHTML != nil` ⇔ the capture block holds `span.signature`; the text comparison proves the cut point | the oracle holds no signature text |
| totals | 125 signatures, 103 messages with personal smileys, 36 with images (LOT-003 RC3.9) | guards against a vacuous comparison |

Plus, on every message: no `on*` attribute, `id`, `script` or `javascript:` in `html` and `signatureHTML`; `embeds` empty.

## Intentional differences from legacy

1. **A new tree instead of regex over a serialization** (C quirk 1): legacy rewrote libxml2's output with regexes that depend on attribute order
   and quoting; here the output is serialized from an allow-listed tree, so HFR markup changes degrade to dropped attributes, never to
   unsanitized output. The tests compare text and typed values, never bytes.
2. **Sanitized of record** (ADR 0006): legacy inserted the content as served (with `onclick`, `onload`, `id`s, `style`s, any scheme) into a
   `WKWebView` with file access; here every handler, `id`, unknown attribute and non-http(s) URL is dropped.
3. **Typed lists** replace the `onClick` custom schemes and the `title=<index>`/`longdesc` tricks: the app reads `images`, `smileys`, `links`.
4. **Display modes are not applied** (`display_images`, `display_sig`, `embedded_videos`): the content is the same whatever the settings;
   the signature is always split out and always available.
5. **`div.edited` and the clear trailer are removed** from the content; legacy kept them (hidden by CSS). Empty paragraphs are dropped.
6. **Whitespace kept**: legacy deleted every newline of the message (quirk 2), which glued words across a source newline (`foo\nbar`);
   HTML collapses whitespace on display anyway.
7. **Every link is absolute** and `http` forum links become `https`; legacy fixed only `/forum2.php` and `/hfr/` prefixes.
8. **`---------------` is not deleted** (legacy `:74`): the rule has no visible trigger in the corpus and would also damage code blocks and
   prose holding a line of dashes. To revisit with a capture that shows what it was for.
9. **`color:blue` is kept** on `olcode` keywords instead of `var( --color-action)`: a theme rule for the app's stylesheet, not content.
10. **`oldcitation` is not renamed**: both classes are contract (ADR 0006); the app styles both, as the legacy CSS did
    (`style-liste-light.css:353`).
11. **Fragment-only links** resolve against the page URL given by the caller (the forum root by default); legacy left them relative.

## Learnings

To copy into AGENTS.md §11 when the lot closes:

- HFR nests the `div.edited` trailer and its `<div style="clear: both;">` **inside** `div#para<numreponse>`, after the signature: content
  normalization must drop both, or the trailer text ends up in the body.
- The legacy oracle's `html` for a message is cut at the signature (`display_sig=no`): comparing its text with the normalized body proves
  the cut point exactly, without any signature fixture.
- Legacy `toHTML` deleted every `\n` of the content, so its visible text can glue words across a source newline: compare text with all
  whitespace removed, not whitespace-normalized.
