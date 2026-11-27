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

    /// What each position does, in the operator's words (issue #1071, 2026-11-17), then what the switch never changes. The last
    /// line is the operator's « Les liens du forum (sujets, MP, profils) restent toujours dans l'app » limited to the reader,
    /// the only screen where that holds (see above).
    static let explanation = [
        "Activé : les liens s’ouvrent dans une nouvelle fenêtre de ton navigateur (hors de l’app).",
        "Désactivé : les liens s’ouvrent dans une fenêtre à l’intérieur de l’app.",
        "Dans le lecteur, les liens du forum (sujets, MP, profils) restent toujours dans l’app."
    ]
}
