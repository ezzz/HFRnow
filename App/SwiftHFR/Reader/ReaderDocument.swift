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
