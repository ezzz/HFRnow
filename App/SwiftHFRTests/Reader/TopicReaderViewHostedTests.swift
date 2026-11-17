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

    /// The page the reader gets: `readerPage`'s two short posts (100, 101), its first post alone, or two 1500-pixel posts so
    /// that a landing on 101 has to scroll.
    enum Shape: Sendable { case twoPosts, onePost, tall }

    private func host(
        target: ReaderTarget = ReaderTarget(source: .topic(readerTopic), page: 1), shape: Shape = .twoPosts
    ) async throws -> Hosted {
        let pageURL = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        let pages = FakeTopicPages { _ in
            var page = shape == .tall ? Self.tallPage() : readerPage(page: 1, maxPage: 1)
            if shape == .onePost { page.messages.removeLast() }
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

    /// The lower edge of the top bars in window coordinates: the visible navigation bar's. Nil without one, so a test can never
    /// fall back to a lower edge (the status bar) and pass with the header under a bar it did not find.
    private func topBarsEdge(in window: UIWindow) -> CGFloat? {
        func bars(in view: UIView) -> [UINavigationBar] {
            ((view as? UINavigationBar).map { [$0] } ?? []) + view.subviews.flatMap { bars(in: $0) }
        }
        let shown = bars(in: window).filter { !$0.isHidden && $0.alpha > 0 && $0.window != nil }
        return shown.map { $0.convert($0.bounds, to: window).maxY }.max()
    }

    /// The shown document is loaded and its images have finished. The landing or WebKit's reset to the top run two frames after
    /// the document is ready (`afterFirstFrames`, #642): the caller waits a second more before it measures.
    private func settled(_ hosted: Hosted) async -> Bool {
        let script = "return document.readyState === 'complete' && Array.from(document.images).every((i) => i.complete);"
        let web = hosted.webView
        return await until(async: {
            let done = try? await answer(of: "the reader page", within: WaitBudget.cap(.seconds(10))) {
                try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: ReaderWebController.world)
            }
            return (done as? Bool) == true && hosted.reader.hasShownDocument
        }, timeout: .seconds(60))
    }

    /// Message `post`'s header lies between the bars' edge and `slack` points below it, and its "+" takes the tap; checked once
    /// the page has settled, then again a second later, so a late scroll that puts it back under the bar fails the test.
    private func expectHeaderBelowTheBar(of post: Int, in hosted: Hosted, slack: CGFloat) async throws {
        #expect(await until({ topBarsEdge(in: hosted.window) != nil }, timeout: .seconds(30)))
        let edge = try #require(topBarsEdge(in: hosted.window), "no visible navigation bar")
        var seen: (header: CGRect, plus: CGRect)?
        let below = await until(async: {
            seen = await header(of: post, in: hosted)
            guard let seen else { return false }
            return seen.header.minY >= edge - 0.5 && seen.header.minY <= edge + slack
        }, timeout: .seconds(60))
        #expect(below, "header \(String(describing: seen?.header)), bars' edge \(edge)")
        #expect(await settled(hosted))
        try await Task.sleep(for: .seconds(1))
        let last = try #require(await header(of: post, in: hosted))
        #expect(last.header.minY >= edge - 0.5 && last.header.minY <= edge + slack, "settled header \(last.header), edge \(edge)")
        #expect(last.plus.maxY <= hosted.window.bounds.maxY)
        let hit = hosted.window.hitTest(CGPoint(x: last.plus.midX, y: last.plus.midY), with: nil)
        #expect(hit?.isDescendant(of: hosted.webView) == true, "the tap at \(last.plus) lands on \(String(describing: hit))")
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

    /// Issue #641, as seen on screen: once the page is shown at its top, the first post's header (avatar, pseudo, date, "+") is
    /// entirely below the top bar, at most the post's own padding below it, and a tap on its "+" reaches the page, on a page of
    /// two posts and on a one-post page (where no other post's menu could stand in). Before #878 the web view got no top inset
    /// and the header sat at y 5-53 under the status bar and the bar, where a tap opened nothing.
    @Test(arguments: [Shape.twoPosts, .onePost])
    func theFirstPostsHeaderOpensBelowTheTopBarAndItsPlusTakesTheTap(shape: Shape) async throws {
        let hosted = try await host(shape: shape)
        defer { hosted.window.isHidden = true }
        try await expectHeaderBelowTheBar(of: 100, in: hosted, slack: 60)
    }

    /// Issue #641 after a landing on a message anchor: the page scrolls so that the message starts at the top bar's edge, its
    /// header just below it (the message's own padding), never under the bar; and its "+" takes the tap. Message 101 starts
    /// 1500 pixels down, below the window, until the landing.
    @Test func aLandedMessagesHeaderIsBelowTheTopBarAndItsPlusTakesTheTap() async throws {
        let hosted = try await host(target: ReaderTarget(source: .topic(readerTopic), page: 1, anchor: 101), shape: .tall)
        defer { hosted.window.isHidden = true }
        try await expectHeaderBelowTheBar(of: 101, in: hosted, slack: 60)
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
