import Foundation
import HFRModels
import SwiftSoup

/// What HFR's own preview form takes besides the text (`apercu_form`: `apercu_smiley`), plus the smiley codes the
/// renderer may substitute.
public struct BBCodeRenderOptions: Sendable, Hashable {
    /// Whether smiley codes become images: the composer's `smiley` checkbox read as HFR does (checked = disabled,
    /// HFR-PROTOCOL §6b "Checkbox values"), sent to HFR's preview as `apercu_smiley`.
    public var smileysEnabled: Bool
    /// Smiley codes as typed (`:)`, `:ange:`, `[:user]`, `[:user:1]`) and their image URLs: the catalogue of
    /// `CommonSmileyCatalog` plus the member's personal smileys, built by the app. ASCII letters of a code are matched
    /// whatever their case, anywhere but from a URL (`http://`, `https://`, `www.`) to the end of its word; the image's
    /// `alt` is the text as typed and its `title` the code of the table (`R42` → `R20`: `alt=":d" title=":D"`).
    public var smileys: [String: URL] {
        didSet { trie = HFRBBCodeWriter.trie(for: smileys) }
    }
    /// The table prepared for the writer, once per table rather than once per preview; always derived from `smileys`.
    private(set) var trie: HFRBBCodeWriter.SmileyTrie

    /// Creates the options; by default smileys are on, as in a fresh composer, and no code is known.
    public init(smileysEnabled: Bool = true, smileys: [String: URL] = [:]) {
        self.smileysEnabled = smileysEnabled
        self.smileys = smileys
        trie = HFRBBCodeWriter.trie(for: smileys)
    }

    // The trie is derived from `smileys`: equality and hashing read the two public values only, so a comparison per
    // keystroke costs the table, not the trie.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.smileysEnabled == rhs.smileysEnabled && lhs.smileys == rhs.smileys
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(smileysEnabled)
        hasher.combine(smileys)
    }
}

/// Renders a message source (BBCode, as the composer sends it) into the `MessageContent` the reader will show once the
/// message is posted (ADR 0014, LOT-097).
///
/// The source becomes the HTML string HFR itself renders for the tags the captured pairs prove (`W61` / `R95d`,
/// `R41a` / `R20`), parsed on the reader's own path: inside the thread page's markup (`td > div#para…`, the clear
/// trailer last), serialized back as `MessageBlockParser.contentHTML`, then `MessageContentNormalizer`, the sanitizer
/// of record. One rendering path, one stylesheet, one image policy for the preview and for posted messages. Everything
/// the pairs do not prove is text, as HFR does with `[color=…]`, `[list]` and an unclosed tag. No I/O, no request.
public enum BBCodeRenderer {
    /// The content of `source` as the reader will show it. Line breaks are read as the posting flow sends them (CRLF,
    /// whatever the source holds); characters above U+FFFF are text (the posting flow refuses them before sending).
    /// `page` resolves relative links as the reader will, against the topic page the message is posted to.
    /// Only a backend failure throws.
    public static func render(
        _ source: String, options: BBCodeRenderOptions = BBCodeRenderOptions(), relativeTo page: URL = HFRURL.base
    ) throws(ParsingError) -> MessageContent {
        let writer = HFRBBCodeWriter(smileysEnabled: options.smileysEnabled, smileys: options.trie)
        return try MessageContentNormalizer.normalize(contentHTML: contentHTML(for: writer.html(for: source)), relativeTo: page)
    }

    /// `html` parsed where a posted message sits on the thread page and serialized back as `MessageBlockParser` does,
    /// so the normalizer parses it a second time as it parses a posted message: the first serialization of a crossed
    /// `<span><strong>x</span></strong>` loses a `</strong>` that the second parse reopens, and the preview must get the
    /// reader's repair (one parse, or a string ending with an explicit `</p>`, gives another tree).
    static func contentHTML(for html: String) throws(ParsingError) -> String {
        let page = "<html><body><table><tr><td><div id=\"para0\">" + html
            + "<div style=\"clear: both;\"> </div></div></td></tr></table></body></html>"
        let document = try HTMLDocumentLoader.document(from: page)
        document.outputSettings().prettyPrint(pretty: false)
        guard let content = try? document.getElementById("para0"), let contentHTML = try? content.html() else {
            throw .malformedDocument
        }
        return contentHTML
    }
}
