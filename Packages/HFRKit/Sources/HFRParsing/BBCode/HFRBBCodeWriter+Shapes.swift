import Foundation

/// The HTML shapes of the raw blocks and inline tags (LOT-097 spec "Rendering table").
extension HFRBBCodeWriter {
    // MARK: - Shapes

    /// `fixed` → `table.fixed > tr.none > td > p`, lines separated by `<br />`; `code` and `cpp` → `table.code` with the
    /// "Code :" header and one `li` per line, the CRLF removed, every run of spaces read as at a line start
    /// (`R95d`: `code&nbsp; &nbsp;text`; `R27b`: `<li></li>` for an empty line, `&nbsp; &nbsp; ` for four leading spaces),
    /// with HFR's syntax colours (`R443e`, both tags) and, in `code`, `[b]` rendered (`R443j`). The content is escaped here,
    /// as typed.
    static func rawBlock(_ tag: String, content: Scalars) -> Scalars {
        let noBreakSpace = scalars(noBreakSpace)
        switch tag {
        case "fixed":
            let body = replacing(noBreakSpaceMarker, with: noBreakSpace, in: spacedText(escape(content)))
            return fixedBlock(body)
        default:
            var items: Scalars = []
            var line: Scalars = []
            var index = 0
            func flushLine(endedByLineBreak: Bool) {
                items += scalars("<li>") + codeLine(tag, line, endsWithCR: endedByLineBreak) + scalars("</li>")
                line.removeAll(keepingCapacity: true)
            }
            while index < content.count {
                if content[index] == "\r", index + 1 < content.count, content[index + 1] == "\n" {
                    flushLine(endedByLineBreak: true)
                    index += 2
                } else {
                    line.append(content[index])
                    index += 1
                }
            }
            flushLine(endedByLineBreak: false)
            return codeBlock(items)
        }
    }

    private static func fixedBlock(_ body: Scalars) -> Scalars {
        scalars("</p><table class=\"fixed\"><tr class=\"none\"><td><p>") + body + scalars("</p></td></tr></table><p>")
    }

    private static func codeBlock(_ items: Scalars) -> Scalars {
        scalars("</p><table class=\"code\"><tr class=\"none\"><td><b class=\"s1\">Code :</b><br /><ol class=\"olcode\">")
            + items + scalars("</ol></td></tr></table><p>")
    }

    /// One line of a `code` or `cpp` block: escaped, spaced, coloured, `[b]` rendered in `code`, and the blocks HFR renders
    /// inside a line (`R443n`: `[code]` in `[cpp]`, `[fixed]` in `[cpp]` or `[code]`, one line only; the inner content is
    /// the line's own HTML, escaped again and coloured again, as HFR's passes run over the previous pass's output).
    private static func codeLine(_ tag: String, _ line: Scalars, endsWithCR: Bool) -> Scalars {
        var html = syntaxColoured(spacedText(escape(line, guardingParenthesis: true), everyRunStartsLine: true), endsWithCR: endsWithCR)
        if tag == "code" {
            html = replacingPairs("b", in: html, nonEmpty: true) { scalars("<strong>") + $0 + scalars("</strong>") }
        }
        if tag == "cpp" {
            html = replacingPairs("code", in: html) { inner in
                codeBlock(scalars("<li>") + syntaxColoured(escape(inner, guardingParenthesis: true), endsWithCR: false) + scalars("</li>"))
            }
        }
        html = replacingPairs("fixed", in: html) { fixedBlock($0) }
        return replacing(noBreakSpaceMarker, with: scalars(noBreakSpace), in: html)
    }

    /// The keywords HFR colours blue, every one seen in a capture (`R27b`, `R443e`, `R443n`); the others of the language
    /// are pending capture.
    private static let keywords: Set<String> = ["auto", "break", "case", "default", "for", "int", "return", "switch", "#include"]

    /// HFR's colours of a code line (`R443e`: `[cpp]` and `[code]` alike): a keyword in `span[style=color:blue]`, from the
    /// first `//` to the end of the line `span[style=color:green] > i`, which holds the line's CR (`R27b`); no other token is
    /// coloured, string literals included. A keyword is a whole identifier (pending capture).
    static func syntaxColoured(_ line: Scalars, endsWithCR: Bool) -> Scalars {
        let commentStart = find(scalars("//"), in: line, from: 0) ?? line.count
        var result: Scalars = []
        result.reserveCapacity(line.count)
        func isIdentifier(_ scalar: Unicode.Scalar) -> Bool { isASCIILetter(scalar) || isASCIIDigit(scalar) || scalar == "_" }
        var index = 0
        while index < commentStart {
            guard line[index] == "#" || isIdentifier(line[index]) else {
                result.append(line[index])
                index += 1
                continue
            }
            var end = index + 1
            while end < commentStart, isIdentifier(line[end]) { end += 1 }
            let token = Array(line[index..<end])
            if keywords.contains(string(token)) {
                result += scalars("<span style=\"color:blue\">") + token + scalars("</span>")
            } else {
                result += token
            }
            index = end
        }
        if commentStart < line.count {
            result += scalars("<span style=\"color:green\"><i>") + line[commentStart...] + (endsWithCR ? ["\r"] : [])
                + scalars("</i></span>")
        }
        return result
    }

    /// An inline tag and the HTML HFR writes around its content.
    struct InlineTag {
        let tag: String, open: String, close: String
    }

    /// `b` → `strong`, `i` → `em`, `u` → `span.u`, `strike` → `strike` (`R95d`).
    static let inlineTags: [InlineTag] = [
        InlineTag(tag: "b", open: "<strong>", close: "</strong>"), InlineTag(tag: "i", open: "<em>", close: "</em>"),
        InlineTag(tag: "u", open: "<span class=\"u\">", close: "</span>"), InlineTag(tag: "strike", open: "<strike>", close: "</strike>")
    ]
}
