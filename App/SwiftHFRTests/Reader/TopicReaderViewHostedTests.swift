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

    private func host() async throws -> Hosted {
        let pageURL = url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        let pages = FakeTopicPages { _ in
            var page = readerPage(page: 1, maxPage: 1)
            page.pageURL = pageURL
            return page
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), title: "Sujet", source: pages)
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
