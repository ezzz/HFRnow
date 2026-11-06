import HFRClient
import HFRModels
import HFRNetwork

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
    /// The page holding a search match, opened at its message. HFR's `Location` names `page=1` whatever page the match is
    /// on (`R52a`: `…&page=1&…&currentnum=2666649#t2666649`), so only the message number is read from it and the page is
    /// left to HFR as for any `numreponse` link (`R25`, issue #106). Nil when the link names no message.
    init?(searchMatch url: URL, topic: TopicID) {
        guard let message = HFRURL.anchorPostNumber(in: url.absoluteString) else { return nil }
        self.init(source: .topic(topic), anchor: message, numreponse: message)
    }
}
