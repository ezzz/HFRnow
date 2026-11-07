import Foundation
/// One GIF of a Giphy answer: only what the captures `T40`/`T41` show and the picker needs.
public struct GiphyGIF: Sendable, Equatable, Identifiable {
    /// Giphy's id (`data[].id`).
    public let id: String
    /// Giphy's title (`data[].title`, may be empty).
    public let title: String
    /// `data[].rating`: the GIF's own rating, at or below the one asked for.
    public let rating: String?
    /// `images.original.url`, as served: legacy posts `images.original.gifUrl` (`AnswerView.swift:2333` @ 2440d79).
    /// Its query holds Giphy's tracking values (`cid`, `ep`, `rid`, `ct`), `cid` derived from the API key.
    public let originalURL: URL
    /// `images.original` size in points, from the strings the API sends.
    public let originalWidth: Int?
    /// See `originalWidth`.
    public let originalHeight: Int?
    /// `images.fixed_width_small.url`, a small animated rendition for the picker grid, if present.
    public let previewURL: URL?

    /// `originalURL` without its query, so a posted `[img]` link does not carry the key-derived `cid`.
    /// Whether the CDN serves the query-less URL is not captured (pending): `originalURL` is the verified form.
    public var originalURLWithoutTracking: URL {
        var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url ?? originalURL
    }
}

/// A page of results with Giphy's `pagination` block.
public struct GiphyPage: Sendable, Equatable {
    /// The GIFs of this page, in Giphy's order. An item without `id` or a usable `images.original.url` is dropped.
    public let items: [GiphyGIF]
    /// `pagination.total_count`, when present.
    public let totalCount: Int?
    /// `pagination.offset`, when present.
    public let offset: Int?
}
