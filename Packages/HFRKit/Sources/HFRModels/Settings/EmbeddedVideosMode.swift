/// The `embedded_videos` setting: how video links are shown. Raw values are the legacy defaults strings.
public enum EmbeddedVideosMode: String, Sendable, Codable, CaseIterable {
    /// Links only.
    case never = "no"
    /// Inline player only.
    case inlinePlayer = "yes"
    /// Inline player and the link.
    case playerAndLink = "both"
}
