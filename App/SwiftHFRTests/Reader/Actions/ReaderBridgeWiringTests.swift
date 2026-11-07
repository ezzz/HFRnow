import Foundation
import HFRNetwork
@testable import SwiftHFR
import Testing
import UIKit

/// One menu event as the screen receives it.
private struct MenuEvent: Equatable {
    let post: Int
    let source: MessageMenuSource
    let token: Int
    var anchor: CGRect?
}

/// What a decoded bridge message does in the controller: the path from `reader.js` to the screen's events.
@MainActor
struct ReaderBridgeWiringTests: ReaderWebTesting {
    @Test func aMenuMessageReachesTheScreenWithItsDocumentToken() {
        let (controller, _) = makeController(transport: imageTransport())
        var received: [MenuEvent] = []
        controller.events.menu = { post, source, anchor, token in
            received.append(MenuEvent(post: post, source: source, token: token, anchor: anchor))
        }
        let shown = document(token: 7)
        _ = controller.handle(.menu(post: 42, source: .avatar, anchor: nil), in: shown)
        _ = controller.handle(.menu(post: 43, source: .message, anchor: nil), in: shown)
        #expect(received == [MenuEvent(post: 42, source: .avatar, token: 7), MenuEvent(post: 43, source: .message, token: 7)])
    }

    @Test func theMenuAnchorIsMovedBelowTheBarsThePageRunsUnder() {
        let (controller, _) = makeController(transport: imageTransport())
        controller.obscuredInsets = UIEdgeInsets(top: 100, left: 0, bottom: 0, right: 0)
        var received: [CGRect?] = []
        controller.events.menu = { _, _, anchor, _ in received.append(anchor) }
        let rect = CGRect(x: 300, y: 20, width: 30, height: 30)
        _ = controller.handle(.menu(post: 42, source: .message, anchor: rect), in: document(token: 1))
        #expect(received == [CGRect(x: 300, y: 120, width: 30, height: 30)])
    }

    @Test func aQuoteMessageReachesTheScreenWithItsDocumentToken() {
        let (controller, _) = makeController(transport: imageTransport())
        var received: [String] = []
        controller.events.quote = { post, text, bold, token in received.append("\(post)|\(text)|\(bold)|\(token)") }
        let shown = document(token: 7)
        _ = controller.handle(.quote(post: 42, text: "tout", bold: true), in: shown)
        #expect(received == ["42|tout|true|7"])
    }
}
