import Foundation
import HFRModels
/// Keys of the `image` object; a file-level type keeps `RehostResponse` within the nesting limit.
private enum RehostImageKey: String, CodingKey { case url, width, height, medium, thumb }

/// The JSON the Chevereto v1 upload endpoint answers, read as legacy did (`ReplyService.swift:2002-2093` @ 2440d79).
struct RehostResponse: Decodable, Sendable {
    struct Rendition: Decodable, Sendable {
        let url: String?
    }

    struct Image: Decodable, Sendable {
        let url: String?
        let width: Int?
        let height: Int?
        let medium: Rendition?
        let thumb: Rendition?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: RehostImageKey.self)
            url = try? container.decode(String.self, forKey: .url)
            width = Self.lenientInt(container, .width)
            height = Self.lenientInt(container, .height)
            medium = try? container.decode(Rendition.self, forKey: .medium)
            thumb = try? container.decode(Rendition.self, forKey: .thumb)
        }

        /// A number written as a JSON number or as a string, as legacy accepted both.
        fileprivate static func lenientInt<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> Int? {
            if let number = try? container.decode(Int.self, forKey: key) { return number }
            if let text = try? container.decode(String.self, forKey: key) { return Int(text) }
            return nil
        }
    }

    struct Message: Decodable, Sendable {
        let message: String?
    }

    let statusCode: Int?
    let error: Message?
    let success: Message?
    let image: Image?

    private enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case error, success, image
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = Image.lenientInt(container, .statusCode)
        error = try? container.decode(Message.self, forKey: .error)
        success = try? container.decode(Message.self, forKey: .success)
        image = try? container.decode(Image.self, forKey: .image)
    }

    /// The host's own explanation: the error message first, then the success message, empty ones ignored.
    var message: String? {
        [error?.message, success?.message].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// Reads a body; `nil` when it is not a JSON object.
    static func decode(_ data: Data) -> RehostResponse? {
        try? JSONDecoder().decode(RehostResponse.self, from: data)
    }

    /// The hosted image, or `nil` when the payload holds no usable full URL. Renditions with a bad URL are dropped.
    func hostedImage(uploadedAt: Date) -> RehostedImage? {
        guard let full = Self.webURL(image?.url) else { return nil }
        return RehostedImage(
            fullURL: full, mediumURL: Self.webURL(image?.medium?.url), miniURL: Self.webURL(image?.thumb?.url),
            width: image?.width, height: image?.height, uploadedAt: uploadedAt
        )
    }

    /// An absolute `http(s)` URL with a host; the text goes into a post, so nothing else is accepted.
    private static func webURL(_ text: String?) -> URL? {
        guard let text, !text.isEmpty, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}
