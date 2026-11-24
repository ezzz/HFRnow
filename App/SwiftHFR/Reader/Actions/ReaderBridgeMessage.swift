import CoreGraphics
import Foundation

// Port of HFRswift/Swift/MessagesView.swift (`Coordinator.userContentController(_:didReceive:)`, `:1169-1235`) @ 2440d79.
// Differences: GAP-064; the body is decoded into a closed enum and rejected whole when it does not fit, where legacy read
// untyped values and ignored bad shapes silently.

/// A message of `reader.js`, decoded into a closed set of cases (LOT-087, audit C14). The page never supplies code or a
/// selector: the decoder knows a fixed set of names and takes only numbers and strings of the shape each one needs; anything else
/// is rejected, never partly read.
enum ReaderBridgeMessage: Equatable, Sendable {
    /// `src` of every image of the document, in order; an entry that is not a string is kept as nil (blocked).
    case images([String?])
    /// The user tapped the placeholder of a third-party image.
    case tap(url: String)
    /// The document reached DOMContentLoaded and its images were routed.
    case ready
    /// The user tapped a YouTube thumbnail card or the plain link it belongs to (#1037): the link as the page holds it, a claim
    /// the app checks again before opening it.
    case videoLink(url: String)
    /// The user tapped the placeholder of video `index` of message `post`.
    case video(post: Int, index: Int)
    /// The user tapped the menu button (`message`) or the author (`avatar`) of message `post`.
    /// `anchor` is the button's rectangle in the page's viewport (CSS points); nil when the page sent none or a bad one.
    case menu(post: Int, source: MessageMenuSource, anchor: CGRect?)
    /// Scrolling paused with message `post` topmost (LOT-111: recorded as the reading position).
    case position(post: Int)

    /// The user chose "Citer extrait" (`bold` false) or "Citer gras" over `text`, selected inside message `post` (LOT-086). The
    /// page's `text` is a claim: the app only hands it to the quote formatter, never to the page or the network.
    case quote(post: Int, text: String, bold: Bool)

    /// The user tapped a posted picture: the `src` of the pictures the page shows (in order) and the tapped one's position
    /// among them (LOT-109), and the `href` of the link around the tapped one, nil when it is in none (#912). The app re-checks
    /// every entry and decides what the link means; the page's list and link are claims.
    case image(urls: [String], index: Int, link: String? = nil)

    /// The page's end came on screen (`atBottom`) or left it: legacy's `scrollState` message (`MessagesView.swift:1013-1035`
    /// @ 87fe0d1c), sent only on a change. It drives the end-of-page bar (#820).
    case edge(atBottom: Bool)

    /// A touch started inside a block that scrolls sideways (`inside`) or outside any (legacy's `horizontalScrollTouch`,
    /// `MessagesView.swift:1102-1142` @ 87fe0d1c, #672), sent only on a change: the page swipe ignores a drag that began in one.
    case scroller(inside: Bool)

    /// Why a body was rejected.
    enum Failure: Error, Equatable, Sendable {
        /// The body is not a dictionary, or has no string `type` and integer `token`.
        case malformed
        /// A name this decoder does not know.
        case unknownType
        /// A known name with a missing field or a field of the wrong type or range.
        case invalidPayload
    }

    /// The document token and the message of a raw body.
    struct Decoded: Equatable, Sendable {
        /// The document the message says it comes from.
        var token: Int
        /// The message.
        var message: ReaderBridgeMessage
    }

    /// Longest selection kept, in characters: a message holds far less, so a longer one is not a selection of it.
    static let maximumQuoteText = 20_000

    /// Longest link taken from the page, in bytes: browsers and servers refuse far less, so more is not a video link.
    static let maximumLinkLength = 2_048

    /// Most array entries read from one body: the images of a page, as the controller already caps them.
    static let maximumImages = 5_000

    /// Decodes the body `reader.js` posted (a JSON-like object from WebKit).
    static func decode(_ body: Any) throws(Failure) -> Decoded {
        guard let object = body as? [String: Any], let type = object["type"] as? String,
              let token = integer(object["token"]) else { throw .malformed }
        return Decoded(token: token, message: try message(ofType: type, in: object))
    }

    private static func message(ofType type: String, in object: [String: Any]) throws(Failure) -> ReaderBridgeMessage {
        switch type {
        case "images":
            guard let urls = object["urls"] as? [Any] else { throw .invalidPayload }
            return .images(urls.prefix(maximumImages).map { $0 as? String })
        case "tap":
            guard let url = object["url"] as? String else { throw .invalidPayload }
            return .tap(url: url)
        case "ready":
            return .ready
        case "videolink":
            guard let url = object["url"] as? String, url.utf8.count <= maximumLinkLength else { throw .invalidPayload }
            return .videoLink(url: url)
        case "edge":
            guard let atBottom = boolean(object["bottom"]) else { throw .invalidPayload }
            return .edge(atBottom: atBottom)
        case "scroller":
            guard let inside = boolean(object["inside"]) else { throw .invalidPayload }
            return .scroller(inside: inside)
        default:
            return try messageAboutAPost(ofType: type, in: object)
        }
    }

    /// The names whose payload starts with a message number.
    private static func messageAboutAPost(ofType type: String, in object: [String: Any]) throws(Failure) -> ReaderBridgeMessage {
        switch type {
        case "video":
            return try video(in: object)
        case "menu":
            guard let post = positivePost(in: object), let name = object["source"] as? String,
                  let source = MessageMenuSource(rawValue: name) else { throw .invalidPayload }
            return .menu(post: post, source: source, anchor: anchor(in: object))
        case "image":
            return try image(in: object)
        case "quote":
            return try quote(in: object)
        case "position":
            guard let post = positivePost(in: object) else { throw .invalidPayload }
            return .position(post: post)
        default:
            throw .unknownType
        }
    }

    /// Largest coordinate or size taken from the page, in points: a viewport is far smaller, so more is not a button's rectangle.
    static let maximumAnchorExtent = 100_000.0

    /// The rectangle `x`, `y`, `width`, `height` of a body: real numbers (never booleans), finite, within
    /// `maximumAnchorExtent` and with no negative size. Anything else gives nil: the menu then opens unanchored.
    static func anchor(in object: [String: Any]) -> CGRect? {
        guard let x = number(object["x"]), let y = number(object["y"]), let width = number(object["width"]),
              let height = number(object["height"]), width >= 0, height >= 0,
              [x, y, width, height].allSatisfy({ abs($0) <= maximumAnchorExtent }) else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func video(in object: [String: Any]) throws(Failure) -> ReaderBridgeMessage {
        guard let post = positivePost(in: object), let index = integer(object["index"]), index >= 0 else {
            throw .invalidPayload
        }
        return .video(post: post, index: index)
    }

    private static func quote(in object: [String: Any]) throws(Failure) -> ReaderBridgeMessage {
        guard let post = positivePost(in: object), let text = object["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maximumQuoteText,
              let bold = boolean(object["bold"]) else { throw .invalidPayload }
        return .quote(post: post, text: text, bold: bold)
    }

    private static func image(in object: [String: Any]) throws(Failure) -> ReaderBridgeMessage {
        guard let list = object["urls"] as? [Any], list.count <= maximumImages, let index = integer(object["index"]),
              index >= 0, index < list.count else { throw .invalidPayload }
        // One entry that is not a string rejects the whole message: the index must keep pointing at the same picture.
        let urls = list.compactMap { $0 as? String }
        guard urls.count == list.count else { throw .invalidPayload }
        // `link` is absent or null outside a link; any other type rejects the message rather than reading a tap as unlinked.
        let link: String?
        switch object["link"] {
        case nil, is NSNull: link = nil
        case let text as String: link = text.utf8.count <= maximumLinkLength ? text : nil
        default: throw .invalidPayload
        }
        return .image(urls: urls, index: index, link: link)
    }

    /// The message number a body names: a whole number above zero, nothing else.
    private static func positivePost(in object: [String: Any]) -> Int? {
        integer(object["post"]).flatMap { $0 > 0 ? $0 : nil }
    }

    /// A real boolean from WebKit's bridge: `1` and `0` are numbers, not booleans.
    private static func boolean(_ value: Any?) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A finite real number from WebKit's bridge: an `NSNumber` that is not a boolean.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite
        else { return nil }
        return number.doubleValue
    }

    /// A whole number from WebKit's bridge: an `NSNumber` that is not a boolean and has no fraction; nothing else.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double == double.rounded(), abs(double) < 9_007_199_254_740_992 else { return nil }
        return number.intValue
    }
}

extension ReaderBridgeMessage {
    /// A tap that opens something, dropped under an open composer (#653): a menu, a video, the image viewer, or a quote of the
    /// selection (the `tap` of a third-party placeholder answers with a consent and is handled on its own).
    var isTapAction: Bool {
        switch self {
        case .menu, .video, .videoLink, .image, .quote: true
        case .images, .tap, .ready, .position, .edge, .scroller: false
        }
    }
}
