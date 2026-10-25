/// Normalised, display-independent content of one message (ADR 0006): sanitised HTML plus typed lists.
public struct MessageContent: Sendable, Hashable, Codable {
    /// Sanitised content HTML, signature excluded.
    public var html: String
    /// Sanitised signature HTML, nil when the message has none.
    public var signatureHTML: String?
    /// Images in document order.
    public var images: [MessageImage]
    /// Smileys in document order.
    public var smileys: [MessageSmiley]
    /// Links in document order.
    public var links: [MessageLink]
    /// Inline-able video links in document order.
    public var embeds: [MessageEmbed]

    /// Creates message content.
    public init(
        html: String,
        signatureHTML: String? = nil,
        images: [MessageImage] = [],
        smileys: [MessageSmiley] = [],
        links: [MessageLink] = [],
        embeds: [MessageEmbed] = []
    ) {
        self.html = html
        self.signatureHTML = signatureHTML
        self.images = images
        self.smileys = smileys
        self.links = links
        self.embeds = embeds
    }
}
