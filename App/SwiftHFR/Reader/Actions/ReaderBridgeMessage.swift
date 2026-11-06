import Foundation

// Port of HFRswift/Swift/MessagesView.swift (`Coordinator.userContentController(_:didReceive:)`, `:1169-1235`) @ 2440d79.
// Differences: GAP-064; the body is decoded into a closed enum and rejected whole when it does not fit, where legacy read
// untyped values and ignored bad shapes silently.

/// A message of `reader.js`, decoded into a closed set of cases (LOT-087, audit C14). The page never supplies code or a
/// selector: the decoder knows six names and takes only numbers and strings of the shape each one needs; anything else
/// is rejected, never partly read.
enum ReaderBridgeMessage: Equatable, Sendable {
    /// `src` of every image of the document, in order; an entry that is not a string is kept as nil (blocked).
    case images([String?])
    /// The user tapped the placeholder of a third-party image.
    case tap(url: String)
    /// The document reached DOMContentLoaded and its images were routed.
    case ready
    /// The user tapped the placeholder of video `index` of message `post`.
    case video(post: Int, index: Int)
    /// The user tapped the menu button (`message`) or the author (`avatar`) of message `post`.
    case menu(post: Int, source: MessageMenuSource)
    /// Scrolling paused with message `post` topmost (LOT-111: recorded as the reading position).
    case position(post: Int)

    /// The user tapped a posted picture: the `src` of the pictures the page shows (in order) and the tapped one's position
    /// among them (LOT-109). The app re-checks every entry; the page's list is a claim.
    case image(urls: [String], index: Int)

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
            return .menu(post: post, source: source)
        case "image":
            return try image(in: object)
        case "position":
            guard let post = positivePost(in: object) else { throw .invalidPayload }
            return .position(post: post)
        default:
            throw .unknownType
        }
    }

    private static func video(in object: [String: Any]) throws(Failure) -> ReaderBridgeMessage {
        guard let post = positivePost(in: object), let index = integer(object["index"]), index >= 0 else {
            throw .invalidPayload
        }
        return .video(post: post, index: index)
    }

    private static func image(in object: [String: Any]) throws(Failure) -> ReaderBridgeMessage {
        guard let list = object["urls"] as? [Any], list.count <= maximumImages, let index = integer(object["index"]),
              index >= 0, index < list.count else { throw .invalidPayload }
        // One entry that is not a string rejects the whole message: the index must keep pointing at the same picture.
        let urls = list.compactMap { $0 as? String }
        guard urls.count == list.count else { throw .invalidPayload }
        return .image(urls: urls, index: index)
    }

    /// The message number a body names: a whole number above zero, nothing else.
    private static func positivePost(in object: [String: Any]) -> Int? {
        integer(object["post"]).flatMap { $0 > 0 ? $0 : nil }
    }

    /// A whole number from WebKit's bridge: an `NSNumber` that is not a boolean and has no fraction; nothing else.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double == double.rounded(), abs(double) < 9_007_199_254_740_992 else { return nil }
        return number.intValue
    }
}
