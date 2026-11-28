import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import HFRNetwork

/// #1398: a transport invalidates the `URLSession` it was handed to own when it is released, and only that one. Offline.
struct URLSessionTransportOwnershipTests {
    /// Records the session's end (`didBecomeInvalidWithError`).
    private final class InvalidationWatch: NSObject, URLSessionDelegate, Sendable {
        private let ended = Mutex(false)
        var hasEnded: Bool { ended.withLock { $0 } }

        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
            ended.withLock { $0 = true }
        }
    }

    /// Whether the watched session ended within about two seconds of the transport's release.
    private static func endsAfterRelease(owned: Bool) async throws -> Bool {
        let watch = InvalidationWatch()
        let session = URLSession(configuration: .ephemeral, delegate: watch, delegateQueue: nil)
        do {
            let transport = owned ? URLSessionTransport(ownedSession: session) : URLSessionTransport(session: session)
            _ = transport
        }
        for _ in 0..<40 where !watch.hasEnded { try await Task.sleep(for: .milliseconds(50)) }
        let ended = watch.hasEnded
        if !owned { session.finishTasksAndInvalidate() }
        return ended
    }

    @Test func anOwnedSessionEndsWithItsTransport() async throws {
        #expect(try await Self.endsAfterRelease(owned: true))
    }

    @Test func aSessionOfTheCallerOutlivesTheTransport() async throws {
        #expect(try await !Self.endsAfterRelease(owned: false))
    }

    @Test func theTransportsThatCreateTheirSessionOwnIt() {
        #expect(URLSessionTransport().ownsSession)
        #expect(!URLSessionTransport(session: .shared).ownsSession)
    }
}
