/// Size variant of an uploaded image.
public enum RehostImageVariant: String, Sendable, Codable {
    /// The uploaded image.
    case full
    /// Medium rendition.
    case medium
    /// Thumbnail rendition.
    case mini
}
