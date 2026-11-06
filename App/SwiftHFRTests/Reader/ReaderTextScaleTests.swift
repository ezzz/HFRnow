import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import WebKit

/// The in-app text size in the real reader (LOT-169): from the first render, then live without a reload.
@MainActor
@Suite(.serialized)
struct ReaderTextScaleTests: ReaderWebTesting {
    /// Body text size over the root's (`-apple-system-body`, Dynamic Type): the in-app factor.
    private let ratio = """
        const root = parseFloat(getComputedStyle(document.documentElement).fontSize);
        return parseFloat(getComputedStyle(document.querySelector('.content')).fontSize) / root;
        """

    private func factor(in controller: ReaderWebController) async -> Double {
        ((try? await evaluate(ratio, in: controller)) as? NSNumber)?.doubleValue ?? 0
    }

    @Test func theTextSizeAppliesFromTheFirstRenderThenLiveWithoutAReload() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.textScale = TextScale(percent: 70)
        // Set from the document's start, so the first layout is already at 70 %.
        let sources = controller.webView.configuration.userContentController.userScripts.map(\.source)
        #expect(sources.contains(ReaderWebController.textScaleScript(TextScale(percent: 70))))
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready)")
        let small = await until(async: { abs(await factor(in: controller) - 0.7) < 0.01 })
        let seen = await factor(in: controller)
        #expect(small, "factor: \(seen)")

        controller.textScale = TextScale(percent: 130)
        let large = await until(async: { abs(await factor(in: controller) - 1.3) < 0.01 })
        let seenLarge = await factor(in: controller)
        #expect(large, "factor: \(seenLarge)")
        // Same document: no reload, no new ready.
        #expect(recorder.ready == [1])
        #expect(controller.webView.url == ReaderWebController.pageURL(token: 1))
    }

    @Test func theScriptOnlyEverWritesAFormattedNumber() {
        #expect(ReaderWebController.textScaleScript(TextScale(percent: 85))
            == "document.documentElement.style.setProperty('--text-scale', '0.85');")
        #expect(ReaderWebController.textScaleScript(.standard).hasSuffix("'1.00');"))
    }

    /// The header at a large text size. System Dynamic Type does not reach a `WKWebView` in a test host (the host stays at its
    /// default), so `--text-scale` stands for it: it scales `body`, and the header is sized in em like at an accessibility size.
    @Test func theMessageHeaderWrapsItsAuthorSensiblyAtALargeTextSize() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let page = ReaderPage(
            topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1,
            messages: [ReaderMessage(
                numreponse: 7, author: "auteur", isDeleted: false, isContinuation: false,
                avatarURL: URL(string: "https://forum-images.hardware.fr/avatars/a.png"), dateText: "27-10-2026 10:00:00",
                editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>texte</p>")
            )]
        )
        let options = ReaderRenderOptions(showsMessageMenus: true, showsAuthorMenus: true)
        controller.show(ReaderDocument(
            token: 1, html: TopicHTMLBuilder.document(for: page, token: 1, options: options), anchor: nil, keepsScrollPosition: false
        ))
        #expect(await until { recorder.ready == [1] })
        let measure = """
            const header = document.querySelector('.message .header');
            const author = header.querySelector('.author'), button = header.querySelector('.menu-button');
            const text = document.createRange(); text.selectNodeContents(author);
            const lines = new Set([...text.getClientRects()].map(r => Math.round(r.top))).size;
            return [header.getBoundingClientRect().height, lines,
                    button.getBoundingClientRect().width, button.getBoundingClientRect().height];
            """
        let normal = try #require(try await evaluate(measure, in: controller) as? [Double])
        #expect(normal[1] == 1 && normal[0] < 40, "header at default: \(normal)")
        _ = try await evaluate("document.documentElement.style.setProperty('--text-scale', '3'); return true;", in: controller)
        let large = try #require(try await evaluate(measure, in: controller) as? [Double])
        #expect(large[1] <= 2, "author lines at 300 %: \(large)")
        // The "⋯" button stays a plain tap target (44 pt and up, not a block filling the header), and the default is unchanged.
        #expect(large[2] >= 44 && large[3] >= 44 && large[3] <= 80, "button at 300 %: \(large)")
    }
}
