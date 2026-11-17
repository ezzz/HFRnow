import Foundation
import SwiftSoup

/// A smiley the member created: the code to type and its image.
public struct OwnSmiley: Sendable, Hashable, Identifiable {
    /// The code to type in a message, `[:code]` or `[:code:N]` (the image's `alt` between the brackets).
    public var code: String
    /// Absolute `http(s)` URL of the image under `/images/perso/`.
    public var imageURL: URL
    /// The code is unique on a page.
    public var id: String { code }

    /// Creates a value; used by the parser and by tests.
    public init(code: String, imageURL: URL) {
        self.code = code
        self.imageURL = imageURL
    }
}

/// Reads the member's own created smileys from the profile edit page 5 (`GET /user/editprofil.php?config=hfr.inc&page=5`):
/// the row « Smilies persos » lists `<img src=".../images/perso/[N/]code.gif" alt="code[:N]" title /> [:code[:N]]` for each one,
/// then a link to `uploadsmil.php` (HFR-PROTOCOL §6c « Smiley page and filtered lists », `R601a`; a member with none has only
/// the link, `R55-p5`).
///
/// The page is not the only thing that can answer this URL: a logged-out or other page has no such row, and that throws instead
/// of reading as « no smileys » (LESSONS 44).
public enum OwnSmileysParser {
    /// The smileys of the row, in the order printed, a repeated code dropped.
    /// - Throws: `missingElement` when the page has no « Smilies persos » row.
    public static func parse(_ html: String) throws(ParsingError) -> [OwnSmiley] {
        let document = try HTMLDocumentLoader.document(from: html)
        for row in document.descendants(matching: .classToken("profil")) where row.tagName() == "tr" {
            guard
                let label = row.firstDescendant(matching: .classToken("profilCase2")),
                let labelText = try? label.text(),
                labelText.replacing("\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Smilies persos"),
                let cell = row.firstDescendant(matching: .classToken("profilCase3"))
            else { continue }
            return smileys(in: cell)
        }
        throw .missingElement("tr.profil « Smilies persos »")
    }

    private static func smileys(in cell: Element) -> [OwnSmiley] {
        var found: [OwnSmiley] = []
        for image in (try? cell.getElementsByTag("img").array()) ?? [] {
            guard
                let source = try? image.attr("src"), source.contains("/images/perso/"), let url = HFRURL.absolute(source),
                let alt = try? image.attr("alt")
            else { continue }
            let name = alt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let smiley = OwnSmiley(code: "[:\(name)]", imageURL: url)
            if !found.contains(where: { $0.code == smiley.code }) { found.append(smiley) }
        }
        return found
    }
}
