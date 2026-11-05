import Foundation
@testable import SwiftHFR
import Testing

/// The typed bridge: five known names, exact shapes, everything else rejected (LOT-087, audit C14).
struct ReaderBridgeMessageTests {
    private func decode(_ body: Any) -> Result<ReaderBridgeMessage.Decoded, ReaderBridgeMessage.Failure> {
        do throws(ReaderBridgeMessage.Failure) { return .success(try ReaderBridgeMessage.decode(body)) } catch { return .failure(error) }
    }

    @Test func everyKnownMessageDecodes() {
        #expect(decode(["type": "ready", "token": 3]) == .success(.init(token: 3, message: .ready)))
        #expect(decode(["type": "tap", "token": 3, "url": "https://x.test/a.png"])
            == .success(.init(token: 3, message: .tap(url: "https://x.test/a.png"))))
        #expect(decode(["type": "video", "token": 3, "post": 42, "index": 0])
            == .success(.init(token: 3, message: .video(post: 42, index: 0))))
        #expect(decode(["type": "menu", "token": 3, "post": 42, "source": "message"])
            == .success(.init(token: 3, message: .menu(post: 42, source: .message))))
        #expect(decode(["type": "menu", "token": 3, "post": 42, "source": "avatar"])
            == .success(.init(token: 3, message: .menu(post: 42, source: .avatar))))
        #expect(decode(["type": "images", "token": 3, "urls": ["a", 7, "b"] as [Any]])
            == .success(.init(token: 3, message: .images(["a", nil, "b"]))))
    }

    @Test func unknownNamesAreRejected() {
        #expect(decode(["type": "eval", "token": 1, "code": "alert(1)"]) == .failure(.unknownType))
        #expect(decode(["type": "Menu", "token": 1, "post": 1, "source": "message"]) == .failure(.unknownType))
        #expect(decode(["type": "", "token": 1]) == .failure(.unknownType))
    }

    @Test func malformedBodiesAreRejected() {
        #expect(decode("menu") == .failure(.malformed))
        #expect(decode(42) == .failure(.malformed))
        #expect(decode([Any]()) == .failure(.malformed))
        #expect(decode(["token": 1]) == .failure(.malformed))
        #expect(decode(["type": "ready"]) == .failure(.malformed))
        #expect(decode(["type": 5, "token": 1]) == .failure(.malformed))
        #expect(decode(["type": "ready", "token": "1"]) == .failure(.malformed))
        #expect(decode(["type": "ready", "token": true]) == .failure(.malformed))
        #expect(decode(["type": "ready", "token": 1.5]) == .failure(.malformed))
    }

    @Test func aKnownNameWithAWrongPayloadIsRejectedWhole() {
        let base: [String: Any] = ["type": "menu", "token": 1]
        #expect(decode(base) == .failure(.invalidPayload))
        #expect(decode(base.merging(["post": 42, "source": "other"]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["post": 42]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["post": 0, "source": "message"]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["post": -3, "source": "message"]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["post": "42", "source": "message"]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["post": 4.2, "source": "message"]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["post": true, "source": "message"]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(["type": "video", "token": 1, "post": 42, "index": -1]) == .failure(.invalidPayload))
        #expect(decode(["type": "video", "token": 1, "post": 42]) == .failure(.invalidPayload))
        #expect(decode(["type": "tap", "token": 1]) == .failure(.invalidPayload))
        #expect(decode(["type": "tap", "token": 1, "url": 5]) == .failure(.invalidPayload))
        #expect(decode(["type": "images", "token": 1, "urls": "a"]) == .failure(.invalidPayload))
    }

    @Test func theImageListIsBounded() throws {
        let urls = Array(repeating: "a", count: ReaderBridgeMessage.maximumImages + 10) as [Any]
        let decoded = try ReaderBridgeMessage.decode(["type": "images", "token": 1, "urls": urls])
        guard case .images(let kept) = decoded.message else { Issue.record("not images"); return }
        #expect(kept.count == ReaderBridgeMessage.maximumImages)
    }
}
