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
    /// A "toolbar" inside the message content is member markup, not HFR's, and gives no action either.
    /// Every URL is kept only on the forum origin (LESSONS 37, 43), and each action is recognised by its exact path and
    /// required parameters, never by a substring of the whole URL: a pseudo in `dest=` or any other parameter value must not
    /// turn one link into another action.
    static func actions(of extracted: ExtractedMessageBlock) -> MessageActions {
        guard let toolbar = extracted.toolbar, !isInside(toolbar, extracted.content) else { return MessageActions() }
        let elements = (try? toolbar.getAllElements().array().dropFirst()) ?? []
        let numreponse = extracted.block.numreponse
        let isPost = { (url: URL) in path(of: url) == messagePath }
        return MessageActions(
            quoteURL: keep(obfuscatedLink(wrappingImageWithAlt: "answer", in: elements), if: isPost),
            editURL: keep(obfuscatedLink(wrappingImageWithAlt: "edit", in: elements), if: isPost),
            alertURL: firstLink(in: elements) { isMessageLink($0, path: alertPath, numreponse: numreponse) },
            profileURL: keep(imageParent(alt: "profil", in: elements).flatMap { forumURL(attribute: "href", of: $0) }, if: isProfileLink),
            privateMessageURL: firstLink(in: elements, where: isPrivateMessageLink),
            favoriteURL: firstLink(in: elements) { isMessageLink($0, path: favoritePath, numreponse: numreponse) },
            quoteSelection: quoteSelection(in: elements, numreponse: numreponse)
        )
    }

    /// Path of the quote, edit and new-MP forms (`ParseMessagesOperation.m:371-375, 389`).
    static let messagePath = "/message.php"
    /// Path of the moderator alert form (`:377`).
    static let alertPath = "/user/modo.php"
    /// Path of the state-changing favourite GET (`:383`, HFR-PROTOCOL §3.2).
    static let favoritePath = "/user/addflag.php"

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

    /// The first `href` whose forum URL satisfies `predicate` (legacy `findChildWithAttribute:@"href"`, which matched a substring).
    private static func firstLink(in elements: some Collection<Element>, where predicate: (URL) -> Bool) -> URL? {
        elements.lazy.compactMap { forumURL(attribute: "href", of: $0) }.first(where: predicate)
    }

    /// `path` exactly, with `numreponse=` naming this block's message (alert and favourite links, every capture).
    private static func isMessageLink(_ url: URL, path expected: String, numreponse: Int) -> Bool {
        path(of: url) == expected && HFRURL.numreponse(in: url.absoluteString) == numreponse
    }

    /// `/hfr/profil-<id>.htm`, the only profile shape of the corpus (HFR-PROTOCOL R9).
    private static func isProfileLink(_ url: URL) -> Bool {
        path(of: url).wholeMatch(of: profilePattern) != nil
    }

    /// A new-MP link to the author: `/message.php` with `cat=prive` and a non-empty `dest` (`:389`).
    ///
    /// Legacy matched the literal prefix `/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=`; the parameters
    /// that make it an MP to someone are read instead, so a reordered query is still found and the multi-quote link of an
    /// MP thread (`/message.php?…&cat=prive&…&numrep=`, no `dest`) is not.
    private static func isPrivateMessageLink(_ url: URL) -> Bool {
        let link = url.absoluteString
        guard path(of: url) == messagePath else { return false }
        return HFRURL.queryValue(named: "cat", in: link) == "prive" && !(HFRURL.queryValue(named: "dest", in: link) ?? "").isEmpty
    }

    // MARK: - Multi-quote

    /// Arguments of the element whose `onclick` calls `quoter('hardwarefr', …)` (`:386-387`), for this block's message only.
    private static func quoteSelection(in elements: some Collection<Element>, numreponse: Int) -> QuoteSelectionToken? {
        let marker = "quoter('\(quoteForum)'"
        guard
            let script = elements.lazy.compactMap({ attribute("onclick", of: $0) }).first(where: { $0.contains(marker) }),
            let match = script.firstMatch(of: quoterPattern),
            match.output.1 == quoteForum,
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

    /// Optional has no `filter`; this keeps the field rules one expression each in `actions(of:)`.
    private static func keep(_ url: URL?, if predicate: (URL) -> Bool) -> URL? {
        url.flatMap { predicate($0) ? $0 : nil }
    }

    /// Compared percent-encoded, as served: a decoded path could turn `%2F` into a `/` and match another action's path.
    private static func path(of url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: true)?.percentEncodedPath ?? ""
    }

    /// Whether `element` is a descendant of `ancestor`.
    private static func isInside(_ element: Element, _ ancestor: Element) -> Bool {
        var node = element.parent()
        while let current = node {
            if current === ancestor { return true }
            node = current.parent()
        }
        return false
    }

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
    /// Profile page path `/hfr/profil-<id>.htm`.
    nonisolated(unsafe) private static let profilePattern = /\/hfr\/profil-[0-9]+\.htm/
    /// `quoter('<forum>','<cat>',<post>,<numreponse>)`; legacy stripped either quote from every argument and read the first
    /// four of four or more (`MessagesView.swift:1852-1876`), so each one may be quoted or not and more arguments may follow.
    nonisolated(unsafe) private static let quoterPattern =
        /quoter\(\s*['"]?([A-Za-z0-9_]+)['"]?\s*,\s*['"]?([A-Za-z0-9]+)['"]?\s*,\s*['"]?([0-9]+)['"]?\s*,\s*['"]?([0-9]+)['"]?\s*[,)]/
}
