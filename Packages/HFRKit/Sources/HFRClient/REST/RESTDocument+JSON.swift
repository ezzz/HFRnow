import Foundation

/// The JSON shapes `RESTDocument` decodes (`R57a`-`R57k`, `R285a`-`R285c`, `R335a`-`R335e`), keys in snake case.
extension RESTDocument {
    struct Envelope<Resource: Decodable>: Decodable {
        let resource: Resource
    }

    struct CategoryList: Decodable {
        let resources: [Category]
    }

    struct Category: Decodable {
        let id: Int
        let name: String
        let href: String
    }

    struct ErrorAnswer: Decodable {
        let resource: Nothing?
        let error: Bool
        let errorCode: Int
    }

    /// Any JSON object: only whether `resource` is null matters.
    struct Nothing: Decodable {}

    struct SubcategoryList: Decodable {
        let page: Int
        let resultsCount: Int
        let listType: String
        let href: String
        let resources: [Subcategory]
    }

    struct Subcategory: Decodable {
        let id: Int
        let name: String
        let href: String
        let links: GroupLinksHref
    }

    struct GroupLinksHref: Decodable {
        let category: Link
    }

    struct TopicList: Decodable {
        let page: Int
        let resultsCount: Int
        let resultsPerPage: Int
        let listType: String
        let href: String
        let resources: [Topic]
    }

    /// The fields of `R57j`'s placeholder, which has no author titles.
    struct Placeholder: Decodable {
        let id: Int
        let title: String
        let lastPostDate: String?
        let href: String
        let links: GroupLinksHref
    }

    struct Topic: Decodable {
        let id: Int
        let title: String
        /// Null on `R57j`'s placeholder only.
        let lastPostDate: String?
        let isClosed: Bool
        let isSticky: Bool
        let href: String
        let links: Links
        /// Flag buckets only (`R335a`-`R335e`); absent from `R57b`, `R57c`.
        let flagOwntopic: Int?
        // Flag buckets only, as `flagOwntopic`; optional because the R57 rows have none, checked on every bucket row.
        // swiftlint:disable:next discouraged_optional_boolean
        let isRead: Bool?
        let lastPosition: Int?
        let lastPostReadId: Int?
    }

    struct BucketList: Decodable {
        let page: Int
        let resultsCount: Int
        let listType: String
        let href: String
        let resources: [BucketGroup]
    }

    struct BucketGroup: Decodable {
        let page: Int
        let resultsCount: Int
        let listType: String
        let href: String
        let links: GroupLinks
        let resources: [Topic]
    }

    struct GroupLinks: Decodable {
        let category: TitledLink
    }

    struct TitledLink: Decodable {
        let href: String
        let title: String
    }

    struct Links: Decodable {
        let category: Link
        let posts: CountedLink
        let author: User
        let lastAuthor: User
    }

    struct Link: Decodable {
        let href: String
    }

    struct CountedLink: Decodable {
        let count: Int
    }

    struct User: Decodable {
        let title: String
    }
}

extension JSONDecoder {
    /// The REST API writes its keys in snake case.
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
