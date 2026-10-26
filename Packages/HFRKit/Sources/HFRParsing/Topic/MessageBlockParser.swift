import Foundation
import SwiftSoup

/// Finds the message blocks of a topic page (public topic or private conversation) and reads their facts.
///
/// Port of the block part of `ParseMessagesOperation.parseData:` (`ParseMessagesOperation.m:136-177, 324-355, 398-405, 453`).
/// Policy (own pseudo, blacklist, filters), action links, quotes, content rewriting and avatar downloads are
/// out of scope: see the LOT-030 spec for what each later lot picks up from `ExtractedMessageBlock`.
public enum MessageBlockParser {
    /// Author cell text of the advertisement block HFR inserts between messages (`ParseMessagesOperation.m:172`).
    static let advertisementAuthor = "Publicité"
    /// Bold lead of the block that opens page 2 and later with a copy of the previous page's last message.
    static let continuationLead = "Reprise du message précédent :"

    /// Message blocks of a page in page order; advertisement blocks are skipped. A page without any block
    /// (a deleted conversation, a page that is not a topic) gives an empty array, not an error.
    public static func blocks(in html: String) throws(ParsingError) -> [MessageBlock] {
        let document = try HTMLDocumentLoader.document(from: html)
        return try extract(from: document).map(\.block)
    }

    /// Message blocks with their DOM elements, for the stages that continue on the same tree.
    static func extract(from document: Document) throws(ParsingError) -> [ExtractedMessageBlock] {
        // `contentHTML` is handed on as served: pretty-printing would add newlines inside `<pre>` and around inline tags.
        document.outputSettings().prettyPrint(pretty: false)
        guard let body = document.body() else { throw .malformedDocument }
        var blocks: [ExtractedMessageBlock] = []
        // Legacy matches the whole class attribute (`allowPartial:NO`); the ad block uses the same class and is dropped below.
        for table in body.descendants(matching: .exact("messagetable")) {
            let elements = (try? table.getAllElements().array().dropFirst()) ?? []
            guard let author = try author(in: elements) else { continue }
            let numreponse = try numreponse(in: elements)
            let content = try content(in: elements, numreponse: numreponse)
            let toolbar = elements.first { $0.hasAttributeValue("class", .exact("toolbar")) }
            let edited = elements.first { $0.hasAttributeValue("class", .exact("edited")) }
            let date = toolbar.flatMap { postingDate(in: $0) }
            let trailer = edited.map { editTrailer(in: $0) } ?? EditTrailer()
            let block = MessageBlock(
                numreponse: numreponse,
                author: author,
                isDeleted: isDeleted(table),
                isContinuation: blocks.isEmpty && isContinuation(content),
                avatarURL: avatarURL(in: elements),
                dateText: date?.text ?? "",
                postedAt: date?.instant,
                contentHTML: try innerHTML(of: content),
                editNote: trailer.note,
                editedBy: trailer.editor,
                editedAt: trailer.instant,
                quotedByCount: trailer.quotedByCount,
                quotedByURL: trailer.quotedByURL
            )
            blocks.append(ExtractedMessageBlock(block: block, table: table, content: content, toolbar: toolbar, edited: edited))
        }
        return blocks
    }

    // MARK: - Fields

    /// The normalized author pseudo, or nil for the advertisement block.
    private static func author(in elements: some Collection<Element>) throws(ParsingError) -> String? {
        guard let cell = elements.first(where: { $0.hasAttributeValue("class", .exact("s2")) }) else {
            throw .missingElement("class=s2")
        }
        let raw = (try? cell.text()) ?? ""
        guard raw.trimmingCharacters(in: .whitespacesAndNewlines) != advertisementAuthor else { return nil }
        return HFRText.normalizedPseudo(raw)
    }

    /// The `t<numreponse>` anchor of the block: legacy reads the first child of the first cell (`:160`); the first
    /// `<a name>` of that shape in document order is the same element on every capture, and ignores the `bas` anchor
    /// that MP threads add after it.
    private static func numreponse(in elements: some Collection<Element>) throws(ParsingError) -> Int {
        for anchor in elements where anchor.tagName() == "a" && anchor.hasAttr("name") {
            guard let name = try? anchor.attr("name"), let match = name.wholeMatch(of: anchorPattern) else { continue }
            if let number = HFRURL.positiveInteger(match.output.1) { return number }
        }
        throw .missingElement("a[name=t<numreponse>]")
    }

    /// The content element: `div#para<numreponse>` on every capture; the legacy rule (first `id` containing `para`,
    /// `:177`) is the fallback.
    private static func content(in elements: some Collection<Element>, numreponse: Int) throws(ParsingError) -> Element {
        let exact = elements.first { $0.hasAttributeValue("id", .exact("para\(numreponse)")) }
        guard let element = exact ?? elements.first(where: { $0.hasAttributeValue("id", .contains("para")) }) else {
            throw .missingElement("id=para<numreponse>")
        }
        return element
    }

    /// Inner HTML of the content element; a serialization failure is a malformed document.
    private static func innerHTML(of element: Element) throws(ParsingError) -> String {
        guard let html = try? element.html() else { throw .malformedDocument }
        return html
    }

    /// Legacy compares the whole class attribute of the table's parent with `messagetabledel` (`:153`); a class token
    /// is accepted here so a wrapper with extra classes is not missed. Pending capture.
    private static func isDeleted(_ table: Element) -> Bool {
        table.parent()?.hasAttributeValue("class", .classToken("messagetabledel")) ?? false
    }

    /// The continuation block starts its first paragraph with the bold lead (R22a, R22b, R24, R26, R27, R28).
    private static func isContinuation(_ content: Element) -> Bool {
        guard
            let paragraph = content.children().first, paragraph.tagName() == "p",
            let lead = paragraph.getChildNodes().first as? Element, lead.tagName() == "strong",
            let text = try? lead.text()
        else { return false }
        return text == continuationLead
    }

    /// Source of the first image of the `avatar_center` block (`:176, 453`), as an absolute http(s) URL.
    private static func avatarURL(in elements: some Collection<Element>) -> URL? {
        guard
            let container = elements.first(where: { $0.hasAttributeValue("class", .exact("avatar_center")) }),
            let image = try? container.getElementsByTag("img").first(),
            let source = try? image.attr("src")
        else { return nil }
        return HFRURL.absolute(source)
    }

    /// First `dd-MM-yyyy à HH:mm:ss` of the toolbar text, as the legacy `dd-MM-yyyy HH:mm:ss` string plus its instant.
    private static func postingDate(in toolbar: Element) -> (text: String, instant: Date?)? {
        guard let text = try? toolbar.text(), let match = text.firstMatch(of: datePattern) else { return nil }
        return ("\(match.output.1) \(match.output.2)", HFRDate.date(from: String(match.output.0)))
    }

    /// Reads the `div.edited` trailer: "Message cité N fois" with its link, then "Message édité par <pseudo> le <date>".
    private static func editTrailer(in edited: Element) -> EditTrailer {
        var trailer = EditTrailer()
        guard let text = try? edited.text() else { return trailer }
        if let match = text.firstMatch(of: quotedPattern), let count = HFRURL.positiveInteger(match.output.1) {
            trailer.quotedByCount = count
            // Legacy takes the first link of the trailer only once a count was read (`:338-339`).
            if let link = try? edited.getElementsByTag("a").first(), let href = try? link.attr("href") {
                trailer.quotedByURL = HFRURL.absolute(href)
            }
        }
        if let match = text.firstMatch(of: editedPattern) {
            let note = match.output.1.trimmingCharacters(in: .whitespacesAndNewlines)
            trailer.note = note
            if let parts = note.wholeMatch(of: editNotePattern) {
                trailer.editor = HFRText.normalizedPseudo(String(parts.output.1))
                trailer.instant = HFRDate.date(from: String(parts.output.2))
            }
        }
        return trailer
    }

    /// The fields of a `div.edited` trailer.
    private struct EditTrailer {
        var note: String?
        var editor: String?
        var instant: Date?
        var quotedByCount: Int?
        var quotedByURL: URL?
    }

    // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). These literals capture
    // only `Substring`s and the compiled program is initialised atomically by the runtime, so sharing is safe.
    /// `t<numreponse>` anchor name.
    nonisolated(unsafe) private static let anchorPattern = /t([0-9]+)/
    /// Toolbar date; `\s` covers the U+00A0 HFR prints around `à` (`ParseMessagesOperation.m:400`).
    nonisolated(unsafe) private static let datePattern = /([0-9]{2}-[0-9]{2}-[0-9]{4})\s+à\s+([0-9]{2}:[0-9]{2}:[0-9]{2})/
    /// "Message cité N fois" (`:336`); the count must be a number where legacy kept any text.
    nonisolated(unsafe) private static let quotedPattern = /Message cité\s+([0-9]+)\s+fois/
    /// Everything after "Message édité par" (`:350`); the trailer text holds no newline.
    nonisolated(unsafe) private static let editedPattern = /Message édité par\s+(.*)/
    /// `<pseudo> le <date>`.
    nonisolated(unsafe) private static let editNotePattern =
        /(.+?)\s+le\s+([0-9]{2}-[0-9]{2}-[0-9]{4}\s+à\s+[0-9]{2}:[0-9]{2}:[0-9]{2})/
}

private extension Element {
    /// Whether `attribute` is present and satisfies `match`, with the legacy lookup semantics of `AttributeMatch`.
    func hasAttributeValue(_ attribute: String, _ match: AttributeMatch) -> Bool {
        guard hasAttr(attribute), let value = try? attr(attribute) else { return false }
        return match.matches(value)
    }
}
