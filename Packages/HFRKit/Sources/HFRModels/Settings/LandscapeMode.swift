/// The `landscape_mode` setting: where rotation is allowed.
public enum LandscapeMode: String, Sendable, Codable, CaseIterable {
    /// Landscape allowed in the message gallery (default).
    case galerieMessage = "galerie_message"
    /// Portrait only.
    case none
}
