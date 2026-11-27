import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// Issue #672 in the real web view: `reader.js` tells the app whether a touch started inside a block that scrolls sideways
/// (legacy `horizontalScrollTouchTrackingScript`, `MessagesView.swift:1102-1142` @ 87fe0d1c), so the page swipe leaves that
/// drag to the block.
@MainActor
@Suite(.serialized)
struct ReaderHorizontalScrollerWebTests: ReaderWebTesting {
    private let content = """
        <div id="scroller" style="overflow-x:auto;width:100px"><span id="deep" style="display:inline-block;width:3000px">x</span></div>
        <div id="short" style="overflow-x:auto;width:300px"><span id="small">y</span></div>
        <table class="fixed" id="block"><tr><td><span id="wide" style="display:inline-block;width:3000px">z</span></td></tr></table>
        <div id="visible" style="overflow-x:visible;width:100px"><span id="spill" style="display:inline-block;width:3000px">v</span></div>
        <p id="plain">texte</p>
        """

    private func touch(_ id: String, in controller: ReaderWebController) async throws {
        let script = "document.getElementById('\(id)').dispatchEvent(new Event('touchstart', { bubbles: true })); return true;"
        _ = try await evaluate(script, in: controller)
    }

    @Test func aTouchInsideASidewaysBlockIsReportedAndTheNextOutsideResetsIt() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        #expect(controller.touchStartedInScroller == false)

        try await touch("deep", in: controller) // a descendant of the scrolling block
        #expect(await until { controller.touchStartedInScroller }, "a touch inside the block was not reported")

        try await touch("plain", in: controller)
        #expect(await until { !controller.touchStartedInScroller }, "the next touch outside must reset the flag")

        try await touch("wide", in: controller) // inside the cell of a [fixed] block, which scrolls (reader.css:196)
        #expect(await until { controller.touchStartedInScroller }, "a touch inside a [fixed] block was not reported")
    }

    @Test func aBlockThatDoesNotOverflowIsNotAScroller() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        try await touch("deep", in: controller)
        #expect(await until { controller.touchStartedInScroller })
        try await touch("small", in: controller) // overflow-x: auto but nothing to scroll
        #expect(await until { !controller.touchStartedInScroller }, "a block with no overflow must not own the touch")
    }

    /// A box wider than itself that does not scroll (`overflow-x: visible`) is no scroller: only `overflow-x` auto or scroll counts.
    @Test func aWideChildInAnOverflowVisibleBoxIsNotAScroller() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        try await touch("deep", in: controller)
        #expect(await until { controller.touchStartedInScroller })
        try await touch("spill", in: controller)
        #expect(await until { !controller.touchStartedInScroller }, "a box that does not scroll must not own the touch")
    }

    @Test func aNewDocumentStartsWithNoScrollerTouch() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        try await touch("deep", in: controller)
        #expect(await until { controller.touchStartedInScroller })
        controller.show(document(token: 2, content: content)) // a page change
        #expect(controller.touchStartedInScroller == false, "the first swipe on the new page must work")
        #expect(await until { recorder.ready == [1, 2] })
        #expect(controller.touchStartedInScroller == false)
    }
}
