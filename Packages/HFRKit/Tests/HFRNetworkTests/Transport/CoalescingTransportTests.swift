import Foundation
import Testing
@testable import HFRNetwork

/// Concurrent identical GETs share one exchange (#1397): a smiley picker of 35 cells, or several readers showing the same avatar,
/// must not open one connection per cell.
struct CoalescingTransportTests {
    /// Holds every request until `release()`, so the callers overlap.
    private actor Gate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async { if !open { await withCheckedContinuation { waiters.append($0) } } }
        func release() { open = true; waiters.forEach { $0.resume() }; waiters = [] }
    }

    private let image = URL(string: "https://forum-images.hardware.fr/icones/smiley.gif")!

    private func make(gate: Gate) -> (MockTransport, CoalescingTransport) {
        let base = MockTransport { request async throws(NetworkError) -> HTTPResponse in
            await gate.wait()
            return HTTPResponse(statusCode: 200, url: request.url, body: Data(request.url.absoluteString.utf8))
        }
        return (base, CoalescingTransport(base: base))
    }

    @Test func manyCellsWithTheSameURLCostOneRequest() async throws {
        let gate = Gate()
        let (base, transport) = make(gate: gate)
        let url = image
        let answers = await withTaskGroup(of: HTTPResponse?.self) { group in
            for _ in 0..<35 { group.addTask { try? await transport.perform(.get(url)) } }
            // Let every caller join the exchange in flight before the server answers.
            try? await Task.sleep(for: .milliseconds(200))
            await gate.release()
            var all: [HTTPResponse?] = []
            for await answer in group { all.append(answer) }
            return all
        }
        #expect(answers.count == 35)
        #expect(answers.allSatisfy { $0?.statusCode == 200 && $0?.body == Data(url.absoluteString.utf8) })
        #expect(await base.requests.count == 1)
    }

    /// Runs `requests` at once against a held transport, answers them all, and returns how many reached the base.
    private func requestsReachingBase(_ requests: [HTTPRequest]) async -> Int {
        let gate = Gate()
        let (base, transport) = make(gate: gate)
        await withTaskGroup(of: Void.self) { group in
            for request in requests { group.addTask { _ = try? await transport.perform(request) } }
            try? await Task.sleep(for: .milliseconds(200))
            await gate.release()
        }
        return await base.requests.count
    }

    @Test func requestsThatDifferInAnyFieldAreNotMerged() async {
        let get = HTTPRequest.get(image)
        #expect(await requestsReachingBase([get, .get(image.appending(path: "other"))]) == 2)
        #expect(await requestsReachingBase([get, .get(image, headers: ["Referer": "https://forum.hardware.fr/"])]) == 2)
        #expect(await requestsReachingBase([get, .get(image, redirectPolicy: .doNotFollow)]) == 2)
        let noFollow = HTTPRequest.get(image, redirectPolicy: .doNotFollow)
        #expect(await requestsReachingBase([get, noFollow, noFollow]) == 2)
    }

    @Test func aFailedExchangeIsNotReplayedToALaterCaller() async throws {
        let base = MockTransport(replies: [
            .failure(.unscripted), .success(HTTPResponse(statusCode: 200, url: image)), .success(HTTPResponse(statusCode: 200, url: image))
        ])
        let transport = CoalescingTransport(base: base)
        await #expect(throws: NetworkError.self) { try await transport.perform(.get(image)) }
        _ = try await transport.perform(.get(image))
        _ = try await transport.perform(.get(image))
        #expect(await base.requests.count == 3)
    }

    @Test func writesAreNeverMerged() async {
        let post = HTTPRequest(url: image, method: .post, body: Data("a=1".utf8))
        #expect(await requestsReachingBase([post, post]) == 2)
    }

    /// Counts the exchanges started and the ones cancelled; each runs until released or cancelled.
    private final class Slow: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var started = 0
        private var cancelled = 0
        var counts: (started: Int, cancelled: Int) { lock.withLock { (started, cancelled) } }

        func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
            lock.withLock { started += 1 }
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled {
                lock.withLock { cancelled += 1 }
                throw .cancelled
            }
            return HTTPResponse(statusCode: 200, url: request.url)
        }
    }

    /// A cancelled caller stops waiting at once; the exchange is cancelled only when its last waiter has left.
    @Test func cancellingTheLastWaiterCancelsTheExchangeAndEndsItsWaitAtOnce() async throws {
        let slow = Slow()
        let transport = CoalescingTransport(base: slow)
        let url = image
        let first = Task { try await transport.perform(.get(url)) }
        let second = Task { try await transport.perform(.get(url)) }
        try await Task.sleep(for: .milliseconds(100))
        let began = ContinuousClock.now
        first.cancel()
        await #expect(throws: NetworkError.cancelled) { try await first.value }
        // One waiter is left: the exchange goes on.
        try await Task.sleep(for: .milliseconds(100))
        #expect(slow.counts.cancelled == 0)
        second.cancel()
        await #expect(throws: NetworkError.cancelled) { try await second.value }
        #expect(ContinuousClock.now - began < .seconds(1), "a cancelled caller waited for the download")
        try await Task.sleep(for: .milliseconds(2300))
        #expect(slow.counts == (started: 1, cancelled: 1))
    }
}
