import Foundation

/// What the reader does with a link the user tapped (LOT-137).
enum ReaderLinkAction: Equatable, Sendable {
    /// A topic or private message page of the forum: opened in the app, at its page and post (`TopicReaderModel.follow`).
    case reader(ReaderTarget)
    /// Anything else on the web, in Safari's view inside the app (`SFSafariViewController`, LOT-071 T8).
    case inAppBrowser(URL)
    /// Anything else on the web, in the system's default browser ("Navigateur par défaut", LOT-119).
    case defaultBrowser(URL)
    /// Not an `http(s)` link: nothing happens.
    case ignored
}
