import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// Issue #750: SwiftUI sends `onDisappear` to a reader pushed again in a collapsed split view, before its web view is in a
/// window, and never `onAppear` again. The web view's window decides whether the reader is on screen.
@MainActor
@Suite(.serialized)
struct ReaderPresenceWebTests: ReaderWebTesting {
    /// The reopen of #750 as measured: the document is handed, the load is stopped while the web view is on its way in, then
    /// the web view enters its window. The page must load (before the fix: "show skipped: stopped" forever).
    @Test func aReaderStoppedOnItsWayInLoadsOnceItsWebViewIsInAWindow() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let window = try #require(recorder.window)
        controller.webView.removeFromSuperview()
        controller.show(document(token: 1))
        controller.stopLoading()
        #expect(await until({ !recorder.ready.isEmpty }, timeout: .seconds(2)) == false, "ready before the window")
        window.addSubview(controller.webView)
        #expect(await until({ recorder.ready == [1] }, timeout: .seconds(120)), "ready: \(recorder.ready)")
    }

    /// The same sequence through the lifecycle calls: the disappearance out of a window leaves, the window brings it back.
    @Test func aDisappearanceBeforeTheWindowLeavesAndTheWindowBringsTheReaderBack() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let window = try #require(recorder.window)
        var left = 0
        var returned = 0
        controller.events.left = { left += 1; controller.stopLoading() }
        controller.events.returned = { returned += 1 }
        controller.webView.removeFromSuperview()
        controller.viewAppeared()
        controller.show(document(token: 1))
        controller.viewDisappeared()
        #expect(left == 1)
        window.addSubview(controller.webView)
        #expect(returned == 1)
        #expect(await until({ recorder.ready == [1] }, timeout: .seconds(120)), "ready: \(recorder.ready)")
    }

    /// A disappearance while the web view is in a window changes nothing; its leaving the window then is the real leave.
    @Test func aDisappearanceInAWindowWaitsForTheWebViewToLeaveIt() throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        _ = try #require(recorder.window)
        var left = 0
        controller.events.left = { left += 1; controller.stopLoading() }
        controller.viewAppeared()
        controller.show(document(token: 1))
        controller.viewDisappeared()
        #expect(left == 0)
        controller.webView.removeFromSuperview()
        #expect(left == 1)
    }

    /// A real leave (the web view leaves its window first, then `onDisappear`) leaves once; a window change of a reader on
    /// screen (no stop) brings nothing back.
    @Test func aRealLeaveLeavesOnceAndAnAppearedReaderIsNotBroughtBack() throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let window = try #require(recorder.window)
        var left = 0
        var returned = 0
        controller.events.left = { left += 1; controller.stopLoading() }
        controller.events.returned = { returned += 1 }
        controller.viewAppeared()
        controller.webView.removeFromSuperview()
        window.addSubview(controller.webView)
        #expect(left == 0)
        #expect(returned == 0)
        controller.webView.removeFromSuperview()
        controller.viewDisappeared()
        #expect(left == 1)
    }
}
