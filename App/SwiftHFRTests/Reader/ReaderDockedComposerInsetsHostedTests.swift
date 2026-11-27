import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit
import WebKit

/// #1285, #1286 (review of #1377): the real reader under its docked reply composer at its cap. The page is exactly the space between
/// the navigation bar and the bar: the web view's top inset ends at the navigation bar's bottom, its bottom one at the bar's top.
/// The reader's bottom pull icon (#1207) once gave the page a minimum height of about 135 pt: with a capped card above the
/// keyboard, the page overflowed under both bars (40 pt each on the iPhone 18 Pro simulator, iOS 27.2) and the bar with it.
@MainActor
@Suite(.serialized)
struct ReaderDockedComposerInsetsHostedTests {
    @Test(.enabled(if: UIDevice.current.userInterfaceIdiom == .phone))
    func thePageUnderADockedComposerAtItsCapEndsAtBothBars() async throws {
        let box = InsetsFramesBox()
        let pages = FakeTopicPages { _ in
            var page = quotablePage(numbers: Array(100..<110))
            page.pageURL = URL(string: "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
            return page
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), title: "Sujet", source: pages)
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        settings.set(.modernComposer, isOn: true)
        let root = DockedReaderHost(
            reader: reader, composer: ComposerFixture.services(poster: ScriptedPoster([]), drafts: drafts), settings: settings
        )
        .environment(\.composerLayoutProbe, box.probe)
        let host = UIHostingController(rootView: root)
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        // The space a keyboard leaves on a phone (a window of this size has no safe area): the capped card (six lines with no
        // keyboard measured) and the page's former 135 pt minimum do not fit together under the navigation bar.
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 420)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        try #require(await Self.until { reader.hasShownDocument && reader.replyTarget != nil }, "the page is shown")
        // A long draft: the composer opens on it, at its cap.
        let target = try #require(reader.replyTarget)
        let text = (1...30).map { "Ligne \($0) du message." }.joined(separator: "\n")
        try await drafts.save(text, for: target.draftContext, account: ComposerFixture.account)
        await reader.requestReply()
        let webView = try #require(Self.find(WKWebView.self, in: window))
        // Until the composer shows its draft and the frames and insets stop moving (four equal reads in a row, #1194).
        var last: [CGFloat] = []
        var steady = 0
        for _ in 0..<200 where steady < 4 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let insets = webView.scrollView.contentInset
            let now = [insets.top, insets.bottom, box.frames[.card]?.minY ?? -1, box.layout.text]
            steady = box.layout.text > ComposerCardLayout.maximumLines * box.layout.line && now == last ? steady + 1 : 0
            last = now
        }
        try #require(steady >= 4, "never settled: card \(String(describing: box.frames[.card])), text \(box.layout.text)")
        let navigationBottom = try #require(Self.find(UINavigationBar.self, in: window)).windowFrame(window).maxY
        let card = try #require(box.frames[.card])
        // The bar starts at the floating buttons' row: what the measured top (`ComposerCardLayout.top`) holds above the card.
        let barTop = card.minY - box.layout.top
        let insets = webView.scrollView.contentInset
        let webFrame = webView.windowFrame(window)
        #expect(abs(webFrame.minY + insets.top - navigationBottom) < 1, "top inset \(insets.top), navigation bar \(navigationBottom)")
        #expect(abs(webFrame.maxY - insets.bottom - barTop) < 1, "bottom inset \(insets.bottom), bar's top \(barTop)")
        #expect(card.maxY < window.bounds.maxY, "the card \(card) on screen")
        // The menu's confirmation sits on the page, above the bar (#853), not under it.
        HostedAccessibility.beginAutomation()
        defer { HostedAccessibility.endAutomation() }
        reader.showMenuFeedback("Lien copié")
        let feedback = { HostedAccessibility.elements(under: window).first { $0.accessibilityLabel == "Lien copié" } }
        try #require(await Self.until { feedback() != nil }, "the confirmation is shown")
        let banner = try #require(feedback()).accessibilityFrame
        #expect(banner.maxY <= barTop + 0.5 && banner.minY >= navigationBottom - 0.5, "banner \(banner), bar's top \(barTop)")
    }

    private static func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(50)) }
        return condition()
    }

    private static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let found = view as? T { return found }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
}

extension UIView {
    fileprivate func windowFrame(_ window: UIWindow) -> CGRect { convert(bounds, to: window) }
}

@MainActor
private final class InsetsFramesBox {
    var frames: [ComposerLayoutProbe.Part: CGRect] = [:]
    var layout = ComposerCardLayout()

    var probe: ComposerLayoutProbe {
        ComposerLayoutProbe(frame: { [weak self] part, frame in self?.frames[part] = frame }, layout: { [weak self] in self?.layout = $0 })
    }
}

/// The real reader in its navigation stack, its reply composer docked (« Composer moderne » on).
private struct DockedReaderHost: View {
    let reader: TopicReaderModel
    let composer: ComposerServices
    let settings: ExperimentalSettings

    var body: some View {
        NavigationStack {
            TopicReaderView(
                model: reader,
                services: ReaderServices(
                    imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
                    settings: ReaderSettings(
                        autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
                    ),
                    profiles: FakeUserProfiles([])
                ),
                composer: composer
            )
        }
        .environment(settings)
        // A short window reads as compact height, where the composer opens full: a phone in portrait, keyboard up, is regular.
        .environment(\.verticalSizeClass, .regular)
    }
}
