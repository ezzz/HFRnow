import Foundation

/// A video link of a message that can be shown inline; the embed URL is built by the parser, never copied from the page.
public struct MessageEmbed: Sendable, Hashable, Codable {
    /// Host of the video.
    public var provider: EmbedProvider
    /// Original link posted in the message.
    public var sourceURL: URL
    /// Player URL built from the extracted video id.
    public var embedURL: URL
    /// Start offset in seconds, when the link carries one.
    public var startSeconds: Int?

    /// Creates an embed.
    public init(provider: EmbedProvider, sourceURL: URL, embedURL: URL, startSeconds: Int? = nil) {
        self.provider = provider
        self.sourceURL = sourceURL
        self.embedURL = embedURL
        self.startSeconds = startSeconds
    }
}
