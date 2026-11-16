import HFRModels
import HFRNetwork
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit
import WebKit

/// The real `TopicReaderView` in a navigation stack, in a window: what no model test reaches. Issue #641 (the page is handed
/// the bars' heights, with the bottom `safeAreaBar` the view now adds) and issue #594 (the model's message menu reaches the
/// web view's edit-menu callout through the view's `onChange`).
@MainActor
@Suite(.serialized)
struct TopicReaderViewHostedTests: ReaderWebTesting {
    private struct Hosted {
        let reader: TopicReaderModel
        let window: UIWindow
        let webView: WKWebView
    }

    private func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = webView(in: child) { return web } }
        return nil
    }

    /// `tall`: two 1500-pixel messages (100 and 101), so a landing on 101 has to scroll.
    private func host(
        target: ReaderTarget = ReaderTarget(source: .topic(readerTopic), page: 1), tall: Bool = false
    ) async throws -> Hosted {
        let pageURL = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        let pages = FakeTopicPages { _ in
            var page = tall ? Self.tallPage() : readerPage(page: 1, maxPage: 1)
            page.pageURL = pageURL
            return page
        }
        let reader = TopicReaderModel(target: target, title: "Sujet", source: pages)
        let services = ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([])
        )
        let controller = UIHostingController(rootView: NavigationStack { TopicReaderView(model: reader, services: services) })
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        #expect(await until { reader.document != nil && webView(in: window) != nil })
        return Hosted(reader: reader, window: window, webView: try #require(webView(in: window)))
    }

    /// Issue #641: the first post's header opens below the top bar because the web view is told what covers it. The top inset
    /// is the window's own (status bar) plus at least a navigation bar; the bottom one at least a bar too.
    @Test func theReaderHandsItsWebViewTheHeightOfBothBars() async throws {
        let hosted = try await host()
        defer { hosted.window.isHidden = true }
        let window = hosted.window, web = hosted.webView
        let enough = await until({
            web.obscuredContentInsets.top >= window.safeAreaInsets.top + 44 && web.obscuredContentInsets.bottom >= 44
        }, timeout: .seconds(30))
        #expect(enough, "insets \(web.obscuredContentInsets), window safe area \(window.safeAreaInsets)")
        #expect(web.scrollView.contentInset.top == web.obscuredContentInsets.top)
    }

    nonisolated private static func tallPage() -> ReaderPage {
        func message(_ number: Int) -> ReaderMessage {
            ReaderMessage(
                numreponse: number, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil,
                content: MessageContent(html: "<div style=\"height:1500px\">m\(number)</div>")
            )
        }
        return ReaderPage(topicID: readerTopic, title: "Sujet", currentPage: 1, maxPage: 1, messages: [message(100), message(101)])
    }

    /// The lower edge of the top bars in window coordinates: the navigation bar's, never above the window's own safe area.
    private func topBarsEdge(in window: UIWindow) -> CGFloat {
        func bars(in view: UIView) -> [UINavigationBar] {
            ((view as? UINavigationBar).map { [$0] } ?? []) + view.subviews.flatMap { bars(in: $0) }
        }
        let shown = bars(in: window).filter { !$0.isHidden && $0.alpha > 0 && $0.window != nil }
        let bottom = shown.map { $0.convert($0.bounds, to: window).maxY }.max() ?? 0
        return max(bottom, window.safeAreaInsets.top)
    }

    /// The header and the "+" of message `post` in window coordinates, read in document coordinates (CSS pixels from the
    /// document's top, the scroll view's content coordinates at zoom 1) and placed by the scroll view: no assumption on where
    /// WebKit counts `getBoundingClientRect` from under `obscuredContentInsets`. Nil until the page shows the message's "+".
    private func header(of post: Int, in hosted: Hosted) async -> (header: CGRect, plus: CGRect)? {
        let script = """
        const article = document.getElementById('t' + n);
        const plus = article ? article.querySelector('header.header .menu-button') : null;
        if (!plus) { return null; }
        const rect = (e) => {
          const b = e.getBoundingClientRect();
          return [b.left + window.scrollX, b.top + window.scrollY, b.width, b.height];
        };
        return rect(article.querySelector('header.header')).concat(rect(plus));
        """
        let web = hosted.webView
        let result = try? await answer(of: "the reader page", within: WaitBudget.cap(.seconds(10))) {
            try await web.callAsyncJavaScript(script, arguments: ["n": post], in: nil, contentWorld: ReaderWebController.world)
        }
        guard let values = (result as? [NSNumber])?.map({ CGFloat($0.doubleValue) }), values.count == 8 else { return nil }
        let scrollView = web.scrollView
        func placed(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            scrollView.convert(CGRect(x: x, y: y, width: width, height: height), to: hosted.window)
        }
        return (placed(values[0], values[1], values[2], values[3]), placed(values[4], values[5], values[6], values[7]))
    }

    /// Whether a tap at the centre of `plus` reaches the page, not a bar over it.
    private func reachesThePage(_ plus: CGRect, in hosted: Hosted) -> Bool {
        let hit = hosted.window.hitTest(CGPoint(x: plus.midX, y: plus.midY), with: nil)
        return hit?.isDescendant(of: hosted.webView) == true
    }

    /// Issue #641, as seen on screen: once the page is shown at its top, the first post's header (avatar, pseudo, date, "+") is
    /// entirely below the top bar, and a tap on its "+" reaches the page. Before #878 the web view got no top inset and the
    /// header sat at y 5-53 under the status bar and the bar, where a tap opened nothing.
    @Test func theFirstPostsHeaderOpensBelowTheTopBarAndItsPlusTakesTheTap() async throws {
        let hosted = try await host()
        defer { hosted.window.isHidden = true }
        var seen: (header: CGRect, plus: CGRect)?
        let below = await until(async: {
            seen = await header(of: 100, in: hosted)
            guard let seen else { return false }
            return seen.header.minY >= topBarsEdge(in: hosted.window) - 0.5
        }, timeout: .seconds(60))
        let edge = topBarsEdge(in: hosted.window)
        #expect(below, "header \(String(describing: seen?.header)), bars' edge \(edge)")
        let plus = try #require(seen?.plus)
        #expect(plus.maxY <= hosted.window.bounds.maxY)
        let hit = hosted.window.hitTest(CGPoint(x: plus.midX, y: plus.midY), with: nil)
        #expect(reachesThePage(plus, in: hosted), "the tap at \(plus) lands on \(String(describing: hit))")
    }

    /// Issue #641 after a landing on a message anchor: the page scrolls so that the message starts at the top bar's edge, its
    /// header just below it (the message's own padding), never under the bar; and its "+" takes the tap. Message 101 starts
    /// 1500 pixels down, below the window, until the landing.
    @Test func aLandedMessagesHeaderIsBelowTheTopBarAndItsPlusTakesTheTap() async throws {
        let hosted = try await host(target: ReaderTarget(source: .topic(readerTopic), page: 1, anchor: 101), tall: true)
        defer { hosted.window.isHidden = true }
        var seen: (header: CGRect, plus: CGRect)?
        let below = await until(async: {
            seen = await header(of: 101, in: hosted)
            guard let seen else { return false }
            let edge = topBarsEdge(in: hosted.window)
            return seen.header.minY >= edge - 0.5 && seen.header.minY <= edge + 60
        }, timeout: .seconds(60))
        #expect(below, "header \(String(describing: seen?.header)), bars' edge \(topBarsEdge(in: hosted.window))")
        let plus = try #require(seen?.plus)
        #expect(reachesThePage(plus, in: hosted), "the tap at \(plus) does not reach the page")
    }

    /// Issue #594: a tap's menu in the model is shown as the callout at the button, and closing it in the model closes it.
    @Test func theModelsMessageMenuReachesTheCallout() async throws {
        let hosted = try await host()
        defer { hosted.window.isHidden = true }
        let reader = hosted.reader
        // Out of `#require`: its expansion adds optional chaining to a trailing-closure call (`compactMap { }.first`).
        let menus = hosted.webView.interactions.compactMap { ($0 as? UIEditMenuInteraction)?.delegate as? ReaderMessageEditMenu }
        let editMenu = try #require(menus.first)
        // The view installs the menu handlers in its first task (which may rebuild the document); the menu then offers "Link"
        // (the page has a URL).
        let anchor = CGRect(x: 340, y: 300, width: 30, height: 30)
        #expect(await until({
            reader.requestMenu(post: 100, source: .message, anchor: anchor, token: reader.document?.token ?? -1)
            return reader.presentedMenu != nil
        }, timeout: .seconds(30)))
        let menu = try #require(reader.presentedMenu)
        #expect(await until({ editMenu.shownMenu == menu }, timeout: .seconds(30)), "shown: \(String(describing: editMenu.shownMenu))")
        reader.dismissMenu()
        #expect(await until({ editMenu.shownMenu == nil }, timeout: .seconds(30)))
    }
}
