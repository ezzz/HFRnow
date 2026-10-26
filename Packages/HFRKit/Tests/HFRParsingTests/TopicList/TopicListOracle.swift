import Foundation

/// A LOT-002 oracle file for the legacy topic list parser (`schema` 1, kinds `topics`, `mp`, `search`;
/// `docs/lots/LOT-002-list-oracle.md`). The display-only `aDateOfLastPost` is not decoded; the session fields
/// the port does not model are decoded only to check they carry nothing on list pages.
struct TopicListOracle: Decodable {
    let schema: Int
    let kind: String
    let input: Input
    let exception: String?
    let result: Result?

    struct Input: Decodable {
        let file: String
        let currentURL: String?
    }

    struct Result: Decodable {
        /// `results` or `redirect` on search cases; absent on topics and MP cases.
        let page: String?
        let currentCat: String?
        let forumNewTopicUrl: String?
        let forumBaseURL: String?
        let forumFavorisURL: String?
        let forumFlag1URL: String?
        let forumFlag0URL: String?
        let firstPageUrl: String?
        let lastPageUrl: String?
        let nextPageUrl: String?
        let previousPageUrl: String?
        let pageNumber: Int?
        let firstPageNumber: Int?
        let lastPageNumber: Int?
        // Absent on search redirect cases only; list cases require it (`pageFieldsMatch`).
        let needToUpdateMP: Bool? // swiftlint:disable:this discouraged_optional_boolean
        let sNewMPNumber: String?
        let statusInfo: StatusInfo?
        let topics: [Topic]?
    }

    struct StatusInfo: Decodable {
        let statusName: String
        let message: String?
    }

    struct Topic: Decodable {
        let aTitle: String
        let aURL: String
        let aURLOfFirstPage: String
        let aURLOfFlag: String
        let aTypeOfFlag: String
        let aURLOfLastPost: String
        let aURLOfLastPage: String
        let aAuthorOfLastPost: String
        let aAuthorOrInter: String
        let sLastSearchPostContent: String?
        let sLastSearchPostURL: String?
        let aRepCount: Int
        let maxTopicPage: Int
        let curTopicPage: Int
        let isViewed: Bool
        let isViewedFromForumAtLoad: Bool
        let isLocallyViewedInApp: Bool
        let isSuperFavorite: Bool
        let catID: Int
        let postID: Int
        let isPoll: Bool
        let isSticky: Bool
        let isClosed: Bool
        let dDateOfLastPost: String?
    }

    /// Loads `Fixtures/LOT-002/<case>.oracle.json`.
    static func load(_ name: String) throws -> TopicListOracle {
        let json = try Fixture.text("\(name).oracle", extension: "json", subdirectory: "Fixtures/LOT-002")
        return try JSONDecoder().decode(TopicListOracle.self, from: Data(json.utf8))
    }

    /// The captured page the oracle was computed on (its `input.file` is `../captures/<name>.html`).
    func capture() throws -> String {
        let name = URL(fileURLWithPath: input.file).deletingPathExtension().lastPathComponent
        return try Fixture.capture(name)
    }
}
