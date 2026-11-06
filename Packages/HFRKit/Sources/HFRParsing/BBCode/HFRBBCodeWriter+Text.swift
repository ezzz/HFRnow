import Foundation

/// Scalars, source preparation and HFR's text rules (escaping, whitespace, link text, scheme).
extension HFRBBCodeWriter {
    // MARK: - Scalars

    static func scalars(_ text: String) -> Scalars { Array(text.unicodeScalars) }

    static func string(_ scalars: Scalars) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// The first occurrence of `needle` in `text` at or after `start`.
    static func find(_ needle: Scalars, in text: Scalars, from start: Int) -> Int? {
        guard !needle.isEmpty, text.count >= needle.count else { return nil }
        var index = start
        let last = text.count - needle.count
        while index <= last {
            if text[index] == needle[0] {
                var offset = 1
                while offset < needle.count, text[index + offset] == needle[offset] { offset += 1 }
                if offset == needle.count { return index }
            }
            index += 1
        }
        return nil
    }

    static func find(_ scalar: Unicode.Scalar, in text: Scalars, from start: Int) -> Int? {
        var index = start
        while index < text.count {
            if text[index] == scalar { return index }
            index += 1
        }
        return nil
    }

    // MARK: - Source preparation

    /// Placeholder marker (U+FFFF, a noncharacter): `\u{FFFF}<index>\u{FFFF}`.
    static let placeholderMarker: Unicode.Scalar = "\u{FFFF}"
    /// Stands for a LF until the tags are written (a `<br />` in the text would be escaped by step 5).
    static let lineBreakMarker: Unicode.Scalar = "\u{FFFE}"
    /// Stands for the `&nbsp;` HFR writes (the entity, as in HFR's bytes) until the text is escaped. U+FDD0 is a
    /// noncharacter, like the two others; Swift takes it from its value, not from a literal.
    static let noBreakSpaceMarker: Unicode.Scalar = {
        guard let scalar = Unicode.Scalar(UInt32(0xFDD0)) else { preconditionFailure("U+FDD0 is a Unicode scalar") }
        return scalar
    }()
    static let noBreakSpace = "&nbsp;"

    static func placeholder(_ index: Int) -> Scalars {
        [placeholderMarker] + scalars(String(index)) + [placeholderMarker]
    }

    /// Line breaks as the posting flow sends them (`PostingBody`: CRLF); the three markers cannot come from the text.
    static func normalizedLineBreaks(_ source: Scalars) -> Scalars {
        var result: Scalars = []
        result.reserveCapacity(source.count)
        var index = 0
        while index < source.count {
            let scalar = source[index]
            switch scalar {
            case placeholderMarker, lineBreakMarker, noBreakSpaceMarker:
                break
            case "\r":
                result.append(contentsOf: ["\r", "\n"])
                if index + 1 < source.count, source[index + 1] == "\n" { index += 1 }
            case "\n":
                result.append(contentsOf: ["\r", "\n"])
            default:
                result.append(scalar)
            }
            index += 1
        }
        return result
    }

    /// HFR's own escaping of the four characters (`R95d`: `&lt;b&gt;`, `&amp;`, `&#034;`), scalar by scalar.
    static func escape(_ text: Scalars) -> Scalars {
        var result: Scalars = []
        result.reserveCapacity(text.count)
        for scalar in text {
            switch scalar {
            case "&": result.append(contentsOf: "&amp;".unicodeScalars)
            case "<": result.append(contentsOf: "&lt;".unicodeScalars)
            case ">": result.append(contentsOf: "&gt;".unicodeScalars)
            case "\"": result.append(contentsOf: "&#034;".unicodeScalars)
            default: result.append(scalar)
            }
        }
        return result
    }

    /// HFR's whitespace rule, one for plain text, `fixed` and `code` (`R20` `para2666649` against the `R41a` prefill,
    /// `R27b`, `R95d`): in a run of spaces and CRs, the first character becomes `&nbsp;` when the run starts a line
    /// (right after a LF; the start of the message is not a line start), then the run is read two by two: the first of
    /// a pair stays (a space as itself, a CR as the `\r` HFR leaves in the text), the second becomes `&nbsp;`; a last one
    /// alone stays. A LF becomes `lineBreak`. In `code`, every run of two or more is read as at a line start
    /// (`everyRunStartsLine`: `code   text` → `code&nbsp; &nbsp;text`, `int x = 1;` kept; a run of one at a code
    /// line's start becomes `&nbsp;` too, pending capture).
    /// `  :ange:` → ` &nbsp;`, `)  \r\n\r\n` → ` &nbsp;\r<br />&nbsp;<br />`,
    /// ` \r\n\r\n\r\n ` → ` &nbsp;<br />&nbsp;<br />&nbsp;<br />&nbsp;`, `Bonjour,\r\n\r\n` → `Bonjour,\r<br />&nbsp;<br />`,
    /// nine leading spaces → `&nbsp; &nbsp; &nbsp; &nbsp; &nbsp;`.
    static func spacedText(_ text: Scalars, lineBreak: Scalars = scalars("<br />"), everyRunStartsLine: Bool = false) -> Scalars {
        var result: Scalars = []
        result.reserveCapacity(text.count)
        var run: Scalars = []
        var atLineStart = everyRunStartsLine
        func flushRun() {
            var position = 0
            if atLineStart && !run.isEmpty || everyRunStartsLine && run.count > 1 {
                result.append(noBreakSpaceMarker)
                position = 1
            }
            while position < run.count {
                result.append(run[position])
                if position + 1 < run.count { result.append(noBreakSpaceMarker) }
                position += 2
            }
            run.removeAll(keepingCapacity: true)
            atLineStart = false
        }
        for scalar in text {
            switch scalar {
            case " ", "\r":
                run.append(scalar)
            case "\n":
                flushRun()
                result.append(contentsOf: lineBreak)
                atLineStart = true
            default:
                flushRun()
                result.append(scalar)
            }
        }
        flushRun()
        return result
    }

    /// The text of a link without its leading and trailing spaces (`R41a` → `R20`: `napoletana [/url]` → `napoletana</a>`,
    /// `[url=…] Solea[/url]` → `>Solea</a>`, `[url]G3Ferrari / Optima [/url]` → `>G3Ferrari / Optima</a>`).
    static func trimmedLinkText(_ content: Scalars) -> Scalars {
        var start = 0, end = content.count
        while start < end, content[start] == " " || content[start] == noBreakSpaceMarker { start += 1 }
        while end > start, content[end - 1] == " " || content[end - 1] == noBreakSpaceMarker { end -= 1 }
        return Array(content[start..<end])
    }

    /// A URL without a scheme (`scheme:` prefix, RFC 3986, ASCII) gets `http://` (`R41a` → `R20`: `[url]G3Ferrari / Optima [/url]`
    /// → `href="http://G3Ferrari / Optima "`); a URL with another scheme is left to the normalizer, which drops it.
    static func schemed(_ url: Scalars) -> Scalars {
        if let first = url.first, isASCIILetter(first) {
            var index = 1
            while index < url.count, isASCIILetter(url[index]) || isASCIIDigit(url[index]) || "+-.".unicodeScalars.contains(url[index]) {
                index += 1
            }
            if index < url.count, url[index] == ":" { return url }
        }
        return scalars("http://") + url
    }

    static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool { ("0"..."9").contains(scalar) }

    static func isASCIIHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIDigit(scalar) || ("a"..."f").contains(scalar) || ("A"..."F").contains(scalar)
    }

    /// Lowercases an ASCII letter; any other scalar is itself (what HFR does with the case of a non-ASCII code is pending).
    static func asciiLowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        ("A"..."Z").contains(scalar) ? Unicode.Scalar(scalar.value + 32) ?? scalar : scalar
    }

}
