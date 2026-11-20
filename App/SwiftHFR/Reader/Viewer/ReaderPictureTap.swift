import Foundation
import HFRNetwork

// Port of HFRswift/Swift/Common.swift (`MessageImageViewerURLResolver.isImageURL`, `:2243-2256`) @ 87fe0d1c and of the tap script
// of `MessagesView.swift:1150-1235` @ 87fe0d1c. Differences (#912): legacy's tap script read the picture's `longdesc`, not its
// `<a>`, and opened the viewer only for a small `img3.super-h.fr` thumbnail whose link names the same file; every other tap fell
// through to the link's own navigation, with no warning. Here a link to an image opens that image in the viewer, and a link to a
// page asks first (the forum's own links open in the reader, as LOT-137).

/// What a tap on a loaded posted picture does, from the link around it (#912). The page only reports the link; this decides.
enum ReaderPictureTap: Equatable, Sendable {
    /// No usable link: today's viewer on the page's pictures.
    case viewer
    /// The link is an image the viewer may fetch: the viewer opens it at this address, the preview being the fallback.
    case linkedImage(URL)
    /// The link is anything else: the app routes it (`ReaderLinkAction`), asking first when it leaves the app.
    case link(URL)

    /// Path extensions that make a link an image (legacy `imageExtensions`, `Common.swift:2231-2242`).
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif"]

    /// The outcome for the picture `shown` wrapped in `link` (the `href` the page reports, nil when it is in no link).
    static func decide(
        shown: String?, link: String?, autoLoadsThirdParty: Bool, hosts: ImageHostTable = .standard
    ) -> ReaderPictureTap {
        guard let link, let target = URL(string: link), let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return .viewer }
        guard isImage(target, hosts: hosts) else { return .link(target) }
        guard let shown, let shownURL = URL(string: shown),
              let full = ImageGallery.linkedFull(of: shownURL, linked: target, autoLoadsThirdParty: autoLoadsThirdParty, hosts: hosts)
        else { return .link(target) }
        return .linkedImage(full)
    }

    /// Whether `url` names an image: an image extension, or a rehost the table knows to serve extension-less images
    /// (legacy listed `reho.st`, `img3.super-h.fr` and `rehost.diberie.com`, which `ImageHostTable.standard` carries).
    static func isImage(_ url: URL, hosts: ImageHostTable = .standard) -> Bool {
        if imageExtensions.contains(url.pathExtension.lowercased()) { return true }
        return hosts.servesExtensionlessImages(url) && url.path().count > 1
    }
}

extension ReaderLinkAction {
    /// The web address the user would leave the app for, when it is not a forum page (the confirmation of #912 names its domain).
    var externalURL: URL? {
        switch self {
        case .inAppBrowser(let url), .defaultBrowser(let url): url
        case .reader, .profile, .ignored: nil
        }
    }
}
