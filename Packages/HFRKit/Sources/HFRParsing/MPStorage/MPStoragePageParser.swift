import HFRModels
import SwiftSoup

/// Finds the MPStorage thread on the private messages list and reads the JSON document of its first message.
///
/// Port of the parsing half of `MPStorage.m` at `2440d79`: `findStorageMPFromPage:` (`:692-736`) and `parseMPStorage:`
/// (`:835-903`). The page walk, the GET URLs and the writes are LOT-052's; differences from legacy are in
/// `docs/lots/LOT-038-mpstorage-page.md`.
public enum MPStoragePageParser {
    /// Looks for the storage thread on one page of the private messages list.
    /// - Parameters:
    ///   - html: The page as served.
    ///   - pageURL: The URL the page was served from, as for `PrivateMessageListParser.parse`.
    /// - Throws: `PrivateMessageListParser`'s failures (login wall, maintenance, not the MP list).
    public static func findThread(in html: String, pageURL: String) throws(ListPageFailure) -> MPStorageThreadSearch {
        let page = try PrivateMessageListParser.parse(html, pageURL: pageURL)
        // Legacy takes the first matching row (`:710-724`); a row without a readable `post` is skipped, as legacy's loop did.
        for thread in page.threads where isStorageSubject(thread.summary.title) {
            if let post = thread.summary.topicID?.topic { return .found(post: post) }
        }
        return .notOnPage(navigation: page.navigation)
    }

    /// Reads the storage thread's first page: the first message's `numreponse` and its JSON document.
    /// - Throws: `MPStoragePageError`; the "not addressed" notice is a result, not an error.
    public static func readDocument(in html: String) throws(MPStoragePageError) -> MPStorageThreadPage {
        let document: Document
        let blocks: [ExtractedMessageBlock]
        do throws(ParsingError) {
            document = try HTMLDocumentLoader.document(from: html)
            blocks = try MessageBlockParser.extract(from: document)
        } catch {
            throw .unreadablePage(error)
        }
        guard let body = document.body() else { throw .unreadablePage(.malformedDocument) }
        guard let first = blocks.first else {
            // Legacy searched the whole page for "destiné" (`:837`); only a page without messages is read that way here,
            // so a stored text holding the word cannot pass for the notice.
            let notice = body.firstDescendant(matching: .classToken("hop"))?.rawText ?? ""
            if notice.contains(notAddressedWord) { return .notAddressed }
            throw .noMessage
        }
        guard !first.block.isContinuation else { throw .notFirstPage }
        // Legacy trusted the cached `post` (`:878`); the subject check keeps another thread's message from being read
        // as the document, and later edited in its place.
        guard TopicPageMetadataParser.title(in: body) == MPStorageDocument.subject else { throw .notStorageThread }
        // Legacy reads the first `<p>` of the message cell (`:882`); the content element holds the same one.
        guard let paragraph = try? first.content.getElementsByTag("p").first() else { throw .missingParagraph }
        // The page prints U+00A0 where HFR adds non-breaking spaces; legacy removed them all (`:883`).
        let text = paragraph.rawText.replacing("\u{00A0}", with: "")
        do {
            let decoded = try MPStorageCodec.decode(text)
            return .storage(MPStorageMessage(numreponse: first.block.numreponse, text: text, document: decoded))
        } catch {
            throw .invalidDocument
        }
    }

    /// Word of HFR's "Ce message ne vous est pas destiné, désolé" notice (`RA5`), the one legacy looks for.
    static let notAddressedWord = "destiné"

    /// Legacy compares the whole title cell with the subject, with or without the `[non lu] ` prefix (`:713`);
    /// `PrivateMessageListParser` already removes the prefix when HFR prints it as its marker.
    static func isStorageSubject(_ title: String) -> Bool {
        title == MPStorageDocument.subject || title == "[non lu] \(MPStorageDocument.subject)"
    }
}
