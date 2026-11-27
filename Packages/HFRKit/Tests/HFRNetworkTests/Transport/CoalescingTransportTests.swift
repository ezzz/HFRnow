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
            // Every caller has joined the exchange in flight before the server answers (a condition, not a delay).
            while transport.waitingCallers < 35 { await Task.yield() }
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
            // Every GET has joined (a write is never a waiter); a write is held at the base, so it is waited for there.
            let gets = requests.filter { $0.method == .get && $0.body == nil }.count
            let writes = requests.count - gets
            while true {
                let reached = await base.requests.count
                if transport.waitingCallers >= gets, reached >= writes + (gets > 0 ? 1 : 0) { break }
                await Task.yield()
            }
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

    /// A one-shot signal: `wait()` returns once `fire()` has been called, however the two interleave.
    private actor Signal {
        private(set) var isFired = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func fire() { isFired = true; waiters.forEach { $0.resume() }; waiters = [] }
        func wait() async { if !isFired { await withCheckedContinuation { waiters.append($0) } } }
    }

    /// A transport whose exchange stays open until `release` fires or the exchange is cancelled; no clock involved.
    private final class Blocking: HTTPTransport, Sendable {
        let started = Signal()
        let release = Signal()
        let wasCancelled = Signal()

        func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
            await started.fire()
            await withTaskCancellationHandler {
                await release.wait()
            } onCancel: {
                Task { await self.wasCancelled.fire(); await self.release.fire() }
            }
            if Task.isCancelled { throw .cancelled }
            return HTTPResponse(statusCode: 200, url: request.url)
        }
    }

    /// A cancelled caller ends its wait while the exchange is still open; the exchange goes on for the callers that remain.
    @Test func aCancelledWaiterLeavesAtOnceAndTheExchangeServesTheOthers() async throws {
        let blocking = Blocking()
        let transport = CoalescingTransport(base: blocking)
        let url = image
        let first = Task { try await transport.perform(.get(url)) }
        let second = Task { try await transport.perform(.get(url)) }
        await blocking.started.wait()
        // Both callers have joined before one leaves (a condition, not a delay).
        while transport.waitingCallers < 2 { await Task.yield() }
        first.cancel()
        // Returns while the base is still blocked: had the cancelled caller waited for the download this would never return.
        await #expect(throws: NetworkError.cancelled) { try await first.value }
        #expect(await blocking.release.isFired == false)
        await blocking.release.fire()
        #expect(try await second.value.statusCode == 200)
        #expect(await blocking.wasCancelled.isFired == false)
    }

    /// The last waiter leaving cancels the exchange, so an abandoned download does not run on.
    @Test func theLastWaiterLeavingCancelsTheExchange() async throws {
        let blocking = Blocking()
        let transport = CoalescingTransport(base: blocking)
        let url = image
        let only = Task { try await transport.perform(.get(url)) }
        await blocking.started.wait()
        only.cancel()
        await #expect(throws: NetworkError.cancelled) { try await only.value }
        // Never returns if the exchange were left running.
        await blocking.wasCancelled.wait()
    }

    /// A caller already cancelled when it arrives starts nothing.
    @Test func aCallerCancelledBeforeItJoinsStartsNothing() async {
        let blocking = Blocking()
        let transport = CoalescingTransport(base: blocking)
        // The request is built outside the closure, and the closure returns the error as a value: a typed-throws closure capturing
        // a value here crashed the compiler (SIL ownership error, #1405).
        let request = HTTPRequest.get(image)
        let task = Task { () async -> NetworkError? in
            while !Task.isCancelled { await Task.yield() }
            do throws(NetworkError) {
                _ = try await transport.perform(request)
                return nil
            } catch {
                return error
            }
        }
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(await blocking.started.isFired == false)
    }
}
