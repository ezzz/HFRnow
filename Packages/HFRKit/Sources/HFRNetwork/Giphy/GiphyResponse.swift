import Foundation
/// Decoder of Giphy's `{data, meta, pagination}` envelope, limited to the fields `T40`/`T41` show.
enum GiphyResponse {
    /// The page, or nil when `body` is not the envelope.
    static func decode(_ body: Data) -> GiphyPage? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return nil }
        return GiphyPage(
            items: envelope.data.compactMap { $0.value.flatMap(gif) },
            totalCount: envelope.pagination?.value?.totalCount,
            offset: envelope.pagination?.value?.offset
        )
    }

    private static func gif(_ item: Item) -> GiphyGIF? {
        guard !item.id.isEmpty, let original = webURL(item.images.original.url) else { return nil }
        return GiphyGIF(
            id: item.id, title: item.title ?? "", rating: item.rating, originalURL: original,
            originalWidth: item.images.original.width.flatMap { Int($0) },
            originalHeight: item.images.original.height.flatMap { Int($0) },
            previewURL: item.images.fixedWidthSmall.flatMap { webURL($0.url) }
        )
    }

    /// Only an absolute `https` URL with a host: the link is posted into a message, so `javascript:` or `http` is not kept.
    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

private struct Envelope: Decodable {
    let data: [Throwable<Item>]
    let pagination: Throwable<Pagination>?
}

private struct Pagination: Decodable {
    let totalCount: Int?
    let offset: Int?
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case offset
    }
}

private struct Item: Decodable {
    let id: String
    let title: String?
    let rating: String?
    let images: Images
}

private struct Images: Decodable {
    let original: Rendition
    let fixedWidthSmall: Rendition?
    enum CodingKeys: String, CodingKey {
        case original
        case fixedWidthSmall = "fixed_width_small"
    }
}

/// Sizes are strings in the captures; `url` is the only required field.
private struct Rendition: Decodable {
    let url: String
    let width: String?
    let height: String?
}

/// Decodes one element without failing its container.
private struct Throwable<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}
