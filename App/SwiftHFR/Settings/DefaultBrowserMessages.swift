import Foundation

/// The words of the « Navigateur par défaut » row of Réglages (#1071). The explanation follows `ReaderLinkAction` and its callers
/// (`TopicReaderModel.action(forLink:defaultBrowser:)`), verified for #1071: in the reader a topic or private message page of
/// the forum and a member's profile stay in the app whatever the switch says; every other `http(s)` link goes to Safari inside
/// the app (`SFSafariViewController`, switch off) or to the system's default browser (switch on, the app goes to the
/// background). The profile, the filtered posts and the static pages have no reader to open a link in: all their links
/// follow the switch.
enum DefaultBrowserMessages {
    /// The switch's title.
    static let title = "Navigateur par défaut"

    /// The accessibility label of the (i) button that opens `explanation` in a bubble.
    static let infoLabel = "À propos du navigateur par défaut"

    /// What each position does, one short sentence each; the last says what the switch never changes.
    static let explanation = [
        "Désactivé : les autres liens s’ouvrent dans Safari, intégré à l’app.",
        "Activé : ils s’ouvrent dans le navigateur par défaut de l’iPhone ; l’app passe en arrière-plan.",
        "Dans le lecteur, les sujets, les MP et les profils du forum restent dans l’app, quel que soit le réglage."
    ]
}
