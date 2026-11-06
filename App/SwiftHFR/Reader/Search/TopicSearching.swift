import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing

/// Searches one topic for the reader's search sheet: `TopicSearchFlow` in the app, a scripted double in tests.
protocol TopicSearching: Sendable {
    /// Same contract as `TopicSearchFlow.search(_:in:)`.
    func search(_ query: TopicSearchQuery) async throws(TopicSearchError) -> TopicSearchResult
}

/// LOT-046's flow over the current account's session (its `hash_check` is required, so a logged-out reader has no search).
struct LiveTopicSearcher: TopicSearching {
    let session: HFRSession
    var flow = TopicSearchFlow()

    func search(_ query: TopicSearchQuery) async throws(TopicSearchError) -> TopicSearchResult {
        try await flow.search(query, in: session)
    }
}

extension ReaderTarget {
    /// The page holding a search match, opened at its message. Only the message number is read from HFR's `Location`
    /// (`R52a`: `…&page=1&…&currentnum=2666649#t2666649`): whether its `page=` follows the match is not captured (the
    /// match of `R52a` is on page 1), so the page is left to HFR as for any `numreponse` link (`R25`, issue #106).
    /// Nil when the link names no message.
    init?(searchMatch url: URL, topic: TopicID) {
        guard let message = HFRURL.anchorPostNumber(in: url.absoluteString) else { return nil }
        self.init(source: .topic(topic), anchor: message, numreponse: message)
    }
}
