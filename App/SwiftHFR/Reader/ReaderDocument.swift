import Foundation

/// An HTML document handed to the web view. `token` is unique per model, so an event of an older document is recognised.
struct ReaderDocument: Equatable, Sendable {
    /// Identity of this document; grows with every new document.
    let token: Int
    /// The full page (TopicHTMLBuilder).
    let html: String
    /// Message to scroll to once shown.
    let anchor: Int?
    /// Keep the scroll position of the previous document (a refresh of the same page).
    let keepsScrollPosition: Bool
}

/// A request to scroll the shown document to a message, without reloading it (a link to a post of the same page).
struct ScrollRequest: Equatable, Sendable {
    /// Unique per request, so asking twice for the same message scrolls twice.
    let id: Int
    /// The document the request is for.
    let token: Int
    /// Message number.
    let anchor: Int
}

/// What the reader does with a link the user tapped (LOT-137).
enum ReaderLinkAction: Equatable, Sendable {
    /// A topic or private message page of the forum: opened in the app, at its page and post (`TopicReaderModel.follow`).
    case reader(ReaderTarget)
    /// A member's public profile (`/hfr/profil-<id>.htm`): the profile sheet (LOT-116), as legacy
    /// `OnlineMessagesTableViewController.m:1953-1964` at `2440d79` opened `ProfilViewController`.
    case profile(memberID: Int)
    /// Anything else on the web, in Safari's view inside the app (`SFSafariViewController`, LOT-071 T8).
    case inAppBrowser(URL)
    /// Anything else on the web, in the system's default browser ("Navigateur par défaut", LOT-119).
    case defaultBrowser(URL)
    /// Not an `http(s)` link: nothing happens.
    case ignored
}
