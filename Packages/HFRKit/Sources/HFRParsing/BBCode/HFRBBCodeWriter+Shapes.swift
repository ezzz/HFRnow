import Foundation

/// The HTML shapes of the raw blocks and inline tags (LOT-097 spec "Rendering table").
extension HFRBBCodeWriter {
    // MARK: - Shapes

    /// `fixed` → `table.fixed > tr.none > td > p`, lines separated by `<br />`; `code` and `cpp` → `table.code` with the
    /// "Code :" header and one `li` per line, the CRLF removed, every run of spaces read as at a line start
    /// (`R95d`: `code&nbsp; &nbsp;text`; `R27b`: `<li></li>` for an empty line, `&nbsp; &nbsp; ` for four leading spaces);
    /// `cpp` without HFR's syntax colours (pending capture). The content is escaped here, as typed.
    static func rawBlock(_ tag: String, content: Scalars) -> Scalars {
        let noBreakSpace = scalars(noBreakSpace)
        switch tag {
        case "fixed":
            let body = replacing(noBreakSpaceMarker, with: noBreakSpace, in: spacedText(escape(content)))
            return scalars("</p><table class=\"fixed\"><tr class=\"none\"><td><p>") + body + scalars("</p></td></tr></table><p>")
        default:
            var items: Scalars = []
            var line: Scalars = []
            var index = 0
            func flushLine() {
                let spaced = spacedText(escape(line), everyRunStartsLine: true)
                items += scalars("<li>") + replacing(noBreakSpaceMarker, with: noBreakSpace, in: spaced) + scalars("</li>")
                line.removeAll(keepingCapacity: true)
            }
            while index < content.count {
                if content[index] == "\r", index + 1 < content.count, content[index + 1] == "\n" {
                    flushLine()
                    index += 2
                } else {
                    line.append(content[index])
                    index += 1
                }
            }
            flushLine()
            return scalars("</p><table class=\"code\"><tr class=\"none\"><td><b class=\"s1\">Code :</b><br /><ol class=\"olcode\">")
                + items + scalars("</ol></td></tr></table><p>")
        }
    }

    /// `b` → `strong`, `i` → `em`, `u` → `span.u`, `strike` → `strike` (`R95d`).
    static let inlineTags: [(tag: String, open: String, close: String)] = [
        ("b", "<strong>", "</strong>"), ("i", "<em>", "</em>"), ("u", "<span class=\"u\">", "</span>"),
        ("strike", "<strike>", "</strike>")
    ]
}
