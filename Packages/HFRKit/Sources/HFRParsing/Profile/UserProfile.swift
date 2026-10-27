import Foundation

/// A member's public profile page, `/hfr/profil-<id>.htm` (LOT-027).
///
/// Everything on the page is public to the visitor who fetched it; the value holds no token. Section fields keep the
/// page's own labels and text, the typed properties are the figures the app needs.
public struct UserProfile: Sendable, Hashable {
    /// Pseudo from the `Pseudo` row, without zero-width spaces; empty when the page has no such row.
    public var pseudo: String
    /// Text of the `Statut` row (`Membre`, …); nil when absent or empty.
    public var status: String?
    /// Avatar image, absolute `http(s)` URL; nil when the member has none.
    public var avatarURL: URL?
    /// Number of posted messages (`Nombre de messages postés`); nil when absent or not a number.
    public var messageCount: Int?
    /// Day of arrival (`Date d'arrivée sur le forum`, `dd/MM/yyyy`) as midnight Europe/Paris; nil when absent or invalid.
    public var joinDate: Date?
    /// Date of the last message (`Date du dernier message`, `dd-MM-yyyy à HH:mm`), Europe/Paris; nil when absent or invalid.
    public var lastMessageDate: Date?
    /// Headline fields, in the order messages, arrival, last message; each present only when the field has a value.
    public var summary: [UserProfileSummaryItem]
    /// Sections with at least one field, in page order.
    public var sections: [UserProfileSection]
    /// Personal smileys, in page order, without duplicates.
    public var personalSmilies: [UserProfileSmiley]
    /// Link rows, in page order, without duplicates.
    public var actions: [UserProfileAction]

    /// Creates a value; used by the parser and by tests.
    public init(
        pseudo: String = "",
        status: String? = nil,
        avatarURL: URL? = nil,
        messageCount: Int? = nil,
        joinDate: Date? = nil,
        lastMessageDate: Date? = nil,
        summary: [UserProfileSummaryItem] = [],
        sections: [UserProfileSection] = [],
        personalSmilies: [UserProfileSmiley] = [],
        actions: [UserProfileAction] = []
    ) {
        self.pseudo = pseudo
        self.status = status
        self.avatarURL = avatarURL
        self.messageCount = messageCount
        self.joinDate = joinDate
        self.lastMessageDate = lastMessageDate
        self.summary = summary
        self.sections = sections
        self.personalSmilies = personalSmilies
        self.actions = actions
    }
}
