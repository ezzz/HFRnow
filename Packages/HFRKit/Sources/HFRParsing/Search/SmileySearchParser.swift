import Foundation
import HFRModels
import SwiftSoup

/// Reads the answer of the smiley search (HFR-PROTOCOL R7).
///
/// `GET /message-smi-mp-aj.php?config=hfr.inc&findsmilies=+word1+word2` answers an HTML fragment with no
/// markup around it: one `<img src="…/images/perso/[N/]<name>.gif" alt="[:name[:N]]" title="…" onclick="putSmiley(…)" />`
/// per smiley (captures `R53b`, `R53c`), or the bare text "Désolé, aucune réponse n'a été trouvée !" (`R53a`).
/// Legacy took every `<img>` with a `src` and a non-empty `alt` (`SmileySearchService.swift:62-88`); this parser also requires
/// the `alt` to be a smiley code (`[:…]`), so the logo and pixels of a full page served instead of the fragment
/// (logged-out redirect, maintenance) are not mistaken for smileys.
public enum SmileySearchParser {
    /// Smileys of a search answer, in the order served. Duplicates are kept: the server repeats a smiley
    /// when it matches several keywords (`R53c` holds one twice).
    ///
    /// `code` is the `alt` exactly as served (`[:name]`, or `[:name:N]` for the personal smiley stored in folder `N`);
    /// the image URL is resolved against the forum root and kept only when it is `https`/`http` (ADR 0006 amendment 1);
    /// an `<img>` whose `alt` is not `[:…]` or with an unusable `src` is skipped.
    /// - Returns: an empty list for the "aucune réponse" answer.
    /// - Throws: `missingElement` when the page holds neither a smiley nor the "no result" sentence
    ///   (an error page or an empty body must not look like "no match").
    public static func parse(_ html: String) throws(ParsingError) -> [ForumSmiley] {
        let document = try HTMLDocumentLoader.document(from: html)
        let images: Elements
        do {
            images = try document.getElementsByTag("img")
        } catch {
            throw .malformedDocument
        }
        var smileys: [ForumSmiley] = []
        for image in images.array() {
            guard
                let code = try? image.attr("alt"), code.hasPrefix("[:"), code.hasSuffix("]"),
                let source = try? image.attr("src"),
                let url = HFRURL.absolute(source)
            else { continue }
            smileys.append(ForumSmiley(code: code, url: url))
        }
        if smileys.isEmpty, !isNoResultAnswer(document) {
            throw .missingElement("img alt=smiley code")
        }
        return smileys
    }

    // MARK: - Implementation

    /// The "Désolé, aucune réponse n'a été trouvée !" sentence, matched on its stable core (case and accents ignored).
    private static func isNoResultAnswer(_ document: Document) -> Bool {
        guard let text = try? document.text() else { return false }
        return text.range(of: "aucune réponse", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
