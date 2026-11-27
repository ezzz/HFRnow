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

    @Test func differentURLsAreNotMerged() async throws {
        let gate = Gate()
        let (base, transport) = make(gate: gate)
        await gate.release()
        _ = try await transport.perform(.get(image))
        _ = try await transport.perform(.get(image.appending(path: "other")))
        #expect(await base.requests.count == 2)
    }

    @Test func aFinishedExchangeIsNotReusedAndFailuresAreNotRemembered() async throws {
        let base = MockTransport(replies: [
            .failure(.unscripted), .success(HTTPResponse(statusCode: 200, url: image)), .success(HTTPResponse(statusCode: 200, url: image)),
        ])
        let transport = CoalescingTransport(base: base)
        await #expect(throws: NetworkError.self) { try await transport.perform(.get(image)) }
        _ = try await transport.perform(.get(image))
        _ = try await transport.perform(.get(image))
        #expect(await base.requests.count == 3)
    }

    @Test func writesAreNeverMerged() async throws {
        let gate = Gate()
        let (base, transport) = make(gate: gate)
        await gate.release()
        let post = HTTPRequest(url: image, method: .post, body: Data("a=1".utf8))
        _ = try await transport.perform(post)
        _ = try await transport.perform(post)
        #expect(await base.requests.count == 2)
    }
}
