import Foundation

/// The passes of the writer, each one scan of the text on Unicode scalars (ADR 0014 §1, §4).
extension HFRBBCodeWriter {
    // MARK: - Passes (each one scan of the text)

    /// Every `[tag]…[/tag]` pair, non-greedy, left to right: a pair closes at the first `[/tag]` after its `[tag]`, so
    /// a crossed pair comes out crossed and a tag without its close stays text. With `argumentIsURL`, the content must
    /// be a URL: not empty, no bracket, no line break, no placeholder. The next close is searched once and remembered.
    static func replacingPairs(
        _ tag: String, in text: Scalars, argumentIsURL: Bool = false, with body: (Scalars) -> Scalars
    ) -> Scalars {
        let open = scalars("[\(tag)]"), close = scalars("[/\(tag)]")
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        var nextClose: Int?
        while let openIndex = find(open, in: text, from: cursor) {
            let contentStart = openIndex + open.count
            if nextClose.map({ $0 < contentStart }) ?? true {
                nextClose = find(close, in: text, from: contentStart)
            }
            guard let closeIndex = nextClose else { break }
            if argumentIsURL, !isURLArgument(text[contentStart..<closeIndex]) {
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
    /// `[tag]`); an open or a close without its match stays text. Two scans: the pairs, then the output.
    static func replacingNested(_ tag: String, in text: Scalars, open openHTML: String, close closeHTML: String) -> Scalars {
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
                tags.append(BlockTag(index: next, length: open.count, isOpen: true, matched: false))
                waiting.append(tags.count - 1)
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

    /// `[#RRGGBB]text[/#RRGGBB]`, the toolbar's own colour syntax (`R40a` `TAinsert('['+bgColor+']', …)`, `R41a` → `R20`:
    /// `<span style="color:#0055aa">`), six ASCII hex digits, non-greedy, the closing tag naming the same colour. The
    /// closing tags are indexed once per colour, so every open finds its close without rescanning.
    static func replacingColours(in text: Scalars) -> Scalars {
        let open = scalars("[#"), close = scalars("[/#")
        var closes: [String: [Int]] = [:], heads: [String: Int] = [:]
        var closeCursor = 0
        while let closeIndex = find(close, in: text, from: closeCursor) {
            let digitsStart = closeIndex + close.count, digitsEnd = digitsStart + 6
            if digitsEnd < text.count, text[digitsEnd] == "]", text[digitsStart..<digitsEnd].allSatisfy(isASCIIHexDigit) {
                closes[string(Array(text[digitsStart..<digitsEnd])), default: []].append(closeIndex)
            }
            closeCursor = digitsStart
        }
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        while let openIndex = find(open, in: text, from: cursor) {
            let digitsStart = openIndex + open.count, digitsEnd = digitsStart + 6
            guard digitsEnd < text.count, text[digitsEnd] == "]", text[digitsStart..<digitsEnd].allSatisfy(isASCIIHexDigit) else {
                result += text[cursor..<digitsStart]
                cursor = digitsStart
                continue
            }
            let colour = string(Array(text[digitsStart..<digitsEnd]))
            let contentStart = digitsEnd + 1
            // Closes before the content are consumed or stale: a head index per colour only ever moves forward.
            let list = closes[colour] ?? []
            var head = heads[colour] ?? 0
            while head < list.count, list[head] < contentStart { head += 1 }
            heads[colour] = head
            guard head < list.count, case let closeIndex = list[head] else {
                result += text[cursor..<digitsStart]
                cursor = digitsStart
                continue
            }
            result += text[cursor..<openIndex]
            result += scalars("<span style=\"color:#\(colour)\">") + text[contentStart..<closeIndex] + scalars("</span>")
            cursor = closeIndex + colour.count + 4
        }
        result += text[cursor...]
        return result
    }

    /// `[*]` and the rest of its line (up to its line break, consumed) → `</p><ul><li>…</li></ul><p>` (`R95d`:
    /// `[list]</p><ul><li>item one[*]item two[/list]\r</li></ul><p>`).
    static func replacingBullets(in text: Scalars) -> Scalars {
        let bullet = scalars("[*]")
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        while let bulletIndex = find(bullet, in: text, from: cursor) {
            result += text[cursor..<bulletIndex]
            let contentStart = bulletIndex + bullet.count
            let lineEnd = find(lineBreakMarker, in: text, from: contentStart)
            let contentEnd = lineEnd ?? text.count
            result += scalars("</p><ul><li>") + text[contentStart..<contentEnd] + scalars("</li></ul><p>")
            cursor = lineEnd.map { $0 + 1 } ?? text.count
        }
        result += text[cursor...]
        return result
    }

    /// A smiley code of the table, folded for the match, with the start of its image.
    struct SmileyCode {
        let code: Scalars, folded: Scalars, image: Scalars
    }

    /// The codes of a table as a trie over their folded scalars: at a position, the walk costs at most the longest
    /// code, whatever the number of codes (a thousand personal `[:name]` share their first scalars).
    struct SmileyTrie {
        private var children: [[Unicode.Scalar: Int]] = [[:]]
        private var terminal: [Int?] = [nil]

        init(_ codes: [SmileyCode]) {
            for (index, code) in codes.enumerated() where !code.folded.isEmpty {
                var node = 0
                for scalar in code.folded {
                    if let next = children[node][scalar] {
                        node = next
                    } else {
                        children.append([:])
                        terminal.append(nil)
                        children[node][scalar] = children.count - 1
                        node = children.count - 1
                    }
                }
                // Two codes equal once folded: the first in the table's order wins.
                if terminal[node] == nil { terminal[node] = index }
            }
        }

        /// The longest code starting at `index`, as an index into the table.
        func longestMatch(at index: Int, in text: Scalars) -> Int? {
            var node = 0, position = index, match: Int?
            while position < text.count, let next = children[node][HFRBBCodeWriter.asciiLowercased(text[position])] {
                node = next
                position += 1
                if let found = terminal[node] { match = found }
            }
            return match
        }
    }

    /// Every occurrence of a code of the table, in one scan, the longest code first at each position, ASCII letters
    /// matched whatever their case (`R20`: `:d` typed, `:D` in the catalogue), except inside a word that starts with
    /// `http://`, `https://` or `www.` (a bare URL in text; what HFR does with it is pending capture). `body` gets the
    /// code and the text as typed.
    static func replacingSmileys(_ codes: [SmileyCode], in text: Scalars, with body: (SmileyCode, Scalars) -> Scalars) -> Scalars {
        let sorted = codes.sorted { string($0.code) < string($1.code) }
        let trie = SmileyTrie(sorted)
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        var index = 0
        /// The word being scanned (space, no-break space and line break bound it) and whether it starts like a URL.
        var wordEnd = 0, wordIsURL = false
        while index < text.count {
            if index >= wordEnd {
                (wordEnd, wordIsURL) = word(at: index, in: text)
            }
            guard let found = trie.longestMatch(at: index, in: text) else {
                index += 1
                continue
            }
            let match = sorted[found]
            result += text[cursor..<index]
            let typed = Array(text[index..<index + match.folded.count])
            result += wordIsURL ? typed : body(match, typed)
            index += match.folded.count
            cursor = index
        }
        result += text[cursor...]
        return result
    }

    /// The end of the word that starts at `start` (the next space, no-break space or line break, or the end of the
    /// text; one past a boundary scalar) and whether that word starts with `http://`, `https://` or `www.`.
    private static func word(at start: Int, in text: Scalars) -> (end: Int, isURL: Bool) {
        func isBoundary(_ scalar: Unicode.Scalar) -> Bool {
            scalar == " " || scalar == noBreakSpaceMarker || scalar == lineBreakMarker
        }
        var end = start
        while end < text.count, !isBoundary(text[end]) { end += 1 }
        let head = text[start..<min(end, start + 8)].map(asciiLowercased)
        let isURL = ["http://", "https://", "www."].contains { head.starts(with: scalars($0)) }
        return (end == start ? start + 1 : end, isURL)
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
