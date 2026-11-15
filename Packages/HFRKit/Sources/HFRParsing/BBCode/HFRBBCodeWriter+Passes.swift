import Foundation

/// The passes of the writer, each one scan of the text on Unicode scalars (ADR 0014 §1, §4).
extension HFRBBCodeWriter {
    // MARK: - Passes (each one scan of the text)

    /// Every `[tag]…[/tag]` pair, non-greedy, left to right: a pair closes at the first `[/tag]` after its `[tag]`, so
    /// a crossed pair comes out crossed and a tag without its close stays text. With `argumentIsURL`, the content must
    /// be a URL: not empty, no bracket, no line break, no placeholder. With `rawContent`, a content holding a placeholder
    /// (a raw block already held) leaves the tags as text, so no held fragment ever holds another. The next close and
    /// the next placeholder are searched once and remembered.
    /// `schemes`: with `argumentIsURL`, the argument must start with one of them (`[img]`: `R443f`). `nonEmpty`:
    /// `[b][/b]` is text (`R443j`). `dropsTagsAroundHeld`:
    /// a raw pair around a held block loses its tags and keeps its content (`[fixed]f [cpp]…[/cpp] f[/fixed]`, `R443n`).
    static func replacingPairs(
        _ tag: String, in text: Scalars, argumentIsURL: Bool = false, rawContent: Bool = false, nonEmpty: Bool = false,
        dropsTagsAroundHeld: Bool = false, schemes: [Scalars] = [], with body: (Scalars) -> Scalars
    ) -> Scalars {
        let open = scalars("[\(tag)]"), close = scalars("[/\(tag)]")
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        var nextClose: Int?, nextMarker: Int?
        while let openIndex = find(open, in: text, from: cursor) {
            let contentStart = openIndex + open.count
            if nextClose.map({ $0 < contentStart }) ?? true {
                nextClose = find(close, in: text, from: contentStart)
            }
            guard let closeIndex = nextClose else { break }
            if rawContent, nextMarker.map({ $0 < contentStart }) ?? true {
                nextMarker = find(placeholderMarker, in: text, from: contentStart) ?? Int.max
            }
            if rawContent && dropsTagsAroundHeld && (nextMarker ?? Int.max) < closeIndex {
                result += text[cursor..<openIndex]
                result += text[contentStart..<closeIndex]
                cursor = closeIndex + close.count
                continue
            }
            if argumentIsURL && !isURLArgument(text[contentStart..<closeIndex]) || rawContent && (nextMarker ?? Int.max) < closeIndex
                || nonEmpty && closeIndex == contentStart
                || !schemes.isEmpty && !schemes.contains(where: { startsWithFolded(text[contentStart..<closeIndex], $0) }) {
                result += text[cursor..<contentStart]
                cursor = contentStart
                continue
            }
            result += text[cursor..<openIndex]
            result += body(Array(text[contentStart..<closeIndex]))
            cursor = closeIndex + close.count
        }
        result += text[cursor...]
        return result
    }

    private static func startsWithFolded(_ slice: ArraySlice<Unicode.Scalar>, _ prefix: Scalars) -> Bool {
        slice.count >= prefix.count && zip(prefix, slice).allSatisfy { $0 == asciiLowercased($1) }
    }

    /// A URL as a tag argument: not empty, no bracket, no line break, no held fragment. Checked on the slice, before
    /// any copy, so a rejected argument costs its own length only.
    private static func isURLArgument(_ argument: ArraySlice<Unicode.Scalar>) -> Bool {
        !argument.isEmpty && !argument.contains { $0 == "[" || $0 == "]" || $0 == lineBreakMarker || $0 == placeholderMarker }
    }

    /// Every `[url=U]text[/url]`, non-greedy: `U` has no bracket, no line break and no held fragment; `text` is the
    /// formatted content.
    static func replacingNamedURLs(in text: Scalars, with body: (Scalars, Scalars) -> Scalars) -> Scalars {
        let open = scalars("[url="), close = scalars("[/url]")
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        var nextClose: Int?, nextBracket: Int?
        while let openIndex = find(open, in: text, from: cursor) {
            let argumentStart = openIndex + open.count
            if nextBracket.map({ $0 < argumentStart }) ?? true {
                nextBracket = find("]", in: text, from: argumentStart)
            }
            guard let argumentEnd = nextBracket else { break }
            let contentStart = argumentEnd + 1
            if nextClose.map({ $0 < contentStart }) ?? true {
                nextClose = find(close, in: text, from: contentStart)
            }
            guard let closeIndex = nextClose else { break }
            guard isURLArgument(text[argumentStart..<argumentEnd]) else {
                result += text[cursor..<argumentStart]
                cursor = argumentStart
                continue
            }
            result += text[cursor..<openIndex]
            result += body(Array(text[argumentStart..<argumentEnd]), Array(text[contentStart..<closeIndex]))
            cursor = closeIndex + close.count
        }
        result += text[cursor...]
        return result
    }

    /// Every `[tag]…[/tag]` pair of a block, nested pairs written inside out (a `[/tag]` closes the innermost open
    /// `[tag]`); an open or a close without its match stays text. Past `maxDepth` open pairs an open stays text: of 30
    /// nested quotes only the two outer levels render, and the closes pair with the opens that did (`R443l`). Two scans:
    /// the pairs, then the output.
    static func replacingNested(
        _ tag: String, in text: Scalars, open openHTML: String, close closeHTML: String, maxDepth: Int = .max
    ) -> Scalars {
        let open = scalars("[\(tag)]"), close = scalars("[/\(tag)]")
        guard find(close, in: text, from: 0) != nil else { return text }
        /// A block tag of the text: where it is, whether it opens, whether its match was found.
        struct BlockTag {
            let index: Int, length: Int, isOpen: Bool
            var matched: Bool
        }
        var tags: [BlockTag] = []
        var waiting: [Int] = []
        var nextOpen = find(open, in: text, from: 0), nextClose = find(close, in: text, from: 0)
        while let next = [nextOpen, nextClose].compactMap({ $0 }).min() {
            if next == nextOpen {
                if waiting.count < maxDepth {
                    tags.append(BlockTag(index: next, length: open.count, isOpen: true, matched: false))
                    waiting.append(tags.count - 1)
                }
                nextOpen = find(open, in: text, from: next + open.count)
            } else {
                if let openEntry = waiting.popLast() {
                    tags[openEntry].matched = true
                    tags.append(BlockTag(index: next, length: close.count, isOpen: false, matched: true))
                } else {
                    tags.append(BlockTag(index: next, length: close.count, isOpen: false, matched: false))
                }
                nextClose = find(close, in: text, from: next + close.count)
            }
        }
        let openScalars = scalars(openHTML), closeScalars = scalars(closeHTML)
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        for entry in tags where entry.matched {
            result += text[cursor..<entry.index]
            result += entry.isOpen ? openScalars : closeScalars
            cursor = entry.index + entry.length
        }
        result += text[cursor...]
        return result
    }

    /// The length of the hex digits at `start` when they are 3 or 6 ASCII hex digits followed by `]`.
    private static func hexLength(at start: Int, in text: Scalars) -> Int? {
        for length in [6, 3] where start + length < text.count && text[start + length] == "]"
            && text[start..<start + length].allSatisfy(isASCIIHexDigit) {
            return length
        }
        return nil
    }

    /// `[#RRGGBB]text[/#RRGGBB]` (or three digits), the toolbar's own colour syntax (`R40a` `TAinsert('['+bgColor+']', …)`,
    /// `R41a` → `R20`: `<span style="color:#0055aa">`). The open pairs with the first colour close after it, **whatever
    /// that close names** (`R443n`: `[#0055AA]x[/#0055aa]` renders with the open's case; `[#ff0000]a [#00ff00]b[/#00ff00]
    /// c[/#ff0000]` closes at the inner close and leaves the inner open and the outer close as text). The closes are
    /// indexed once and only ever consumed forward.
    static func replacingColours(in text: Scalars) -> Scalars {
        let open = scalars("[#"), close = scalars("[/#")
        var closes: [(index: Int, end: Int)] = []
        var closeCursor = 0
        while let closeIndex = find(close, in: text, from: closeCursor) {
            let digitsStart = closeIndex + close.count
            if let length = hexLength(at: digitsStart, in: text) { closes.append((closeIndex, digitsStart + length + 1)) }
            closeCursor = digitsStart
        }
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0, head = 0
        while let openIndex = find(open, in: text, from: cursor) {
            let digitsStart = openIndex + open.count
            guard let length = hexLength(at: digitsStart, in: text) else {
                result += text[cursor..<digitsStart]
                cursor = digitsStart
                continue
            }
            let contentStart = digitsStart + length + 1
            while head < closes.count, closes[head].index < contentStart { head += 1 }
            guard head < closes.count else { break }
            let colour = string(Array(text[digitsStart..<digitsStart + length]))
            result += text[cursor..<openIndex]
            result += scalars("<span style=\"color:#\(colour)\">") + text[contentStart..<closes[head].index] + scalars("</span>")
            cursor = closes[head].end
            head += 1
        }
        result += text[cursor...]
        return result
    }

    /// `[*]` and the rest of its line (up to its line break, consumed) → `</p><ul><li>…</li></ul><p>`; a next line that
    /// starts with `[*]` is another item of the same list, the first line without one ends it (`R443d`: `</p><ul><li>one\r</li>
    /// <li>two\r</li><li>three\r</li></ul><p>`, an empty `[*]` an empty `<li>`; `R95d`:
    /// `[list]</p><ul><li>item one[*]item two[/list]\r</li></ul><p>`).
    static func replacingBullets(in text: Scalars) -> Scalars {
        let bullet = scalars("[*]")
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        while let bulletIndex = find(bullet, in: text, from: cursor) {
            result += text[cursor..<bulletIndex]
            result += scalars("</p><ul>")
            var itemStart = bulletIndex + bullet.count
            while true {
                let lineEnd = find(lineBreakMarker, in: text, from: itemStart)
                result += scalars("<li>") + text[itemStart..<(lineEnd ?? text.count)] + scalars("</li>")
                guard let lineEnd, text[(lineEnd + 1)...].starts(with: bullet) else {
                    cursor = lineEnd.map { $0 + 1 } ?? text.count
                    break
                }
                itemStart = lineEnd + 1 + bullet.count
            }
            result += scalars("</ul><p>")
        }
        result += text[cursor...]
        return result
    }

    /// A smiley code of the table, folded for the match, with the start of its image.
    struct SmileyCode: Hashable, Sendable {
        let code: Scalars, folded: Scalars, image: Scalars
    }

    /// The codes of a table as a trie over their folded scalars: at a position, the walk costs at most the longest
    /// code, whatever the number of codes (a thousand personal `[:name]` share their first scalars).
    struct SmileyTrie: Hashable, Sendable {
        private var children: [[Unicode.Scalar: Int]] = [[:]]
        /// The codes (indices into the table) whose folded form ends at the node, in the table's order.
        private var terminal: [[Int]] = [[]]
        private let codes: [SmileyCode]

        init(_ codes: [SmileyCode]) {
            self.codes = codes
            for (index, code) in codes.enumerated() where !code.folded.isEmpty {
                var node = 0
                for scalar in code.folded {
                    if let next = children[node][scalar] {
                        node = next
                    } else {
                        children.append([:])
                        terminal.append([])
                        children[node][scalar] = children.count - 1
                        node = children.count - 1
                    }
                }
                terminal[node].append(index)
            }
        }

        /// The longest code starting at `index`; among codes equal once folded, the one typed exactly, else the first
        /// of the table.
        func longestMatch(at index: Int, in text: Scalars) -> SmileyCode? {
            var node = 0, position = index, match: SmileyCode?
            while position < text.count, let next = children[node][HFRBBCodeWriter.asciiLowercased(text[position])] {
                node = next
                position += 1
                let candidates = terminal[node]
                if let first = candidates.first {
                    let typed = text[index..<position]
                    match = candidates.lazy.map { codes[$0] }.first { $0.code.elementsEqual(typed) } ?? codes[first]
                }
            }
            return match
        }
    }

    /// Every occurrence of a code of the table, in one scan, the longest code first at each position, ASCII letters
    /// matched whatever their case (`R20`: `:d` typed, `:D` in the catalogue), anywhere but inside a held fragment
    /// (`R443a`: `:)` inside a `[url]` and `:/` inside a bare URL are substituted, glued to a word too), except the `:/`
    /// of `://`, which keeps every URL's scheme whole (`https://example.invalid/:/x` links `https://example.invalid/`
    /// and `:/x` is the smiley). `body` gets the code and the text as typed.
    static func replacingSmileys(_ trie: SmileyTrie, in text: Scalars, with body: (SmileyCode, Scalars) -> Scalars) -> Scalars {
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        var index = 0
        while index < text.count {
            // A held fragment (an image, a raw block) is never matched into.
            if text[index] == placeholderMarker, let end = find(placeholderMarker, in: text, from: index + 1) {
                index = end + 1
                continue
            }
            guard let match = trie.longestMatch(at: index, in: text),
                  !(match.code.elementsEqual(":/".unicodeScalars) && index + 2 < text.count && text[index + 2] == "/") else {
                index += 1
                continue
            }
            result += text[cursor..<index]
            let typed = Array(text[index..<index + match.folded.count])
            result += body(match, typed)
            index += match.folded.count
            cursor = index
        }
        result += text[cursor...]
        return result
    }

    /// Bare `http://` and `https://` URLs of the text as typed → `a.cLink` (`R443a`, `R443f`: `https://forum.hardware.fr/`
    /// auto-linked, a smiley ends the link). A link ends at a space, a line break, a held fragment (a smiley), `<`, `>`,
    /// `"`, `[` or `]`: only the smiley and the end of the message are captured (pending). Not right after `[url]` (a `[url]`
    /// whose content a smiley made invalid stays text, URL included, `R443a`) nor after a `=` (the argument of a tag that
    /// did not match: the `=` is a guess, pending; so is a link after another tag, `[b]https://…`, linked here). Never
    /// inside a `[url=…]` link text
    /// (`anchorOpens` / `anchorCloses`: the held opening and closing tags, by placeholder index).
    static func autolinking(
        _ text: Scalars, anchorOpens: Set<Int>, anchorCloses: Set<Int>, hold: (Scalars) -> Scalars
    ) -> Scalars {
        let schemes = ["http://", "https://"].map(scalars)
        func isEnd(_ scalar: Unicode.Scalar) -> Bool {
            [" ", "\r", "\n", "<", ">", "\"", "[", "]", noBreakSpaceMarker, lineBreakMarker, placeholderMarker].contains(scalar)
        }
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0, index = 0, depth = 0
        while index < text.count {
            let scalar = text[index]
            if scalar == placeholderMarker, let end = find(placeholderMarker, in: text, from: index + 1) {
                if let held = Int(string(Array(text[(index + 1)..<end]))) {
                    if anchorOpens.contains(held) { depth += 1 } else if anchorCloses.contains(held) { depth = max(0, depth - 1) }
                }
                index = end + 1
                continue
            }
            let previous = index == 0 ? nil : text[index - 1]
            let startsAWord = previous.map { !isASCIILetter($0) && !isASCIIDigit($0) && $0 != "=" } ?? true
            guard depth == 0, startsAWord, !text[..<index].suffix(5).elementsEqual("[url]".unicodeScalars),
                  let scheme = schemes.first(where: { prefix in
                      index + prefix.count <= text.count && zip(prefix, text[index...]).allSatisfy { $0 == asciiLowercased($1) }
                  }) else {
                index += 1
                continue
            }
            var end = index + scheme.count
            while end < text.count, !isEnd(text[end]) { end += 1 }
            guard end > index + scheme.count else {
                index += 1
                continue
            }
            let url = Array(text[index..<end])
            result += text[cursor..<index]
            result += hold(scalars("<a href=\"") + escape(url) + scalars("\" class=\"cLink\">") + escape(url) + scalars("</a>"))
            cursor = end
            index = end
        }
        result += text[cursor...]
        return result
    }

    /// The line-break and no-break-space markers written as HFR writes them.
    static func replacingMarkers(in text: Scalars) -> Scalars {
        var result: Scalars = []
        result.reserveCapacity(text.count)
        for scalar in text {
            switch scalar {
            case lineBreakMarker: result += "<br />".unicodeScalars
            case noBreakSpaceMarker: result += noBreakSpace.unicodeScalars
            default: result.append(scalar)
            }
        }
        return result
    }

    static func replacing(_ marker: Unicode.Scalar, with replacement: Scalars, in text: Scalars) -> Scalars {
        var result: Scalars = []
        result.reserveCapacity(text.count)
        for scalar in text {
            if scalar == marker { result += replacement } else { result.append(scalar) }
        }
        return result
    }

    /// `\u{FFFF}<ASCII digits>\u{FFFF}` back to the held fragments; every marker comes from `hold`.
    static func restoringPlaceholders(in text: Scalars, _ placeholders: [Scalars]) -> Scalars {
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        while let start = find(placeholderMarker, in: text, from: cursor) {
            result += text[cursor..<start]
            guard let end = find(placeholderMarker, in: text, from: start + 1),
                  text[(start + 1)..<end].allSatisfy(isASCIIDigit), let index = Int(string(Array(text[(start + 1)..<end]))),
                  placeholders.indices.contains(index) else {
                cursor = start + 1
                continue
            }
            result += placeholders[index]
            cursor = end + 1
        }
        result += text[cursor...]
        return result
    }
}
