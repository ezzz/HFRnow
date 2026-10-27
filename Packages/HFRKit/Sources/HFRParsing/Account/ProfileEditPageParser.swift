import Foundation
import SwiftSoup

/// Reads a profile edit page (`GET /user/editprofil.php?config=hfr.inc&page=N`, HFR-PROTOCOL R6).
///
/// Login fetches page 5 to learn the account's `hash_check` and avatar (`LoginService.swift:87-113`).
/// Captures `R55-p1`, `R55-p3` and `R55-p5` show that every page of the form carries the token twice
/// (the header search form and `form[name=ONSENFOU]`), so the same reader works on all of them.
public enum ProfileEditPageParser {
    /// Token and avatar of an edit page.
    ///
    /// The token is the first non-empty `hash_check` input value (legacy: first regex match,
    /// `LoginService.swift:100`). The avatar is the first `<img>` of the value cell of the row labelled "Avatar";
    /// legacy took the first `<img>` after any `profilCase3`, which would pick an unrelated image on a page
    /// whose avatar row is absent. Its `src` is resolved against the forum root and kept only when `https`/`http`.
    /// - Throws: `missingElement` when the page has no `hash_check` input, `invalidValue` when every one is empty
    ///   (logged-out pages print an empty token, `R01`).
    public static func parse(_ html: String) throws(ParsingError) -> ProfileEditPage {
        let document = try HTMLDocumentLoader.document(from: html)
        let tokens = document.descendants(attribute: "name", matching: .exact("hash_check"))
            .filter { $0.tagName() == "input" }
        guard !tokens.isEmpty else { throw .missingElement("input name=hash_check") }
        let values = tokens.compactMap { try? $0.attr("value") }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let hashCheck = values.first(where: { !$0.isEmpty }) else { throw .invalidValue(field: "hash_check") }
        return ProfileEditPage(hashCheck: hashCheck, avatarURL: avatarURL(in: document))
    }

    // MARK: - Implementation

    /// `<img src>` inside the `profilCase3` cell of the `tr.profil` whose `profilCase2` label starts with "Avatar".
    private static func avatarURL(in document: Document) -> URL? {
        for row in document.descendants(matching: .classToken("profil")) where row.tagName() == "tr" {
            guard
                let label = row.firstDescendant(matching: .classToken("profilCase2")),
                let labelText = try? label.text(),
                labelText.replacing("\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Avatar"),
                let cell = row.firstDescendant(matching: .classToken("profilCase3"))
            else { continue }
            guard
                let image = (try? cell.getElementsByTag("img"))?.first(),
                let source = try? image.attr("src")
            else { return nil }
            return HFRURL.absolute(source)
        }
        return nil
    }
}
