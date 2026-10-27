/// A headline figure of a profile, picked from its fields (legacy `UserProfileSummaryItem`).
public struct UserProfileSummaryItem: Sendable, Hashable, Identifiable {
    /// Which field it comes from. Titles and icons are display choices left to the app (legacy stored them).
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// "Nombre de messages postés".
        case messageCount
        /// "Date d'arrivée sur le forum".
        case joinDate
        /// "Date du dernier message".
        case lastMessageDate

        /// Title of the profile row this kind reads.
        var fieldTitle: String {
            switch self {
            case .messageCount: "Nombre de messages postés"
            case .joinDate: "Date d'arrivée sur le forum"
            case .lastMessageDate: "Date du dernier message"
            }
        }
    }

    /// The field this item shows.
    public var kind: Kind
    /// The field's text as printed; never empty.
    public var value: String

    /// Stable key, the kind's name.
    public var id: String { kind.rawValue }

    /// Creates a value; used by the parser and by tests.
    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }
}
