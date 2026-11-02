import Foundation

/// Writes a message source as the HTML string HFR itself renders for it (ADR 0014 §1), by the same model as HFR's
/// renderer: the text is rewritten tag by tag with non-greedy replacements, so crossed tags come out crossed
/// (`[u][b]x[/u][/b]` → `<span class="u"><strong>x</span></strong>`, `R41a` → `R20`) and are repaired by the HTML5 tree
/// builder exactly as a posted message is, once `BBCodeRenderer` parses the string in the thread page's context.
///
/// Every rule is the narrowest one that reproduces a captured pair (LOT-097 spec "Rendering table"); whatever no pair
/// proves is left as text, as HFR does with `[color=…]`, `[list]` and an unclosed tag (`R95d`). Only the parts of
/// HFR's markup that survive the normalizer are written (no `onclick`, `style`, `id`, `onload`, `target`, `rel`).
///
/// Member text never becomes markup: every text run is escaped by one function (`escape`) before the HTML tags are
/// written around it, and the fragments that later passes must not touch (URLs, images, smileys, raw blocks) are held
/// in placeholders built from U+FFFF; a line break is held as U+FFFE and a no-break space as U+E000 until the end, all
/// three stripped from the source first. Every pass works on **Unicode scalars**, never on `Character`s: a combining
/// mark after a `"` or a `]` must not hide it from the escaping or the tag syntax. Every pass is one scan of the text
/// (the next closing tag is searched once and remembered), so the work is linear in the source length.
struct HFRBBCodeWriter {
    typealias Scalars = [Unicode.Scalar]

    var smileysEnabled: Bool
    var smileys: [String: URL]

    /// HFR-shaped body HTML for `source`, to be parsed in the thread page's context (`BBCodeRenderer`).
    func html(for source: String) -> String {
        var placeholders: [Scalars] = []
        func hold(_ fragment: Scalars) -> Scalars {
            placeholders.append(fragment)
            return Self.placeholder(placeholders.count - 1)
        }
        var text = Self.normalizedLineBreaks(Array(source.unicodeScalars))
        // 1. Raw blocks, `cpp` before `code` (HFR numbers the `cpp` block first, `R95d` ids), then `fixed`.
        for tag in ["cpp", "code", "fixed"] {
            text = Self.replacingPairs(tag, in: text) { hold(Self.rawBlock(tag, content: $0)) }
        }
        // 2. Whitespace, on the text as typed (`R20`, `R27b`, `R95d`); a line break becomes U+FFFE for now.
        text = Self.spacedText(text, lineBreak: [Self.lineBreakMarker])
        // 3. Links and images: their URL and text are final, no later pass may rewrite them.
        text = Self.holdingLinksAndImages(in: text, hold: hold)
        // 4. Smileys on the text as typed, longest code first, any case: `alt` as typed, `title` the catalogue's code.
        if smileysEnabled {
            text = holdingSmileys(in: text, hold: hold)
        }
        // 5. The text is escaped once; placeholders and markers hold no escapable character.
        text = Self.escape(text)
        // 6. Blocks, innermost first; 7. colour; 8. inline tags, each in one non-greedy pass (crossed tags stay crossed).
        text = Self.replacingNested("quote", in: text,
            open: "</p><div class=\"container\"><table class=\"quote\"><tr class=\"none\"><td><b class=\"s1\">Citation :</b>"
                + "<br /><br /><p>",
            close: "<br /></p></td></tr></table></div><p>")
        text = Self.replacingNested("spoiler", in: text,
            open: "</p><div class=\"container\"><table class=\"spoiler\"><tr class=\"none\"><td><b class=\"s1Topic\">Spoiler :</b>"
                + "<br /><br /><div class=\"Topic masque\"><p>",
            close: "</p></div></td></tr></table></div><p>")
        text = Self.replacingColours(in: text)
        for (tag, open, close) in Self.inlineTags {
            text = Self.replacingPairs(tag, in: text) { Self.scalars(open) + $0 + Self.scalars(close) }
        }
        // 9. Bullets: the first `[*]` of a line opens `ul > li` for the rest of the line, whose break is consumed (`R95d`).
        text = Self.replacingBullets(in: text)
        // The thread page opens the message's `<p>` and never closes it: the clear trailer that follows does (`R20`).
        text = Self.scalars("<p>") + text
        // 10. Markers and placeholders back (a held fragment never holds another: a URL holding one is text).
        text = Self.replacingMarkers(in: text)
        return Self.string(Self.restoringPlaceholders(in: text, placeholders))
    }

    /// `[url=U]text[/url]` → `a.cLink` around the formatted text; `[url]U[/url]` → `a.cLink` with `U` as text;
    /// `[img]U[/img]` → `img` with `U` as `src`, `alt` and `title` (`R95d`); each held in a placeholder.
    private static func holdingLinksAndImages(in text: Scalars, hold: (Scalars) -> Scalars) -> Scalars {
        var text = replacingNamedURLs(in: text) { url, content in
            hold(scalars("<a href=\"") + escape(schemed(url)) + scalars("\" class=\"cLink\">"))
                + trimmedLinkText(content) + hold(scalars("</a>"))
        }
        text = replacingPairs("url", in: text, argumentIsURL: true) {
            hold(scalars("<a href=\"") + escape(schemed($0)) + scalars("\" class=\"cLink\">") + escape(trimmedLinkText($0))
                + scalars("</a>"))
        }
        return replacingPairs("img", in: text, argumentIsURL: true) {
            let url = escape($0)
            return hold(scalars("<img src=\"") + url + scalars("\" alt=\"") + url + scalars("\" title=\"") + url + scalars("\" />"))
        }
    }

    /// Every smiley code of the table, longest first, as `img` with `alt` as typed and `title` the table's code (`R20`).
    private func holdingSmileys(in text: Scalars, hold: (Scalars) -> Scalars) -> Scalars {
        var text = text
        for (code, url) in smileys.sorted(by: { ($1.key.count, $0.key) < ($0.key.count, $1.key) }) {
            let source = Self.escape(Self.scalars(url.absoluteString)), title = Self.escape(Self.scalars(code))
            text = Self.replacingSmiley(Self.scalars(code), in: text) {
                hold(Self.scalars("<img src=\"") + source + Self.scalars("\" alt=\"") + Self.escape($0) + Self.scalars("\" title=\"")
                    + title + Self.scalars("\" />"))
            }
        }
        return text
    }
}
