import Foundation

/// A link row of a profile: transactions, private message, all messages, hardware configuration.
public struct UserProfileAction: Sendable, Hashable, Identifiable {
    /// What the link does, from the link text (legacy `UserProfileAction.Kind`). Raw values are legacy's keys.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// "Envoyer un message privé à …".
        case privateMessage
        /// "Accéder à la liste de tous ses messages".
        case allMessages
        /// A "liste de contacts" link (no capture shows it).
        case addContact
        /// "<category> -> Transactions (N)".
        case transaction
        /// "Configuration matérielle" row.
        case configuration
        /// Any other link row.
        case link
    }

    /// Opaque stable key `action|<kind>|<URL>`.
    public var id: String
    /// Link text, whitespace normalized.
    public var title: String
    /// Title of the section the row sits in; nil for `configuration`, which comes from a field row.
    public var subtitle: String?
    /// Absolute `https://forum.hardware.fr` URL, safe to request with the session; links to any other place are dropped.
    public var url: URL
    /// The kind of link.
    public var kind: Kind

    /// Creates a value; used by the parser and by tests.
    public init(id: String, title: String, subtitle: String?, url: URL, kind: Kind) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.kind = kind
    }
}
