import Foundation
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

struct StaticPageTests {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func repositoryText(_ name: String) throws -> String {
        try String(contentsOf: repository.appending(path: name), encoding: .utf8)
    }

    @Test func titlesAreTheLegacyOnes() {
        #expect(StaticPage.allCases.map(\.title) == ["Crédits", "Charte du forum"])
    }

    @Test func bothPagesAreBundledWithTheirStyle() {
        for page in StaticPage.allCases {
            let html = page.html()
            #expect(html != StaticPage.missingPage, "\(page.title) is not bundled")
            #expect(html.contains("<style>"), "\(page.title) has no style")
            #expect(html.contains("color-scheme: light dark"))
            #expect(!html.contains("%%iosversion%%"))
        }
    }

    @Test func aPageHoldsNoScript() {
        for page in StaticPage.allCases {
            #expect(!page.html().lowercased().contains("<script"))
        }
    }

    @Test func aMissingResourceShowsTheNotFoundBody() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "static-page-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let empty = try #require(Bundle(path: folder.path(percentEncoded: false)))
        #expect(StaticPage.credits.html(bundle: empty) == StaticPage.missingPage)
    }

    @Test func styleGoesBeforeTheHeadEndOrAtTheStart() {
        #expect(StaticPage.compose(body: "<head></head><body>x</body>", style: "a{}") == "<head><style>a{}</style></head><body>x</body>")
        #expect(StaticPage.compose(body: "<body>x</body>", style: "a{}") == "<style>a{}</style><body>x</body>")
        #expect(StaticPage.compose(body: "</head></head>", style: "a{}") == "<style>a{}</style></head></head>")
    }

    @Test func theCharterIsTheLegacyTextUnchanged() {
        let html = StaticPage.charter.html()
        #expect(html.contains("ARTICLE 1 : Modalités d'accès et d'inscription"))
        #expect(html.contains("ARTICLE 2 : Données collectées"))
        #expect(html.contains("En cas de litige avec un modérateur"))
    }

    @Test func everyLinkOfCreditsAndLicenceAppearsInTheCreditsPage() throws {
        let html = StaticPage.credits.html()
        let sources = try ["CREDITS.md", "LICENSE", "LICENSE-docs.md"].map(Self.repositoryText)
        let links = try sources.flatMap { try Self.absoluteLinks(in: $0) }
        #expect(links.count >= 8)
        for link in Set(links) {
            #expect(html.contains("href=\"\(link)\""), "missing \(link)")
        }
    }

    @Test func creditsNameTheLicenceAndEveryContributorOfCredits() throws {
        let html = StaticPage.credits.html()
        let licence = try Self.repositoryText("LICENSE").split(separator: "\n").first.map(String.init) ?? ""
        #expect(licence == "# PolyForm Noncommercial License 1.0.0")
        #expect(html.contains("PolyForm Noncommercial 1.0.0"))
        #expect(html.contains("CC BY 4.0"))
        let credits = try Self.repositoryText("CREDITS.md")
        for name in ["FLKone", "ezzz", "Bybifok", "moust4ki", "SwiftSoup", "Bruno"] {
            #expect(credits.contains(name), "\(name) left CREDITS.md: update the page")
            #expect(html.contains(name), "\(name) is missing from the credits page")
        }
    }

    @Test func aTappedLinkIsABrowserLinkNeverTheReader() throws {
        let web = try #require(URL(string: "https://github.com/ezzz/HFRnow"))
        let forum = try #require(URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=25&post=1711&page=1"))
        #expect(StaticPage.action(forLink: web, defaultBrowser: false) == .inAppBrowser(web))
        #expect(StaticPage.action(forLink: web, defaultBrowser: true) == .defaultBrowser(web))
        #expect(StaticPage.action(forLink: forum, defaultBrowser: false) == .inAppBrowser(forum))
        for scheme in ["mailto:a@b.c", "javascript:alert(1)", "file:///etc/passwd", "tel:1"] {
            let url = try #require(URL(string: scheme))
            #expect(StaticPage.action(forLink: url, defaultBrowser: false) == .ignored)
        }
    }

    @Test @MainActor func theWebViewRunsNoPageScript() async throws {
        #expect(StaticPageWebView.makeConfiguration().defaultWebpagePreferences.allowsContentJavaScript == false)
        let webView = WKWebView(frame: .zero, configuration: StaticPageWebView.makeConfiguration())
        // Shown as in Réglages: in no window, this test took 67 s on green run 43060241312 and 320 s on job 130925974296 (#801).
        let window = hostInWindow(webView)
        let loader = LoadWaiter()
        webView.navigationDelegate = loader
        let page = "<html><body><script>document.body.setAttribute('data-ran', 'yes')</script></body></html>"
        webView.loadHTMLString(page, baseURL: nil)
        let ended = await loader.ended.wait(timeout: .seconds(120))
        // A page that failed to load runs no script either: only a loaded one proves the setting.
        #expect(ended && loader.failure == nil, "the page did not load: \(loader.failure ?? "no answer before the deadline")")
        let ran = try await answer(of: "the static page") {
            try await webView.evaluateJavaScript("String(document.body.getAttribute('data-ran'))")
        }
        #expect(ran as? String == "null")
        withExtendedLifetime(window) {}
    }

    /// `https://…` links of a Markdown or licence text, without the closing punctuation.
    private static func absoluteLinks(in text: String) throws -> [String] {
        let pattern = try Regex(#"https://[^\s)>\]`"|]+"#)
        return text.matches(of: pattern).map { String(text[$0.range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;")) }
    }
}

/// Tells when a web view's load ended, and how: finished, failed, or its content process died (no other callback comes then,
/// so a wait on the first two alone could hang the test job, issue #801).
@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    let ended = TestEvent()
    /// Why the load did not finish; nil when it finished.
    private(set) var failure: String?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) { ended.fire() }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        end(failure: "failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        end(failure: "failed before committing: \(error)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { end(failure: "the content process terminated") }

    private func end(failure: String) {
        guard !ended.hasFired else { return }
        self.failure = failure
        ended.fire()
    }
}
