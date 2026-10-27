import Foundation
import HFRModels
import SwiftSoup

/// Turns the raw content of a message block into the display-independent `MessageContent` of ADR 0006:
/// sanitized HTML rendered from a new allow-listed tree, the signature split out, and the typed lists of images,
/// smileys and links the app reads instead of re-parsing.
///
/// Port of the content part of `LinkItem.toHTML:isMP:` (`LinkItem.m:72-74, 96-141, 163-247, 265-269`), which rewrote
/// libxml2's serialization with regexes and inserted the result unescaped into the web view (audit C §4.2, quirks 1–3).
/// Policy and display modes (`display_images`, `display_sig`, blacklist quotes) stay app-side; video embeds are LOT-035.
public enum MessageContentNormalizer {
    /// Normalizes `MessageBlock.contentHTML`; `page` resolves relative and fragment-only links (the forum root by default).
    /// Only a backend failure throws.
    public static func normalize(contentHTML: String, relativeTo page: URL = HFRURL.base) throws(ParsingError) -> MessageContent {
        guard let body = (try? SwiftSoup.parseBodyFragment(contentHTML))?.body() else { throw .malformedDocument }
        return try normalize(body, relativeTo: page)
    }

    /// Same from the content element of an `ExtractedMessageBlock`; the source tree is read, never mutated.
    static func normalize(_ content: Element, relativeTo page: URL) throws(ParsingError) -> MessageContent {
        guard let builder = Builder(page: page) else { throw .malformedDocument }
        builder.copy(childrenOf: content)
        return try builder.result()
    }

    // MARK: - Allow-lists (the sanitization contract of ADR 0006)

    /// Elements copied with their children.
    static let keptTags: Set<String> = [
        "p", "br", "b", "strong", "i", "em", "u", "s", "strike", "span", "a", "img", "table", "tbody", "tr", "td", "th",
        "div", "ol", "ul", "li", "blockquote", "pre", "code", "hr", "sub", "sup"
    ]
    /// Elements dropped together with their content; every other unknown element is unwrapped.
    static let droppedTags: Set<String> = [
        "script", "style", "iframe", "object", "embed", "applet", "template", "noscript", "svg", "math", "form", "input",
        "button", "select", "textarea", "link", "meta", "base", "frame", "frameset", "video", "audio", "source", "track",
        "canvas", "head", "title"
    ]
    /// Class tokens kept: the HFR markup the legacy stylesheet relies on, plus the two legacy hooks the normalizer adds.
    static let keptClasses: Set<String> = [
        "cLink", "Topic", "citation", "oldcitation", "quote", "spoiler", "code", "fixed", "container", "masque", "s1", "s1Topic",
        "signature", "u", "olcode", "none", imageClass, customSmileyClass
    ]
    /// Legacy class of a message image (`LinkItem.m:173`).
    static let imageClass = "hfrplusimg"
    /// Legacy class of a personal smiley (`LinkItem.m:124`).
    static let customSmileyClass = "smileycustom"
    /// Host of every smiley (`LinkItem.m:105, 139`).
    static let smileyHost = "forum-images.hardware.fr"

    /// Absolute http(s) URL of a raw `href`/`src` with the content rules: `http` upgraded to `https` on `*.hardware.fr`
    /// (ADR 0006 amendment 1) and the `hfr-rehost.net` host written `reho.st` (`LinkItem.m:163`); nil when not a link to keep.
    static func normalizedURL(_ raw: String, relativeTo page: URL) -> URL? {
        guard
            let absolute = HFRURL.absolute(raw, relativeTo: page),
            var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false),
            let host = components.host
        else { return nil }
        if components.scheme == "http", components.port == nil, host == "hardware.fr" || host.hasSuffix(".hardware.fr") {
            components.scheme = "https"
        }
        let rehost = "hfr-rehost.net"
        if host == rehost {
            components.host = "reho.st"
        } else if host.hasSuffix("." + rehost) {
            components.host = String(host.dropLast(rehost.count)) + "reho.st"
        }
        return components.url
    }

    /// Standard (`/icones/…`) or personal (`/images/perso/…`) smiley, by host and path; nil for any other image.
    static func smileyKind(of url: URL) -> MessageSmiley.Kind? {
        guard url.host(percentEncoded: false) == smileyHost else { return nil }
        let path = url.path(percentEncoded: false)
        if path.hasPrefix("/icones/") { return .standard }
        if path.hasPrefix("/images/perso/") { return .custom }
        return nil
    }

    /// A free-text attribute value (`alt`, `title`) without `<` and `>`: SwiftSoup escapes `&` and `"` there but writes
    /// angle brackets raw, and the output must stay inert wherever the app's builder puts it (defense in depth).
    static func attributeText(_ value: String) -> String {
        value.filter { $0 != "<" && $0 != ">" }
    }

    // MARK: - Tree builder

    /// Copies the allowed parts of the source tree into a fresh document and collects the typed lists on the way.
    ///
    /// The walk is iterative (an explicit stack of steps): a post can nest tags thousands deep, and a recursive copy
    /// would overflow the 512 KB stack of a background thread long before SwiftSoup's own parser gives up. The tree is
    /// assembled bottom-up for the same reason: a copied element joins its parent only once its children are in place,
    /// so every `appendChild` runs on a detached root (SwiftSoup walks up to the owner document recursively on append).
    private final class Builder {
        /// One unit of work: copy a source node under a target, or finish a copied element once its children are copied.
        private enum Step {
            case copy(Node, into: Element, inSignature: Bool)
            case finishElement(Element, into: Element)
            case finishLink(Element, into: Element, URL, inSignature: Bool)
        }

        let page: URL
        let document: Document
        /// Root of the body HTML.
        let main: Element
        /// Root of the signature HTML; nil until a `span.signature` is met.
        private(set) var signature: Element?
        private var images: [MessageImage] = []
        private var smileys: [MessageSmiley] = []
        private var links: [MessageLink] = []
        /// The image copied last, to attach the link that wraps it.
        private var lastImage: (element: Element, index: Int)?
        /// Pending steps, last in first out, so children are copied in document order right after their parent.
        private var pending: [Step] = []

        init?(page: URL) {
            self.page = page
            document = Document.createShell("")
            // The output is handed to the app's builder as is: pretty-printing would add newlines inside code blocks.
            document.outputSettings().prettyPrint(pretty: false)
            guard let body = document.body(), let main = Self.element("div"), (try? body.appendChild(main)) != nil else {
                return nil
            }
            self.main = main
        }

        func result() throws(ParsingError) -> MessageContent {
            guard let html = try? main.html() else { throw .malformedDocument }
            var signatureHTML: String?
            if let signature {
                guard let text = try? signature.html() else { throw .malformedDocument }
                // A signature span without content (or with dropped content only) is no signature.
                signatureHTML = text.isEmpty ? nil : text
            }
            return MessageContent(html: html, signatureHTML: signatureHTML, images: images, smileys: smileys, links: links)
        }

        /// Copies every child of `content` under `main`, running the step stack to completion.
        func copy(childrenOf content: Element) {
            schedule(childrenOf: content, into: main, inSignature: false)
            while let step = pending.popLast() {
                switch step {
                case .copy(let node, let target, let inSignature):
                    copy(node, into: target, inSignature: inSignature)
                case .finishElement(let element, let target):
                    // HFR writes `<p></p>` before quote blocks and the tree builder makes one of its stray `</p>`.
                    guard element.tagName() != "p" || element.childNodeSize() > 0 else { break }
                    append(element, to: target)
                case .finishLink(let link, let target, let url, let inSignature):
                    finishLink(link, into: target, url: url, inSignature: inSignature)
                }
            }
        }

        private func schedule(childrenOf source: Element, into target: Element, inSignature: Bool) {
            for node in source.getChildNodes().reversed() {
                pending.append(.copy(node, into: target, inSignature: inSignature))
            }
        }

        private func copy(_ node: Node, into target: Element, inSignature: Bool) {
            if let text = node as? TextNode {
                append(TextNode(text.getWholeText(), nil), to: target)
                return
            }
            // Comments, data, declarations: nothing of them reaches the output.
            guard let source = node as? Element else { return }
            let tag = source.tagName()
            guard !droppedTags.contains(tag) else { return }
            let classes = Self.classTokens(of: source)
            switch tag {
            case "div" where classes.contains("edited") || Self.isClearTrailer(source, classes: classes):
                // The LOT-030 trailer and HFR's layout trailer sit inside the content element; neither is content.
                return
            case "span" where classes.contains("signature"):
                copySignature(source, inSignature: inSignature)
            case "a":
                copyLink(source, into: target, inSignature: inSignature)
            case "img":
                copyImage(source, into: target, inSignature: inSignature)
            case _ where keptTags.contains(tag):
                copyElement(source, classes: classes, into: target, inSignature: inSignature)
            default:
                // Unknown element: unwrapped, its children stay in place.
                schedule(childrenOf: source, into: target, inSignature: inSignature)
            }
        }

        /// An allow-listed element: its kept classes, a colour on `span`, then its children; an empty `<p>` is dropped.
        private func copyElement(_ source: Element, classes: [String], into target: Element, inSignature: Bool) {
            let tag = source.tagName()
            guard let copy = Self.element(tag) else { return }
            setClass(classes, on: copy)
            if tag == "span", let color = Self.color(in: source) {
                set("style", "color:\(color)", on: copy)
            }
            pending.append(.finishElement(copy, into: target))
            schedule(childrenOf: source, into: copy, inSignature: inSignature)
        }

        /// The first `span.signature` becomes the signature; legacy cut the string there, so later ones are dropped too,
        /// as is a signature span nested inside the first.
        private func copySignature(_ source: Element, inSignature: Bool) {
            guard signature == nil, !inSignature, let root = Self.element("div"), let body = document.body() else { return }
            append(root, to: body)
            signature = root
            schedule(childrenOf: source, into: root, inSignature: true)
        }

        /// A link with a rejected URL is unwrapped: its text stays, the element goes (ADR 0006 amendment 1).
        private func copyLink(_ source: Element, into target: Element, inSignature: Bool) {
            guard
                let href = try? source.attr("href"), let url = normalizedURL(href, relativeTo: page),
                let copy = Self.element("a")
            else {
                schedule(childrenOf: source, into: target, inSignature: inSignature)
                return
            }
            set("href", url.absoluteString, on: copy)
            copyText("title", from: source, to: copy)
            setClass(Self.classTokens(of: source), on: copy)
            pending.append(.finishLink(copy, into: target, url, inSignature: inSignature))
            schedule(childrenOf: source, into: copy, inSignature: inSignature)
        }

        /// Once its children are copied: a link around an image is the image's target, not a link of its own
        /// (legacy `longdesc`); any other link joins the list with its visible text. Then the link joins its parent.
        private func finishLink(_ link: Element, into target: Element, url: URL, inSignature: Bool) {
            if let image = lastImage, Self.wrapsOnly(image.element, link) {
                images[image.index].linkURL = url
            } else {
                links.append(MessageLink(url: url, text: (try? link.text()) ?? "", isInSignature: inSignature))
            }
            append(link, to: target)
        }

        /// An image with a rejected URL is removed (ADR 0006 amendment 1); smileys and images go to their lists.
        private func copyImage(_ source: Element, into target: Element, inSignature: Bool) {
            guard
                let src = try? source.attr("src"), let url = normalizedURL(src, relativeTo: page),
                let copy = Self.element("img")
            else { return }
            set("src", url.absoluteString, on: copy)
            let alt = (try? source.attr("alt")) ?? ""
            set("alt", attributeText(alt), on: copy)
            copyText("title", from: source, to: copy)
            if let kind = smileyKind(of: url) {
                smileys.append(MessageSmiley(code: alt, url: url, kind: kind))
                if kind == .custom {
                    set("class", customSmileyClass, on: copy)
                }
            } else {
                images.append(MessageImage(url: url, altText: alt, isInSignature: inSignature))
                set("class", imageClass, on: copy)
                lastImage = (copy, images.count - 1)
            }
            append(copy, to: target)
        }

        // MARK: Helpers

        private static func element(_ tag: String) -> Element? {
            guard let tag = try? Tag.valueOf(tag) else { return nil }
            return Element(tag, "")
        }

        private func append(_ node: Node, to parent: Element) {
            _ = try? parent.appendChild(node)
        }

        private func set(_ attribute: String, _ value: String, on element: Element) {
            _ = try? element.attr(attribute, value)
        }

        /// Copies a free-text attribute (`title`), angle brackets removed; absent or empty attributes are not copied.
        private func copyText(_ attribute: String, from source: Element, to target: Element) {
            guard source.hasAttr(attribute), let value = try? source.attr(attribute), !value.isEmpty else { return }
            set(attribute, attributeText(value), on: target)
        }

        private func setClass(_ tokens: [String], on element: Element) {
            let kept = tokens.filter { keptClasses.contains($0) }
            guard !kept.isEmpty else { return }
            set("class", kept.joined(separator: " "), on: element)
        }

        /// Class tokens split as HTML does (ASCII whitespace), in source order.
        private static func classTokens(of element: Element) -> [String] {
            guard element.hasAttr("class"), let value = try? element.attr("class") else { return [] }
            return value.htmlClassTokens.map(String.init)
        }

        /// `<div style="clear: both;"> </div>`: HFR's layout trailer, a div without class, that style only, whitespace inside.
        private static func isClearTrailer(_ element: Element, classes: [String]) -> Bool {
            guard
                classes.isEmpty, element.hasAttr("style"), let style = try? element.attr("style"),
                style.wholeMatch(of: clearPattern) != nil
            else { return false }
            return element.getChildNodes().allSatisfy { ($0 as? TextNode)?.getWholeText().allSatisfy(\.isWhitespace) ?? false }
        }

        /// The colour of a `style` holding exactly one `color` declaration with a hex or named value; nil otherwise.
        private static func color(in element: Element) -> String? {
            guard element.hasAttr("style"), let style = try? element.attr("style") else { return nil }
            return style.wholeMatch(of: colorPattern).map { String($0.output.1) }
        }

        /// Whether `link` holds `image` as its only element child and no other text than whitespace.
        private static func wrapsOnly(_ image: Element, _ link: Element) -> Bool {
            let children = link.children()
            guard children.count == 1, children.first === image else { return false }
            return link.ownRawText.allSatisfy(\.isWhitespace)
        }

        // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). These literals capture
        // only `Substring`s and the compiled program is initialised atomically by the runtime, so sharing is safe.
        nonisolated(unsafe) private static let clearPattern = /\s*clear\s*:\s*both\s*;?\s*/.ignoresCase()
        nonisolated(unsafe) private static let colorPattern =
            /\s*color\s*:\s*(#[0-9a-fA-F]{6}|#[0-9a-fA-F]{3}|[a-zA-Z]{1,20})\s*;?\s*/.ignoresCase()
    }
}
