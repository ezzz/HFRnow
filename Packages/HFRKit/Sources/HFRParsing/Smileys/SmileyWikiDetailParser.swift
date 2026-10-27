import Foundation
import SwiftSoup

/// Reads the smiley wiki detail page (`R54`).
///
/// The page lists the smiley in a form row: `<input type="hidden" name="smiley0" value="[:code]">` next to the image,
/// and the keywords in `<input type="text" name="keywords0" value="word word word">`. Keywords are split on whitespace
/// **and commas**, as the shipped Swift copies do (`MessagesView.swift:3317-3392`); the Objective-C step kept the commas
/// (its removal discarded its result, `SmileyAlertView.m:185`). Attribute entities are all decoded, as the ObjC step did.
public enum SmileyWikiDetailParser {
    /// Code, image and keywords of the entry.
    /// - Throws: `missingElement` when `smiley0` or `keywords0` is absent (a smiley unknown to the wiki is not captured).
    public static func parse(_ html: String) throws(ParsingError) -> SmileyWikiDetail {
        let document = try HTMLDocumentLoader.document(from: html)
        let codeInput = try document.requiredDescendant(attribute: "name", matching: .exact("smiley0"))
        let keywordsInput = try document.requiredDescendant(attribute: "name", matching: .exact("keywords0"))
        let code = try codeInput.requiredAttribute("value")
        let keywords = try keywordsInput.requiredAttribute("value")
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
        let image = (try? codeInput.parent()?.getElementsByTag("img"))??.first()
        let imageURL = (try? image?.attr("src")).flatMap { HFRURL.absolute($0) }
        return SmileyWikiDetail(code: code, imageURL: imageURL, keywords: keywords)
    }
}
