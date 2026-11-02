import Foundation

/// Writes a message source as the HTML string HFR itself renders for it (ADR 0014 §1), by the same model as HFR's
/// renderer: the text is escaped once, then rewritten tag by tag with non-greedy replacements, so crossed tags come
/// out crossed (`[u][b]x[/u][/b]` → `<span class="u"><strong>x</span></strong>`, `R41a` → `R20`) and are repaired by
/// the HTML5 tree builder exactly as a posted message is, once `MessageContentNormalizer` parses the string.
///
/// Every rule is the narrowest one that reproduces a captured pair (LOT-097 spec "Rendering table"); whatever no pair
/// proves is left as text, as HFR does with `[color=…]`, `[list]` and an unclosed tag (`R95d`). Only the parts of
/// HFR's markup that survive the normalizer are written (no `onclick`, `style`, `id`, `onload`, `target`, `rel`).
///
/// Member text never becomes markup: the whole source is escaped before any tag is looked at, and the fragments that
/// later passes must not touch (URLs, images, smileys, raw blocks) are held in placeholders built from U+FFFF, a
/// noncharacter stripped from the source first. Every pass is one scan of the text (no regex over the message), so
/// the work is linear in the source length whatever the nesting.
struct HFRBBCodeWriter {
    var smileysEnabled: Bool
    var smileys: [String: URL]

    /// HFR-shaped body HTML for `source`, to be parsed by `MessageContentNormalizer.normalize(contentHTML:)`.
    func html(for source: String) -> String {
        var placeholders: [String] = []
        func hold(_ fragment: String) -> String {
            placeholders.append(fragment)
            return "\u{FFFF}\(placeholders.count - 1)\u{FFFF}"
        }
        var text = Self.escape(Self.normalizedLineBreaks(source))
        // 1. Raw blocks, `cpp` before `code` (HFR numbers the `cpp` block first, `R95d` ids), then `fixed`.
        for tag in ["cpp", "code", "fixed"] {
            text = Self.replacingPairs(tag, in: text) { hold(Self.rawBlock(tag, content: $0)) }
        }
        // 2. Whitespace and line breaks, on the text as typed (`R20`, `R27b`, `R95d`).
        text = Self.spacedText(text)
        // 3. Links and images: their URL and text are final, no later pass may rewrite them.
        text = Self.replacingNamedURLs(in: text) { url, content in
            hold("<a href=\"\(Self.schemed(url))\" class=\"cLink\">") + Self.trimmedLinkText(content) + hold("</a>")
        }
        text = Self.replacingPairs("url", in: text, argumentIsURL: true) {
            hold("<a href=\"\(Self.schemed($0))\" class=\"cLink\">\(Self.trimmedLinkText($0))</a>")
        }
        text = Self.replacingPairs("img", in: text, argumentIsURL: true) { hold("<img src=\"\($0)\" alt=\"\($0)\" title=\"\($0)\" />") }
        // 4. Smileys, longest code first, matched whatever the case: `alt` as typed, `title` the catalogue's code (`R20`).
        if smileysEnabled {
            for (code, url) in smileys.sorted(by: { ($1.key.count, $0.key) < ($0.key.count, $1.key) }) {
                let escapedCode = Self.escape(code)
                let source = Self.escape(url.absoluteString)
                text = Self.replacingOccurrences(of: escapedCode, in: text) {
                    hold("<img src=\"\(source)\" alt=\"\($0)\" title=\"\(escapedCode)\" />")
                }
            }
        }
        // 5. Blocks, innermost first; 6. colour; 7. inline tags, each in one non-greedy pass (crossed tags stay crossed).
        text = Self.replacingNested("quote", in: text) {
            "</p><div class=\"container\"><table class=\"quote\"><tr class=\"none\"><td><b class=\"s1\">Citation :</b><br /><br />"
                + "<p>\($0)<br /></p></td></tr></table></div><p>"
        }
        text = Self.replacingNested("spoiler", in: text) {
            "</p><div class=\"container\"><table class=\"spoiler\"><tr class=\"none\"><td><b class=\"s1Topic\">Spoiler :</b><br /><br />"
                + "<div class=\"Topic masque\"><p>\($0)</p></div></td></tr></table></div><p>"
        }
        text = Self.replacingColours(in: text)
        for (tag, open, close) in Self.inlineTags {
            text = Self.replacingPairs(tag, in: text) { open + $0 + close }
        }
        // 8. Bullets: the first `[*]` of a line opens `ul > li` for the rest of the line, whose break is consumed (`R95d`).
        text = Self.replacingBullets(in: text)
        text = "<p>" + text + "</p>"
        // 9. Placeholders back (a held fragment never holds another).
        return Self.restoringPlaceholders(in: text, placeholders)
    }

    // MARK: - Source preparation

    /// Line breaks as the posting flow sends them (`PostingBody`: CRLF); the placeholder marker cannot come from the text.
    static func normalizedLineBreaks(_ source: String) -> String {
        source.replacing("\u{FFFF}", with: "").replacing("\r\n", with: "\n").replacing("\r", with: "\n").replacing("\n", with: "\r\n")
    }

    /// HFR's own escaping of the four characters (`R95d`: `&lt;b&gt;`, `&amp;`, `&#034;`).
    static func escape(_ text: String) -> String {
        text.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;").replacing("\"", with: "&#034;")
    }

    /// HFR's whitespace rule, one for plain text, `fixed` and `code` (`R20` `para2666649` against the `R41a` prefill,
    /// `R27b`, `R95d`): in a run of spaces and CRs, the first character becomes U+00A0 when the run starts a line, then
    /// the run is read two by two: the first of a pair stays (a space as itself, a CR as the `\r` HFR leaves in the
    /// text), the second becomes U+00A0; a last one alone stays. A LF becomes `<br />`. In `code`, every run of two or
    /// more is read as at a line start (`everyRunStartsLine`: `code   text` → `code&nbsp; &nbsp;text`, `int x = 1;` kept).
    /// `  :ange:` → ` &nbsp;`, `)  \r\n\r\n` → ` &nbsp;<br />&nbsp;<br />`,
    /// ` \r\n\r\n\r\n ` → ` &nbsp;<br />&nbsp;<br />&nbsp;<br />&nbsp;`,
    /// `Bonjour,\r\n\r\n` → `Bonjour,\r<br />&nbsp;<br />`, nine leading spaces → `&nbsp; &nbsp; &nbsp; &nbsp; &nbsp;`.
    static func spacedText(_ text: String, lineBreak: String = "<br />", everyRunStartsLine: Bool = false) -> String {
        var result = String.UnicodeScalarView()
        var run: [Unicode.Scalar] = []
        var atLineStart = everyRunStartsLine
        func flushRun() {
            var position = 0
            if atLineStart && !run.isEmpty || everyRunStartsLine && run.count > 1 {
                result.append("\u{00A0}")
                position = 1
            }
            while position < run.count {
                if position + 1 < run.count {
                    result.append(run[position])
                    result.append("\u{00A0}")
                    position += 2
                } else {
                    result.append(run[position])
                    position += 1
                }
            }
            run.removeAll(keepingCapacity: true)
            atLineStart = false
        }
        for scalar in text.unicodeScalars {
            switch scalar {
            case " ", "\r":
                run.append(scalar)
            case "\n":
                flushRun()
                result.append(contentsOf: lineBreak.unicodeScalars)
                atLineStart = true
            default:
                flushRun()
                result.append(scalar)
            }
        }
        flushRun()
        return String(result)
    }

    /// The text of a link without its leading and trailing spaces (`R41a` → `R20`: `napoletana [/url]` → `napoletana</a>`,
    /// `[url=…] Solea[/url]` → `>Solea</a>`, `[url]G3Ferrari / Optima [/url]` → `>G3Ferrari / Optima</a>`).
    static func trimmedLinkText(_ content: String) -> String {
        var scalars = Substring.UnicodeScalarView(content.unicodeScalars[...])
        while let last = scalars.last, last == " " || last == "\u{00A0}" { scalars.removeLast() }
        while let first = scalars.first, first == " " || first == "\u{00A0}" { scalars.removeFirst() }
        return String(scalars)
    }

    /// A URL without a scheme gets `http://` (`R41a` → `R20`: `[url]G3Ferrari / Optima [/url]` → `href="http://G3Ferrari / Optima "`).
    static func schemed(_ url: String) -> String {
        url.contains("://") ? url : "http://" + url
    }

    // MARK: - Shapes

    /// `fixed` → `table.fixed > tr.none > td > p`, lines separated by `<br />`; `code` and `cpp` → `table.code` with the
    /// "Code :" header and one `li` per line, the CRLF removed, every run of spaces read as at a line start
    /// (`R95d`: `code&nbsp; &nbsp;text`; `R27b`: `<li></li>` for an empty line, `&nbsp; &nbsp; ` for four leading spaces);
    /// `cpp` without HFR's syntax colours (pending capture).
    static func rawBlock(_ tag: String, content: String) -> String {
        switch tag {
        case "fixed":
            let body = spacedText(content)
            return "</p><table class=\"fixed\"><tr class=\"none\"><td><p>\(body)</p></td></tr></table><p>"
        default:
            let items = content.split(separator: "\r\n", omittingEmptySubsequences: false)
                .map { "<li>\(spacedText(String($0), everyRunStartsLine: true))</li>" }.joined()
            return "</p><table class=\"code\"><tr class=\"none\"><td><b class=\"s1\">Code :</b><br />"
                + "<ol class=\"olcode\">\(items)</ol></td></tr></table><p>"
        }
    }

    /// `b` → `strong`, `i` → `em`, `u` → `span.u`, `strike` → `strike` (`R95d`).
    static let inlineTags: [(tag: String, open: String, close: String)] = [
        ("b", "<strong>", "</strong>"), ("i", "<em>", "</em>"), ("u", "<span class=\"u\">", "</span>"),
        ("strike", "<strike>", "</strike>")
    ]

    // MARK: - Passes (each one scan of the text)

    /// Every `[tag]…[/tag]` pair, non-greedy, left to right: a pair closes at the first `[/tag]` after its `[tag]`, so
    /// a crossed pair comes out crossed and a tag without its close stays text. With `argumentIsURL`, the content must
    /// be a URL: no bracket, no `<` (the text being escaped, a `<` can only be a line break), not empty.
    static func replacingPairs(
        _ tag: String, in text: String, argumentIsURL: Bool = false, with body: (String) -> String
    ) -> String {
        let open = "[\(tag)]", close = "[/\(tag)]"
        var result = ""
        var cursor = text.startIndex
        while let openRange = text[cursor...].firstRange(of: open) {
            guard let closeRange = text[openRange.upperBound...].firstRange(of: close) else { break }
            let content = String(text[openRange.upperBound..<closeRange.lowerBound])
            if argumentIsURL, content.isEmpty || content.contains(where: { $0 == "[" || $0 == "]" || $0 == "<" }) {
                result += text[cursor..<openRange.upperBound]
                cursor = openRange.upperBound
                continue
            }
            result += text[cursor..<openRange.lowerBound]
            result += body(content)
            cursor = closeRange.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// Every `[url=U]text[/url]`, non-greedy: `U` has no bracket and no line break; `text` is the formatted content.
    static func replacingNamedURLs(in text: String, with body: (String, String) -> String) -> String {
        let open = "[url=", close = "[/url]"
        var result = ""
        var cursor = text.startIndex
        while let openRange = text[cursor...].firstRange(of: open) {
            guard let argumentEnd = text[openRange.upperBound...].firstIndex(of: "]") else { break }
            let argument = text[openRange.upperBound..<argumentEnd]
            let contentStart = text.index(after: argumentEnd)
            guard !argument.isEmpty, !argument.contains(where: { $0 == "[" || $0 == "<" }),
                  let closeRange = text[contentStart...].firstRange(of: close) else {
                result += text[cursor..<openRange.upperBound]
                cursor = openRange.upperBound
                continue
            }
            result += text[cursor..<openRange.lowerBound]
            result += body(String(argument), String(text[contentStart..<closeRange.lowerBound]))
            cursor = closeRange.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// Every `[tag]…[/tag]` pair of a block, nested pairs written inside out (a `[/tag]` closes the innermost open
    /// `[tag]`); an open or a close without its match stays text.
    static func replacingNested(_ tag: String, in text: String, with body: (String) -> String) -> String {
        let open = "[\(tag)]", close = "[/\(tag)]"
        guard text.contains(close) else { return text }
        /// Segments of the result being built, one per open block plus the outermost text.
        var levels: [String] = [""]
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let nextOpen = text[cursor...].firstRange(of: open)
            let nextClose = text[cursor...].firstRange(of: close)
            guard let next = [nextOpen, nextClose].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            levels[levels.count - 1] += text[cursor..<next.lowerBound]
            if next == nextOpen {
                levels.append("")
            } else if levels.count > 1 {
                let content = levels.removeLast()
                levels[levels.count - 1] += body(content)
            } else {
                levels[0] += close
            }
            cursor = next.upperBound
        }
        levels[levels.count - 1] += text[cursor...]
        // Opens never closed are text again, their content following them.
        return levels.enumerated().map { $0.offset == 0 ? $0.element : open + $0.element }.joined()
    }

    /// `[#RRGGBB]text[/#RRGGBB]`, the toolbar's own colour syntax (`R40a` `TAinsert('['+bgColor+']', …)`, `R41a` → `R20`:
    /// `<span style="color:#0055aa">`), non-greedy, the closing tag naming the same colour.
    static func replacingColours(in text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        while let openRange = text[cursor...].firstRange(of: "[#") {
            let digitsStart = openRange.upperBound
            guard let digitsEnd = text.index(digitsStart, offsetBy: 6, limitedBy: text.endIndex), digitsEnd < text.endIndex,
                  text[digitsEnd] == "]", text[digitsStart..<digitsEnd].allSatisfy(\.isHexDigit) else {
                result += text[cursor..<openRange.upperBound]
                cursor = openRange.upperBound
                continue
            }
            let colour = text[digitsStart..<digitsEnd]
            let contentStart = text.index(after: digitsEnd)
            guard let closeRange = text[contentStart...].firstRange(of: "[/#\(colour)]") else {
                result += text[cursor..<openRange.upperBound]
                cursor = openRange.upperBound
                continue
            }
            result += text[cursor..<openRange.lowerBound]
            result += "<span style=\"color:#\(colour)\">\(text[contentStart..<closeRange.lowerBound])</span>"
            cursor = closeRange.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// `[*]` and the rest of its line (up to the `<br />` of its break, consumed) → `</p><ul><li>…</li></ul><p>` (`R95d`:
    /// `[list]</p><ul><li>item one[*]item two[/list]</li></ul><p>`).
    static func replacingBullets(in text: String) -> String {
        let bullet = "[*]", lineBreak = "<br />"
        var result = ""
        var cursor = text.startIndex
        while let bulletRange = text[cursor...].firstRange(of: bullet) {
            result += text[cursor..<bulletRange.lowerBound]
            let lineEnd = text[bulletRange.upperBound...].firstRange(of: lineBreak)
            let contentEnd = lineEnd?.lowerBound ?? text.endIndex
            result += "</p><ul><li>\(text[bulletRange.upperBound..<contentEnd])</li></ul><p>"
            cursor = lineEnd?.upperBound ?? text.endIndex
        }
        result += text[cursor...]
        return result
    }

    /// Every occurrence of `needle`, whatever its case (`R20`: `:d` typed, `:D` in the catalogue).
    static func replacingOccurrences(of needle: String, in text: String, with body: (String) -> String) -> String {
        var result = ""
        var cursor = text.startIndex
        while let range = text[cursor...].range(of: needle, options: [.caseInsensitive]) {
            result += text[cursor..<range.lowerBound]
            result += body(String(text[range]))
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// `\u{FFFF}<index>\u{FFFF}` back to the held fragments.
    static func restoringPlaceholders(in text: String, _ placeholders: [String]) -> String {
        var result = ""
        var cursor = text.startIndex
        while let start = text[cursor...].firstIndex(of: "\u{FFFF}") {
            result += text[cursor..<start]
            let indexStart = text.index(after: start)
            guard let end = text[indexStart...].firstIndex(of: "\u{FFFF}"), let index = Int(text[indexStart..<end]),
                  placeholders.indices.contains(index) else {
                cursor = indexStart
                continue
            }
            result += placeholders[index]
            cursor = text.index(after: end)
        }
        result += text[cursor...]
        return result
    }
}
