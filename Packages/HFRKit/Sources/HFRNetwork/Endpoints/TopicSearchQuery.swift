import HFRModels

/// Parameters of the intra-topic search form (HFR-PROTOCOL S3), ported from `TopicSearchParams` (`TopicSearchService.swift:11-62`).
public struct TopicSearchQuery: Sendable, Equatable {
    /// Topic searched.
    public var topic: TopicID
    /// Words to find in messages; may be empty when `author` is set.
    public var word: String
    /// Author filter (`spseudo`); may be empty when `word` is set.
    public var author: String
    /// The `filter=1` option (legacy `filterEnabled`).
    public var filterEnabled: Bool
    /// The hidden `p` value of the topic page's search form, passed through unchanged.
    public var formPage: String?
    /// `firstnum` and `currentnum` of a continued search; sent only when both are given (`fromFirstPost == false` in legacy).
    public var continuation: Continuation?

    /// Position of a search continued after its first result page.
    public struct Continuation: Sendable, Equatable {
        /// The `firstnum` value.
        public var firstNumber: String
        /// The `currentnum` value.
        public var currentNumber: String

        /// Creates a continuation.
        public init(firstNumber: String, currentNumber: String) {
            self.firstNumber = firstNumber
            self.currentNumber = currentNumber
        }
    }

    /// Creates a query; a fresh search leaves `continuation` nil.
    public init(
        topic: TopicID,
        word: String,
        author: String = "",
        filterEnabled: Bool = true,
        formPage: String? = nil,
        continuation: Continuation? = nil
    ) {
        self.topic = topic
        self.word = word
        self.author = author
        self.filterEnabled = filterEnabled
        self.formPage = formPage
        self.continuation = continuation
    }
}
