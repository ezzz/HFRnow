import Foundation

/// One entry of the bundled catalogue of standard smileys (`commonsmile.plist` of the legacy app).
public struct CommonSmiley: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: the smiley code, unique in the catalogue.
    public var id: String { code }
    /// Smiley code as typed in a post, e.g. `:)`.
    public var code: String
    /// Image URL on the forum image host.
    public var url: URL
    /// File name of the matching GIF the app may bundle.
    public var resourceName: String
    /// True for the smileys the legacy editor offers in its basic palette.
    public var isEditorSmiley: Bool

    /// Creates a catalogue entry.
    public init(code: String, url: URL, resourceName: String, isEditorSmiley: Bool) {
        self.code = code
        self.url = url
        self.resourceName = resourceName
        self.isEditorSmiley = isEditorSmiley
    }

    private enum CodingKeys: String, CodingKey {
        case code, url
        case resourceName = "resource"
        case isEditorSmiley = "editor"
    }
}
