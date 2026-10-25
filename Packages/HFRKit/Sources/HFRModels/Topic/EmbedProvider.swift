/// Video hosts for which the parser builds an embed URL (allow-list, ADR 0006 amendment 1).
public enum EmbedProvider: String, Sendable, Codable {
    /// youtube.com and youtu.be links.
    case youtube
    /// vimeo.com links.
    case vimeo
    /// streamable.com links.
    case streamable
}
