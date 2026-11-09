import Foundation
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// The Giphy double of the GIF panel's tests: the real `GiphyClient` over a `MockTransport` answering the recorded `T40` (search) and
/// `T41` (trending); no network, a fake key.
enum GifTestSupport {
    static let fakeKey = "DUMMYKEY0123"
    static let base = URL(string: "https://api.giphy.com")!
    /// The id of the first GIF of `T40`.
    static let firstSearchID = "xT9IgG50Fb7Mi0prBC"

    static func capture(_ name: String) throws -> Data {
        let captures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures")
        return try Data(contentsOf: captures.appending(path: name))
    }

    /// The capture with `change` applied to its JSON.
    static func edited(_ name: String, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: capture(name)) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes])
    }

    /// What a test changes in the answers and how the requests behave. Requests are numbered from 0.
    struct Script {
        /// Edits the JSON of both captures.
        var edit: ((inout [String: Any]) -> Void)?
        /// Swaps a text in both bodies (a host off Giphy's CDN).
        var rewriting: (from: String, to: String)?
        /// These requests go offline.
        var failing: Set<Int> = []
        /// These requests answer an empty page.
        var empty: Set<Int> = []
        /// These requests wait on their gate before answering.
        var gates: [Int: ReaderGate] = [:]
    }

    static func giphy(_ script: Script = Script()) throws -> (MockTransport, GiphyClient) {
        func body(_ name: String) throws -> Data {
            var data = try edited(name) { json in script.edit?(&json) }
            if let swap = script.rewriting {
                let text = try #require(String(bytes: data, encoding: .utf8))
                data = Data(text.replacing(swap.from, with: swap.to).utf8)
            }
            return data
        }
        let (search, trending) = (try body("T40-giphy-search.json"), try body("T41-giphy-trending.json"))
        let none = try edited("T41-giphy-trending.json") { $0["data"] = [Any]() }
        let (failing, empty, gates) = (script.failing, script.empty, script.gates)
        let calls = Counter()
        let transport = MockTransport { request async throws(NetworkError) -> HTTPResponse in
            let index = calls.next()
            if let gate = gates[index] { await gate.wait() }
            if failing.contains(index) { throw .offline }
            let answer = empty.contains(index) ? none : request.url.path().hasSuffix("/search") ? search : trending
            return HTTPResponse(statusCode: 200, url: request.url, body: answer)
        }
        let configuration = try GiphyConfiguration(baseURL: base, apiKey: fakeKey)
        return (transport, GiphyClient(configuration: configuration, transport: transport))
    }

    @MainActor
    static func model(_ client: GiphyClient?, accepted: Bool) -> (GifPickerModel, InMemorySettingsStore) {
        let settings = InMemorySettingsStore(accepted ? [GifPickerModel.noticeKey: .bool(true)] : [:])
        let services = GifServices(client: client, hostName: "api.giphy.com", settings: settings)
        return (GifPickerModel(services: services), settings)
    }
}

/// A thread-safe call counter: `next()` returns 0, 1, 2…
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        defer { count += 1 }
        return count
    }
}
