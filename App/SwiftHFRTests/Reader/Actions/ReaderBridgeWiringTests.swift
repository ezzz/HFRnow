import Foundation
import HFRNetwork
@testable import SwiftHFR
import Testing

/// One menu event as the screen receives it.
private struct MenuEvent: Equatable {
    let post: Int
    let source: MessageMenuSource
    let token: Int
}

/// What a decoded bridge message does in the controller: the path from `reader.js` to the screen's events.
@MainActor
struct ReaderBridgeWiringTests: ReaderWebTesting {
    @Test func aMenuMessageReachesTheScreenWithItsDocumentToken() {
        let (controller, _) = makeController(transport: imageTransport())
        var received: [MenuEvent] = []
        controller.events.menu = { post, source, token in received.append(MenuEvent(post: post, source: source, token: token)) }
        let shown = document(token: 7)
        _ = controller.handle(.menu(post: 42, source: .avatar), in: shown)
        _ = controller.handle(.menu(post: 43, source: .message), in: shown)
        #expect(received == [MenuEvent(post: 42, source: .avatar, token: 7), MenuEvent(post: 43, source: .message, token: 7)])
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
