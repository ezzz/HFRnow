/// Whether a topic row announces unread replies; favourites rows carry no such information.
public enum TopicReadState: String, Sendable, Codable {
    /// The row shows no unread marker.
    case read
    /// The row shows the unread marker (`sujetCase1` image with `alt="On"`).
    case unread
    /// The page this row comes from does not expose the read state.
    case unknown
}
