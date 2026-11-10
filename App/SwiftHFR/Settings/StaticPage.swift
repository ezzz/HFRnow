import Foundation

// Port of HFRswift/Swift/StaticInfoPageView.swift (StaticInfoPageKind, StaticHTMLWebView) @ 87fe0d1c. Differences: the credits
// text is SwiftHFR's own (CREDITS.md); no theme CSS injection, the pages follow the system appearance (GAP-151, LOT-120 spec).
/// The two bundled static pages of the Plus tab (LOT-120): the credits and the forum charter.
enum StaticPage: CaseIterable, Hashable, Sendable {
    case credits
    case charter

    /// Navigation title (legacy `StaticInfoPageKind.title`).
    var title: String {
        switch self {
        case .credits: "Crédits"
        case .charter: "Charte du forum"
        }
    }

    /// Name of the bundled HTML file, without extension. Flat names: the app's resources share one folder.
    var resourceName: String {
        switch self {
        case .credits: "static-credits"
        case .charter: "static-charter"
        }
    }

    /// The page ready for a web view, or the "not found" body when a resource is missing (legacy "Fichier introuvable").
    func html(bundle: Bundle = .main) -> String {
        guard let body = Self.text(of: resourceName, extension: "html", in: bundle),
              let style = Self.text(of: Self.styleName, extension: "css", in: bundle)
        else { return Self.missingPage }
        return Self.compose(body: body, style: style)
    }

    /// `body` with `style` inserted before `</head>` (at the start when the page has no head).
    static func compose(body: String, style: String) -> String {
        let tag = "<style>\(style)</style>"
        guard body.contains("</head>") else { return tag + body }
        return body.replacing("</head>", with: tag + "</head>", maxReplacements: 1)
    }

    /// Name of the stylesheet shared by both pages.
    static let styleName = "static-page"

    /// Shown when a resource is missing from the bundle.
    static let missingPage = "<html><head><meta charset=\"utf-8\"></head><body><p>Page introuvable</p></body></html>"

    /// What tapping a link of a static page does: a browser, never the reader and never with the session.
    static func action(forLink url: URL, defaultBrowser: Bool) -> StaticPageLinkAction {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return .ignored }
        return defaultBrowser ? .defaultBrowser(url) : .inAppBrowser(url)
    }

    private static func text(of name: String, extension fileExtension: String, in bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// What a tapped link of a static page leads to.
enum StaticPageLinkAction: Equatable, Sendable {
    /// Safari's view inside the app.
    case inAppBrowser(URL)
    /// The system's default browser ("Navigateur par défaut", LOT-119).
    case defaultBrowser(URL)
    /// Not an `http(s)` link: nothing happens.
    case ignored
}
