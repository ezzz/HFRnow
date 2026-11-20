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
        shown: String?, link: String?, consented: Set<String> = [], autoLoadsThirdParty: Bool, hosts: ImageHostTable = .standard
    ) -> ReaderPictureTap {
        guard let link, let target = URL(string: link), let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return .viewer }
        let shownURL = shown.flatMap { URL(string: $0) }
        guard isImage(target, hosts: hosts) else {
            // The host's own viewer page of a thumbnail it can enlarge (img3: `/image/<id>` around `/images/<hash>.th.png`, R298a/b/e)
            // stays today's viewer, which opens the table's full size: a warning there would be a regression (#917).
            if let shownURL, hosts.rule(for: shownURL) != nil, shownURL.host()?.lowercased() == target.host()?.lowercased(),
               hosts.fullSizeURL(for: shownURL) != shownURL { return .viewer }
            return .link(target)
        }
        guard let shownURL,
              let full = ImageGallery.linkedFull(
                  of: shownURL, linked: target, consented: consented, autoLoadsThirdParty: autoLoadsThirdParty, hosts: hosts)
        else { return .link(target) }
        return .linkedImage(full)
    }

    /// Whether `url` names an image. A host with a rule that serves extension-less images (`reho.st`, `img3.super-h.fr`,
    /// `rehost.diberie.com`) also has viewer pages that look alike (`img3.super-h.fr/image/<id>`, `reho.st/view/self/<hash>.png`,
    /// captures R298a/b/e and R122c), so there the path must have the shape of the rule's image (`imagePathPrefix`), whatever its
    /// extension; a host without such a rule is read by extension (legacy `imageExtensions`).
    static func isImage(_ url: URL, hosts: ImageHostTable = .standard) -> Bool {
        if hosts.servesExtensionlessImages(url) {
            guard let prefix = imagePathPrefix(of: url, hosts: hosts) else { return false }
            return url.path().hasPrefix(prefix) && url.path().count > prefix.count
        }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// The path under which the rule's host serves an image itself, from the rule's rewrite (`/images/` for img3, captured as
    /// full images such as `R298` `/images/2025/03/26/snapshot_….jpg`; `/Picture/Get/f/` for diberie, the target of its rewrite,
    /// linked in the corpus). Nil when no capture shows the shape: `reho.st` rewrites to `/`, and no capture of a link around
    /// its thumbnail shows an image (`/view/self/…` only), so its links are pages until #1280's capture says otherwise.
    static func imagePathPrefix(of url: URL, hosts: ImageHostTable) -> String? {
        switch hosts.rule(for: url)?.thumbnailRewrite {
        case .pathPrefix(_, let replacement): replacement == "/" ? nil : replacement
        case .fileNameMarkers(let prefix, _): prefix
        case nil: nil
        }
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
