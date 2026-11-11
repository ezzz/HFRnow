import Foundation
import HFRModels
import HFRParsing
import UIKit
import WebKit

// Port of HFRswift/Swift/MessagesView.swift (WebView.Coordinator `contextMenuConfigurationForElement`, :1241-1278 @ 2440d79;
// `imageURLForContextMenuElementInfo` :2575-2582 and `saveImageToPhotoLibrary` :2584-2605 @ 2fe43da3) and Common.swift
// (`MessageImageViewerURLResolver.isImageURL`, :2214-2240 @ 2fe43da3). Differences: legacy returned nil for a plain link (WebKit's own
// menu, with a preview) and built a menu for image links only; this one is the app's own for every http(s) link, never a preview, and
// an image link gets "Ouvrir l'image" and "Enregistrer dans Photos" (legacy "Save to Photos", English) before the common entries (#615).
// A picture that is not a link has no entry: WebKit gives the menu no image URL, and the reader's own images are `hfrreader:` ones.
/// The long-press menu of a link in a message (#596). Nothing here requests a URL: the entries hand it to the app's tap routing
/// (`events.link`) or to the system, and the member's link is never fetched with the session.
enum ReaderLinkMenu {
    /// One entry of the menu.
    enum Entry: Equatable, Sendable {
        /// Same routing as a tap (`HFRLinkRoute`: forum in the app, the rest outside).
        case open
        /// Puts the URL on the pasteboard.
        case copy
        /// The image behind an image link, in the app's viewer (LOT-109), cookie-less like every reader image.
        case openImage
        /// Downloads the image behind an image link (cookie-less) and adds it to Photos (add-only permission).
        case saveImage
        /// `UIApplication.open`: iOS may still give a universal link to its app.
        case safari
        /// Universal links only, Safari when no app takes it. `provider` names a video host of LOT-035, nil otherwise.
        case app(provider: EmbedProvider?)

        /// Label shown to the reader.
        var title: String {
            switch self {
            case .open: "Ouvrir"
            case .copy: "Copier le lien"
            case .openImage: "Ouvrir l'image"
            case .saveImage: "Enregistrer dans Photos"
            case .safari: "Ouvrir dans Safari"
            case .app(let provider): provider.map { "Ouvrir dans \(TopicHTMLBuilder.providerName($0))" } ?? "Ouvrir dans l'app"
            }
        }

        var symbol: String {
            switch self {
            case .open: "arrow.up.right.square"
            case .copy: "doc.on.doc"
            case .openImage: "photo"
            case .saveImage: "square.and.arrow.down"
            case .safari: "safari"
            case .app: "arrow.up.forward.app"
            }
        }
    }

    /// What the menu does outside the web view; tests replace it.
    struct Environment {
        var open: @MainActor (URL, _ universalLinksOnly: Bool) async -> Bool
        var copy: @MainActor (URL) -> Void
        /// Adds downloaded image bytes to the photo library.
        var savePhoto: @Sendable (Data) async throws(ImageSaveError) -> Void

        static let live = Environment(
            open: { url, universalOnly in
                await UIApplication.shared.open(url, options: universalOnly ? [.universalLinksOnly: true] : [:])
            },
            copy: { url in
                UIPasteboard.general.url = url
                AccessibilityNotification.Announcement("Lien copié").post()
            },
            savePhoto: { data async throws(ImageSaveError) in try await PhotoLibrarySaver.save(data) }
        )
    }

    /// The entries for `url`: none unless it is an `http(s)` link. An image link gets the two image entries after "Ouvrir". A forum
    /// link (topic, MP or profile) stays in the app, so it has no "app" entry; any other link has one, named for the video hosts the
    /// reader already recognises.
    static func entries(for url: URL) -> [Entry] {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return [] }
        var entries: [Entry] = [.open]
        if isImageLink(url) { entries += [.openImage, .saveImage] }
        entries += [.copy, .safari]
        if isForumLink(url) { return entries }
        let provider = scheme == "https" ? MessageEmbedDetector.embed(for: url)?.provider : nil
        return entries + [.app(provider: provider)]
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif"]

    /// Legacy `MessageImageViewerURLResolver.isImageURL`: an image extension, or one of the rehost hosts whose links carry none.
    /// A host policy C blocks gets no image entry: nothing would be fetched for it.
    static func isImageLink(_ url: URL) -> Bool {
        if case .blocked = ImagePolicy.classify(url) { return false }
        if imageExtensions.contains(url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) { return true }
        guard let host = url.host()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return host == "reho.st" || host.hasSuffix(".reho.st") || host == "img3.super-h.fr" || host == "rehost.diberie.com"
    }

    /// The sentence shown after "Enregistrer dans Photos": downloads the image of `url` through `fetcher` (cookie-less, the viewer's
    /// host rules: full size first, the shown address when the host serves no full size) and hands the bytes to `save`.
    static func saveImage(
        _ url: URL, fetcher: ReaderImageFetcher, save: @Sendable (Data) async throws(ImageSaveError) -> Void
    ) async -> String {
        // The user chose this image: its own host is consented to, a blocked one never enters the gallery.
        guard let image = ImageGallery.build(
            sources: [url.absoluteString], selected: 0, consented: [url.absoluteString], autoLoadsThirdParty: false
        )?.images.first else { return "Impossible d'enregistrer cette image." }
        var bytes = try? await fetcher.image(at: image.full, allowsThirdParty: image.allowsThirdParty, hostTable: .standard).data
        if bytes == nil, image.full != image.shown {
            bytes = try? await fetcher.image(at: image.shown, allowsThirdParty: image.allowsThirdParty, hostTable: .standard).data
        }
        guard let bytes else { return "Erreur réseau" }
        do throws(ImageSaveError) {
            try await save(bytes)
            return "Photo enregistrée"
        } catch {
            switch error {
            case .permissionDenied: return "Autorise l'accès aux Photos pour enregistrer l'image."
            case .invalidImage: return "Impossible d'enregistrer cette image."
            case .system: return "L'enregistrement dans Photos a échoué."
            }
        }
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
    /// The entries of a long-pressed link: none under an open composer (#653), where the menu stays ours but empty, never
    /// WebKit's default one, which previews (loads) the link.
    func linkMenuEntries(for url: URL) -> [ReaderLinkMenu.Entry] {
        ignoresPageTaps ? [] : ReaderLinkMenu.entries(for: url)
    }

    func linkMenuConfiguration(for url: URL?) -> UIContextMenuConfiguration? {
        guard let url else { return nil }
        let entries = linkMenuEntries(for: url)
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
        case .openImage:
            openLinkedImage(url)
        case .saveImage:
            let fetcher = imageFetcher
            let save = linkMenuEnvironment.savePhoto
            Task { [weak self] in
                let message = await ReaderLinkMenu.saveImage(url, fetcher: fetcher, save: save)
                self?.events.notice(message) // shown as the reader's toast, which announces itself
            }
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

    /// Opens the viewer on the image of `url`; the viewer's own policy check (`ImageGallery`) refuses a blocked host.
    private func openLinkedImage(_ url: URL) {
        guard let gallery = ImageGallery.build(
            sources: [url.absoluteString], selected: 0, consented: [url.absoluteString], autoLoadsThirdParty: false
        ) else { return }
        events.image(gallery.images, gallery.index, document?.token ?? 0)
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
