/// A titled block of a public profile (`tr.cBackHeader` and the rows that follow it).
public struct UserProfileSection: Sendable, Hashable, Identifiable {
    /// Opaque stable key `section|<title>|<index>`; the index counts the sections opened before it, including ones later
    /// dropped for having no field (legacy numbering).
    public var id: String
    /// Header text, e.g. `Informations générales`.
    public var title: String
    /// Label and value rows, in page order. Link-only rows are in `UserProfile.actions` instead.
    public var fields: [UserProfileField]

    /// Creates a value; used by the parser and by tests.
    public init(id: String, title: String, fields: [UserProfileField]) {
        self.id = id
        self.title = title
        self.fields = fields
    }
}
