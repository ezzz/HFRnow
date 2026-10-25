import Foundation

/// Per-message action links, absolute and already de-obfuscated; nil when HFR does not offer the action.
public struct MessageActions: Sendable, Hashable, Codable {
    /// Form page that pre-fills a quote of the message.
    public var quoteURL: URL?
    /// Edit form page; only on messages the user may edit.
    public var editURL: URL?
    /// Moderator alert form page.
    public var alertURL: URL?
    /// Author profile page.
    public var profileURL: URL?
    /// New private message to the author.
    public var privateMessageURL: URL?
    /// `addflag` link that flags the topic from this message (a state-changing GET).
    public var favoriteURL: URL?
    /// Multi-quote arguments.
    public var quoteSelection: QuoteSelectionToken?

    /// Creates the action set; the default is "no action available".
    public init(
        quoteURL: URL? = nil,
        editURL: URL? = nil,
        alertURL: URL? = nil,
        profileURL: URL? = nil,
        privateMessageURL: URL? = nil,
        favoriteURL: URL? = nil,
        quoteSelection: QuoteSelectionToken? = nil
    ) {
        self.quoteURL = quoteURL
        self.editURL = editURL
        self.alertURL = alertURL
        self.profileURL = profileURL
        self.privateMessageURL = privateMessageURL
        self.favoriteURL = favoriteURL
        self.quoteSelection = quoteSelection
    }
}
