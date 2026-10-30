import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// A quoting session with scripted answers. Its multi-quote cookies follow `HFRSession`'s rules (`MultiQuoteCookie`,
/// deleted when empty), and it records which of them each request carried.
actor ScriptedQuoteSession: QuotingSession {
    private let transport: MockTransport
    private var quoteCookies: [String: MultiQuoteCookie] = [:]
    /// The last token recorded, like `HFRSession.hashCheck`.
    private(set) var hashCheck: String?
    /// The quote cookies (`name=value`, sorted) the session held when each request left, in order.
    private(set) var carried: [[String]] = []

    init(_ replies: [Result<HTTPResponse, NetworkError>]) {
        transport = MockTransport(replies: replies)
    }

    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        carried.append(quoteCookies.values.map { "\($0.name)=\($0.value)" }.sorted())
        return try await transport.perform(request)
    }

    func updateHashCheck(_ value: String?) {
        if let value, !value.isEmpty { hashCheck = value }
    }

    func userKey(now: Date) -> String? {
        "user2"
    }

    func multiQuote(for token: QuoteSelectionToken, now: Date) -> MultiQuoteCookie {
        quoteCookies[MultiQuoteCookie.name(for: token)] ?? MultiQuoteCookie(token: token)
    }

    @discardableResult
    func toggleQuote(_ token: QuoteSelectionToken, now: Date) -> Bool {
        var selection = multiQuote(for: token, now: now)
        let selected = selection.toggle(token.numreponse)
        quoteCookies[selection.name] = selection.isEmpty ? nil : selection
        return selected
    }

    /// Selects `numbers` of `topic`, in order (the user tapping "answer +").
    func select(_ numbers: [Int], in topic: TopicID) {
        for number in numbers {
            toggleQuote(QuoteSelectionToken(forum: "hardwarefr", topic: topic, numreponse: number), now: Date())
        }
    }

    /// The selection of `topic` as its cookie value; empty when the cookie is gone.
    func selection(of topic: TopicID) -> String {
        multiQuote(for: QuoteSelectionToken(forum: "hardwarefr", topic: topic, numreponse: 1), now: Date()).value
    }

    /// Every request received, in order.
    var requests: [HTTPRequest] {
        get async { await transport.requests }
    }
}
