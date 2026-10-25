/// One row of a topic list (forum, private messages, favourites or search results).
public struct TopicSummary: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: the category/topic pair when known, else the title path. Never empty, never random.
    public var id: String {
        if let topicID {
            return "topic:\(topicID.category.queryValue)-\(topicID.topic)"
        }
        return "path:\(path)"
    }

    /// Category and topic numbers, nil when they cannot be read from the row's links.
    public var topicID: TopicID?
    /// Title as HFR serves it; display rewrites (such as the legacy "TU" normalisation) are a presentation concern.
    public var title: String
    /// Path of the title link, relative to the forum base URL.
    public var path: String
    /// Path of the first page (favourites rows only).
    public var firstPagePath: String?
    /// Number of replies shown in the row.
    public var repliesCount: Int
    /// Number of pages, at least 1 (smaller values are raised to 1).
    public var pageCount: Int {
        didSet { pageCount = max(1, pageCount) }
    }
    /// Path of the last page (the title path when the topic has a single page).
    public var lastPagePath: String
    /// Latest message, when the row shows one.
    public var lastPost: LastPost?
    /// Topic starter, or the interlocutor(s) in the private messages list.
    public var starterOrInterlocutors: String
    /// Flag colour, when the row has a flag.
    public var flag: TopicFlag?
    /// Path of the flag link, which resumes at the last read position.
    public var flagPath: String?
    /// Page of the last read position, read from the flag link.
    public var currentPage: Int?
    /// Whether the row announces unread replies.
    public var readState: TopicReadState
    /// Sticky topic.
    public var isSticky: Bool
    /// Closed topic.
    public var isClosed: Bool
    /// Topic with a poll.
    public var isPoll: Bool
    /// Matching message and excerpt (search results only).
    public var searchHit: SearchHit?

    /// Creates a topic row; `pageCount` is raised to at least 1.
    public init(
        topicID: TopicID? = nil,
        title: String,
        path: String,
        firstPagePath: String? = nil,
        repliesCount: Int = 0,
        pageCount: Int = 1,
        lastPagePath: String? = nil,
        lastPost: LastPost? = nil,
        starterOrInterlocutors: String = "",
        flag: TopicFlag? = nil,
        flagPath: String? = nil,
        currentPage: Int? = nil,
        readState: TopicReadState = .unknown,
        isSticky: Bool = false,
        isClosed: Bool = false,
        isPoll: Bool = false,
        searchHit: SearchHit? = nil
    ) {
        self.topicID = topicID
        self.title = title
        self.path = path
        self.firstPagePath = firstPagePath
        self.repliesCount = repliesCount
        self.pageCount = max(1, pageCount)
        self.lastPagePath = lastPagePath ?? path
        self.lastPost = lastPost
        self.starterOrInterlocutors = starterOrInterlocutors
        self.flag = flag
        self.flagPath = flagPath
        self.currentPage = currentPage
        self.readState = readState
        self.isSticky = isSticky
        self.isClosed = isClosed
        self.isPoll = isPoll
        self.searchHit = searchHit
    }

    private enum CodingKeys: String, CodingKey {
        case topicID, title, path, firstPagePath, repliesCount, pageCount, lastPagePath, lastPost
        case starterOrInterlocutors, flag, flagPath, currentPage, readState, isSticky, isClosed, isPoll, searchHit
    }

    /// Decodes a row and applies the same `pageCount` floor as the initializer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            topicID: try container.decodeIfPresent(TopicID.self, forKey: .topicID),
            title: try container.decode(String.self, forKey: .title),
            path: try container.decode(String.self, forKey: .path),
            firstPagePath: try container.decodeIfPresent(String.self, forKey: .firstPagePath),
            repliesCount: try container.decode(Int.self, forKey: .repliesCount),
            pageCount: try container.decode(Int.self, forKey: .pageCount),
            lastPagePath: try container.decode(String.self, forKey: .lastPagePath),
            lastPost: try container.decodeIfPresent(LastPost.self, forKey: .lastPost),
            starterOrInterlocutors: try container.decode(String.self, forKey: .starterOrInterlocutors),
            flag: try container.decodeIfPresent(TopicFlag.self, forKey: .flag),
            flagPath: try container.decodeIfPresent(String.self, forKey: .flagPath),
            currentPage: try container.decodeIfPresent(Int.self, forKey: .currentPage),
            readState: try container.decode(TopicReadState.self, forKey: .readState),
            isSticky: try container.decode(Bool.self, forKey: .isSticky),
            isClosed: try container.decode(Bool.self, forKey: .isClosed),
            isPoll: try container.decode(Bool.self, forKey: .isPoll),
            searchHit: try container.decodeIfPresent(SearchHit.self, forKey: .searchHit)
        )
    }
}
