import Foundation
import HFRModels
import HFRParsing
import UIKit
import WebKit

// Port of HFRswift/Swift/MessagesView.swift (WebView.Coordinator `contextMenuConfigurationForElement`, :1241-1278) @ 2440d79. Differences:
// legacy returned nil for a plain link (WebKit's own menu, with a preview) and built a menu for image links only; this one is the
// app's own for every http(s) link, never a preview; "Ouvrir l'image" and "Save to Photos" are deferred to #615 (GAP-596, #596).
/// The long-press menu of a link in a message (#596). Nothing here requests a URL: the entries hand it to the app's tap routing
/// (`events.link`) or to the system, and the member's link is never fetched with the session.
enum ReaderLinkMenu {
    /// One entry of the menu.
    enum Entry: Equatable, Sendable {
        /// Same routing as a tap (`HFRLinkRoute`: forum in the app, the rest outside).
        case open
        /// Puts the URL on the pasteboard.
        case copy
        /// `UIApplication.open`: iOS may still give a universal link to its app.
        case safari
        /// Universal links only, Safari when no app takes it. `provider` names a video host of LOT-035, nil otherwise.
        case app(provider: EmbedProvider?)

        /// Label shown to the reader.
        var title: String {
            switch self {
            case .open: "Ouvrir"
            case .copy: "Copier le lien"
            case .safari: "Ouvrir dans Safari"
            case .app(let provider): provider.map { "Ouvrir dans \(TopicHTMLBuilder.providerName($0))" } ?? "Ouvrir dans l'app"
            }
        }

        var symbol: String {
            switch self {
            case .open: "arrow.up.right.square"
            case .copy: "doc.on.doc"
            case .safari: "safari"
            case .app: "arrow.up.forward.app"
            }
        }
    }

    /// What the menu does outside the web view; tests replace it.
    struct Environment {
        var open: @MainActor (URL, _ universalLinksOnly: Bool) async -> Bool
        var copy: @MainActor (URL) -> Void

        static let live = Environment(
            open: { url, universalOnly in
                await UIApplication.shared.open(url, options: universalOnly ? [.universalLinksOnly: true] : [:])
            },
            copy: { url in
                UIPasteboard.general.url = url
                AccessibilityNotification.Announcement("Lien copié").post()
            }
        )
    }

    /// The entries for `url`: none unless it is an `http(s)` link. A forum link (topic, MP or profile) stays in the app, so it
    /// has no "app" entry; any other link has one, named for the video hosts the reader already recognises.
    static func entries(for url: URL) -> [Entry] {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return [] }
        if isForumLink(url) { return [.open, .copy, .safari] }
        let provider = scheme == "https" ? MessageEmbedDetector.embed(for: url)?.provider : nil
        return [.open, .copy, .safari, .app(provider: provider)]
    }

    private static func isForumLink(_ url: URL) -> Bool {
        if ReaderTarget(link: url.absoluteString) != nil { return true }
        if case .profile = HFRLinkRoute.route(for: url) { return true }
        return false
    }
}

extension ReaderWebController {
    /// The menu of the element under the finger, or nil for something that is not a link (WebKit's own menu, which loads
    /// nothing for an image already in the page). A link that is not `http(s)` gets an empty menu, never WebKit's default.
    func linkMenuConfiguration(for url: URL?) -> UIContextMenuConfiguration? {
        guard let url else { return nil }
        let entries = ReaderLinkMenu.entries(for: url)
        // No preview provider: WebKit loads the destination of a link it previews, a request nobody consented to.
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let actions = entries.map { entry in
                UIAction(title: entry.title, image: UIImage(systemName: entry.symbol)) { _ in
                    self?.performLinkEntry(entry, url: url)
                }
            }
            return UIMenu(title: url.host() ?? "", children: actions)
        }
    }

    /// Runs a menu entry. Internal so tests drive it without a long press.
    func performLinkEntry(_ entry: ReaderLinkMenu.Entry, url: URL) {
        switch entry {
        case .open:
            events.link(url)
        case .copy:
            linkMenuEnvironment.copy(url)
        case .safari:
            let environment = linkMenuEnvironment
            Task { _ = await environment.open(url, false) }
        case .app:
            let environment = linkMenuEnvironment
            Task {
                // Only the answer tells whether an app took the link; none did, so Safari gets it (operator's wording).
                if await !environment.open(url, true) { _ = await environment.open(url, false) }
            }
        }
    }

    func webView(
        _ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor @Sendable (UIContextMenuConfiguration?) -> Void
    ) {
        completionHandler(linkMenuConfiguration(for: elementInfo.linkURL))
    }

    /// Committing a (nonexistent) preview never navigates: the web view stays on the document.
    func webView(
        _ webView: WKWebView, contextMenuForElement elementInfo: WKContextMenuElementInfo,
        willCommitWithAnimator animator: any UIContextMenuInteractionCommitAnimating
    ) {
        animator.preferredCommitStyle = .dismiss
    }
}
