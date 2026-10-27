import Foundation
import HFRModels
import SwiftSoup

/// Reads the action links of each message of a topic page (public topic or private conversation) into `MessageActions`.
///
/// Port of the action part of `ParseMessagesOperation.parseData:` (`ParseMessagesOperation.m:371-390`) and of the URL
/// handling of `ObjCMessageActionsBuilder` (`:31-47, 70-89`). Only the links HFR prints are read: whether the app offers
/// an action (`canDelete`, `canAQ`, `canBookmark`, own message…) is app policy (LOT-011 decision 5).
public enum MessageActionsParser {
    /// Forum config name of the site's multi-quote call, `quoter('hardwarefr', …)` (`ParseMessagesOperation.m:386`).
    static let quoteForum = "hardwarefr"

    /// Action links of every message block of `html`, in the order and number of `MessageBlockParser.blocks(in:)`.
    public static func actions(in html: String) throws(ParsingError) -> [MessageActions] {
        let document = try HTMLDocumentLoader.document(from: html)
        return try MessageBlockParser.extract(from: document).map { actions(of: $0) }
    }

    /// Action links of one extracted block; a block without toolbar has none.
    ///
    /// Every link is looked up inside the block's `div.toolbar`, where HFR prints them, not in the whole message row as
    /// legacy did: a link posted in the message body must not become an action the app follows with the session.
    /// Every URL is kept only on the forum origin (LESSONS 37, 43).
    static func actions(of extracted: ExtractedMessageBlock) -> MessageActions {
        guard let toolbar = extracted.toolbar else { return MessageActions() }
        let elements = (try? toolbar.getAllElements().array().dropFirst()) ?? []
        return MessageActions(
            quoteURL: obfuscatedLink(wrappingImageWithAlt: "answer", in: elements),
            editURL: obfuscatedLink(wrappingImageWithAlt: "edit", in: elements),
            alertURL: firstLink(in: elements) { $0.contains("/user/modo.php") },
            profileURL: imageParent(alt: "profil", in: elements).flatMap { forumURL(attribute: "href", of: $0) },
            privateMessageURL: firstLink(in: elements, where: isPrivateMessageLink),
            favoriteURL: firstLink(in: elements) { $0.contains("addflag") },
            quoteSelection: quoteSelection(in: elements, numreponse: extracted.block.numreponse)
        )
    }

    // MARK: - Links

    /// The parent of the first `img` whose whole `alt` is `alt` (legacy `allowPartial:NO`: `answer +` is not `answer`).
    private static func imageParent(alt: String, in elements: some Collection<Element>) -> Element? {
        elements.first { $0.tagName() == "img" && attribute("alt", of: $0) == alt }?.parent()
    }

    /// The link HFR hides in the class of the element wrapping the `alt` image (quote, edit: `:371-375`).
    ///
    /// Legacy decoded the class when it looked obfuscated and otherwise used it as a link in clear (`:84-88`);
    /// a class that neither decodes nor reads as a link (no `/`) gives nil instead of a URL built from a class name.
    private static func obfuscatedLink(wrappingImageWithAlt alt: String, in elements: some Collection<Element>) -> URL? {
        guard let wrapper = imageParent(alt: alt, in: elements), let raw = attribute("class", of: wrapper) else { return nil }
        if let decoded = ObfuscatedURL.decode(classAttribute: raw) {
            return forumURL(decoded)
        }
        return raw.contains("/") ? forumURL(raw) : nil
    }

    /// The first element whose `href` satisfies `predicate`, as a forum URL (legacy `findChildWithAttribute:@"href"`).
    private static func firstLink(in elements: some Collection<Element>, where predicate: (String) -> Bool) -> URL? {
        elements.first { attribute("href", of: $0).map(predicate) ?? false }.flatMap { forumURL(attribute: "href", of: $0) }
    }

    /// A new-MP link to the author: `/message.php` with `cat=prive` and a non-empty `dest` (`:389`).
    ///
    /// Legacy matched the literal prefix `/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=`; the parameters
    /// that make it an MP to someone are read instead, so a reordered query is still found and the multi-quote link of an
    /// MP thread (`/message.php?…&cat=prive&…&numrep=`, no `dest`) is not.
    private static func isPrivateMessageLink(_ href: String) -> Bool {
        guard let link = HFRURL.forumRelativePath(href), link.hasPrefix("/message.php?") else { return false }
        return HFRURL.queryValue(named: "cat", in: link) == "prive" && !(HFRURL.queryValue(named: "dest", in: link) ?? "").isEmpty
    }

    // MARK: - Multi-quote

    /// Arguments of the element whose `onclick` calls `quoter('hardwarefr', …)` (`:386-387`), for this block's message only.
    private static func quoteSelection(in elements: some Collection<Element>, numreponse: Int) -> QuoteSelectionToken? {
        let marker = "quoter('\(quoteForum)'"
        guard
            let script = elements.lazy.compactMap({ attribute("onclick", of: $0) }).first(where: { $0.contains(marker) }),
            let match = script.firstMatch(of: quoterPattern),
            let category = CategoryID(queryValue: String(match.output.2)),
            let topic = HFRURL.positiveInteger(match.output.3),
            let number = HFRURL.positiveInteger(match.output.4),
            // The token selects this message in the multi-quote cookie; another message's number would quote the wrong post.
            number == numreponse
        else { return nil }
        return QuoteSelectionToken(
            forum: String(match.output.1),
            topic: TopicID(category: category, topic: topic),
            numreponse: number
        )
    }

    // MARK: - Helpers

    /// `href` (or another attribute) of `element` as a forum URL.
    private static func forumURL(attribute name: String, of element: Element) -> URL? {
        attribute(name, of: element).flatMap { forumURL($0) }
    }

    /// Absolute `https://forum.hardware.fr` URL of a raw link, nil when it leaves the forum origin (LESSONS 37, 43).
    static func forumURL(_ raw: String) -> URL? {
        HFRURL.forumRelativePath(raw).flatMap { URL(string: $0, relativeTo: HFRURL.base)?.absoluteURL }
    }

    /// Value of an attribute that is present, else nil.
    private static func attribute(_ name: String, of element: Element) -> String? {
        guard element.hasAttr(name) else { return nil }
        return try? element.attr(name)
    }

    // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). This literal captures
    // only `Substring`s and the compiled program is initialised atomically by the runtime, so sharing is safe.
    /// `quoter('<forum>','<cat>',<post>,<numreponse>)`; legacy stripped either quote from every argument
    /// (`MessagesView.swift:1852-1876`), so each one may be quoted or not.
    nonisolated(unsafe) private static let quoterPattern =
        /quoter\(\s*['"]?([A-Za-z0-9_]+)['"]?\s*,\s*['"]?([A-Za-z0-9]+)['"]?\s*,\s*['"]?([0-9]+)['"]?\s*,\s*['"]?([0-9]+)['"]?\s*\)/
}
