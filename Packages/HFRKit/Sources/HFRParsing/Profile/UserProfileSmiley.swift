import Foundation

/// A personal smiley listed on a profile (`[:pseudo:1]` and its image under `/images/perso/`).
public struct UserProfileSmiley: Sendable, Hashable, Identifiable {
    /// Opaque stable key `smiley|<code>|<image URL>`.
    public var id: String
    /// Code to type in a message, e.g. `[:user3:1]`; built from the title when the page prints none.
    public var code: String
    /// Absolute `http(s)` URL of the image.
    public var imageURL: URL
    /// `title` attribute of the image, else its `alt`; nil when it has neither.
    public var title: String?

    /// Creates a value; used by the parser and by tests.
    public init(id: String, code: String, imageURL: URL, title: String?) {
        self.id = id
        self.code = code
        self.imageURL = imageURL
        self.title = title
    }
}
