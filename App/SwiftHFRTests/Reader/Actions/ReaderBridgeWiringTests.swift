import Foundation
import HFRNetwork
@testable import SwiftHFR
import Testing

/// What a decoded bridge message does in the controller: the path from `reader.js` to the screen's events.
@MainActor
struct ReaderBridgeWiringTests: ReaderWebTesting {
    @Test func aMenuMessageReachesTheScreenWithItsDocumentToken() {
        let (controller, _) = makeController(transport: imageTransport())
        var received: [(Int, MessageMenuSource, Int)] = []
        controller.events.menu = { post, source, token in received.append((post, source, token)) }
        let shown = document(token: 7)
        _ = controller.handle(.menu(post: 42, source: .avatar), in: shown)
        _ = controller.handle(.menu(post: 43, source: .message), in: shown)
        #expect(received.map(\.0) == [42, 43])
        #expect(received.map(\.1) == [.avatar, .message])
        #expect(received.map(\.2) == [7, 7])
    }
}
