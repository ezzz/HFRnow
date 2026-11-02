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
            let content = Array(text[contentStart..<closeIndex])
            if argumentIsURL, !isURLArgument(content) {
                result += text[cursor..<contentStart]
                cursor = contentStart
                continue
            }
            result += text[cursor..<openIndex]
            result += body(content)
            cursor = closeIndex + close.count
        }
        result += text[cursor...]
        return result
    }

    /// A URL as a tag argument: not empty, no bracket, no line break, no held fragment.
    private static func isURLArgument(_ argument: Scalars) -> Bool {
        !argument.isEmpty && !argument.contains { $0 == "[" || $0 == "]" || $0 == lineBreakMarker || $0 == placeholderMarker }
    }

    /// Every `[url=U]text[/url]`, non-greedy: `U` has no bracket, no line break and no held fragment; `text` is the
    /// formatted content.
    static func replacingNamedURLs(in text: Scalars, with body: (Scalars, Scalars) -> Scalars) -> Scalars {
        let open = scalars("[url="), close = scalars("[/url]")
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        var nextClose: Int?
        while let openIndex = find(open, in: text, from: cursor) {
            let argumentStart = openIndex + open.count
            guard let argumentEnd = find("]", in: text, from: argumentStart) else { break }
            let argument = Array(text[argumentStart..<argumentEnd])
            let contentStart = argumentEnd + 1
            if nextClose.map({ $0 < contentStart }) ?? true {
                nextClose = find(close, in: text, from: contentStart)
            }
            guard let closeIndex = nextClose else { break }
            guard isURLArgument(argument) else {
                result += text[cursor..<argumentStart]
                cursor = argumentStart
                continue
            }
            result += text[cursor..<openIndex]
            result += body(argument, Array(text[contentStart..<closeIndex]))
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
        /// The tags, in order: position, length, open or close, matched.
        var tags: [(index: Int, length: Int, isOpen: Bool, matched: Bool)] = []
        var waiting: [Int] = []
        var nextOpen = find(open, in: text, from: 0), nextClose = find(close, in: text, from: 0)
        while let next = [nextOpen, nextClose].compactMap({ $0 }).min() {
            if next == nextOpen {
                tags.append((next, open.count, true, false))
                waiting.append(tags.count - 1)
                nextOpen = find(open, in: text, from: next + open.count)
            } else {
                if let openEntry = waiting.popLast() {
                    tags[openEntry].matched = true
                    tags.append((next, close.count, false, true))
                } else {
                    tags.append((next, close.count, false, false))
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
    /// `<span style="color:#0055aa">`), six ASCII hex digits, non-greedy, the closing tag naming the same colour. A
    /// colour whose close was not found ahead is remembered, so an unclosed one is scanned once.
    static func replacingColours(in text: Scalars) -> Scalars {
        let open = scalars("[#")
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        var unclosed: Set<String> = []
        while let openIndex = find(open, in: text, from: cursor) {
            let digitsStart = openIndex + open.count, digitsEnd = digitsStart + 6
            guard digitsEnd < text.count, text[digitsEnd] == "]", text[digitsStart..<digitsEnd].allSatisfy(isASCIIHexDigit) else {
                result += text[cursor..<digitsStart]
                cursor = digitsStart
                continue
            }
            let colour = string(Array(text[digitsStart..<digitsEnd]))
            let contentStart = digitsEnd + 1
            guard !unclosed.contains(colour), let closeIndex = find(scalars("[/#\(colour)]"), in: text, from: contentStart) else {
                unclosed.insert(colour)
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

    /// Every occurrence of a smiley code, ASCII letters matched whatever their case (`R20`: `:d` typed, `:D` in the
    /// catalogue), except inside a word that starts with `http://`, `https://` or `www.` (a bare URL in text; what
    /// HFR does with it is pending capture).
    static func replacingSmiley(_ code: Scalars, in text: Scalars, with body: (Scalars) -> Scalars) -> Scalars {
        guard !code.isEmpty else { return text }
        let folded = code.map(asciiLowercased)
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var cursor = 0
        var index = 0
        let last = text.count - code.count
        while index <= last {
            var offset = 0
            while offset < code.count, asciiLowercased(text[index + offset]) == folded[offset] { offset += 1 }
            if offset == code.count {
                result += text[cursor..<index]
                let match = Array(text[index..<index + code.count])
                result += isInsideURLWord(index, in: text) ? match : body(match)
                index += code.count
                cursor = index
            } else {
                index += 1
            }
        }
        result += text[cursor...]
        return result
    }

    /// Whether the word (no space, no line break) that holds `position` starts like a URL.
    private static func isInsideURLWord(_ position: Int, in text: Scalars) -> Bool {
        func isBoundary(_ scalar: Unicode.Scalar) -> Bool {
            scalar == " " || scalar == noBreakSpaceMarker || scalar == lineBreakMarker
        }
        var start = position
        while start > 0, !isBoundary(text[start - 1]) { start -= 1 }
        var end = position
        while end < text.count, !isBoundary(text[end]) { end += 1 }
        let word = text[start..<end].map(asciiLowercased)
        for prefix in ["http://", "https://", "www."] where word.starts(with: scalars(prefix)) { return true }
        return false
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
