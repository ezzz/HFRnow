import Foundation
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
}
