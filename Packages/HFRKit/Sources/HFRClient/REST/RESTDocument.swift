import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Turns the REST API's JSON into LOT-010 models (LOT-057). The JSON types stay here.
///
/// Every field read is checked; a failure names the field, never its value (the JSON holds pseudos).
enum RESTDocument {
    /// Anonymous page size of a topic (`R04`: every row's page count is the posts count over 40); an account may set
    /// another (`topicpp`, E19). Also the `results_per_page` of every `links.posts.href` (`R57b`, `R57c`).
    static let postsPerPage = 40

    /// The categories of `R57a`, in the answer's order.
    static func categories(from data: Data) throws(ParsingError) -> [ForumCategory] {
        let list = try decode(Envelope<CategoryList>.self, from: data).resource
        guard !list.resources.isEmpty else { throw .invalidValue(field: "resource.resources") }
        var categories: [ForumCategory] = []
        for row in list.resources {
            guard try RESTHref.target(of: row.href) == RESTHref.Target(uri: RESTHref.categoryURI(row.id)) else {
                throw .invalidValue(field: "resource.resources.href")
            }
            // The home page's link of the same forum; a forum the catalogue does not know (an id below 1 included) is read
            // from the home page.
            guard let path = ForumCatalogue.forumPath(for: .forum(row.id)) else { throw .invalidValue(field: "resource.resources.id") }
            let title = try text(row.name, field: "resource.resources.name")
            categories.append(ForumCategory(categoryID: .forum(row.id), title: title, path: path))
        }
        return categories
    }

    /// The last topics of `category` (`R57b`): one page, rows in the answer's order (the sticky topics first).
    static func lastTopics(from data: Data, category: Int) throws(ParsingError) -> TopicListPage {
        let list = try decode(Envelope<TopicList>.self, from: data).resource
        guard list.listType == "topic" else { throw .invalidValue(field: "resource.list_type") }
        guard list.page >= 1 else { throw .invalidValue(field: "resource.page") }
        guard list.resultsPerPage >= 1 else { throw .invalidValue(field: "resource.results_per_page") }
        // A list without a row is not an empty forum (every category has topics): it is read from the HTML page, which
        // tells an empty list from a failure (LESSONS 44). HFR's answer for an unknown category is not captured (#355).
        guard !list.resources.isEmpty else { throw .invalidValue(field: "resource.resources") }
        var topics: [TopicSummary] = []
        for row in list.resources {
            let topic = try summary(of: row, at: "resource.resources", readsSticky: true)
            guard topic.topicID?.category == .forum(category) else {
                throw .invalidValue(field: "resource.resources.links.category.href")
            }
            topics.append(topic)
        }
        // No page after the first is captured: the list offers none and claims no page count.
        return TopicListPage(
            topics: topics,
            navigation: PageNavigation(current: list.page, last: list.page),
            categoryID: .forum(category)
        )
    }

    /// One topic (`R57c`); it must be `topic`.
    static func topic(from data: Data, expected topic: TopicID) throws(ParsingError) -> TopicSummary {
        // `R57c` calls topic 28563 sticky where `R57b`, `R04` and its sub-forum `R06` do not: the flag of a single topic
        // means something else, not known, so it is not read.
        let summary = try summary(of: decode(Envelope<Topic>.self, from: data).resource, at: "resource", readsSticky: false)
        guard summary.topicID == topic else { throw .invalidValue(field: "resource.id") }
        return summary
    }

    /// The global flag bucket `bucket` of the session's account (`R335a`-`R335c`), as the favourites page models it: one
    /// section per category group in the answer's order, the topics in their group's order.
    ///
    /// The answer is complete only as far as its own counts say: every level's `results_count` must equal its number of
    /// entries (HFR ignores paging here, `R335d`). An answer without a group is not "nothing flagged": what HFR sends to an
    /// anonymous or expired session is not captured, so the favourites page, which tells them apart, is read instead.
    static func bucket(from data: Data, bucket: RESTFlagBucket) throws(ParsingError) -> FavoritesPage {
        let list = try decode(Envelope<BucketList>.self, from: data).resource
        guard list.listType == "list" else { throw .invalidValue(field: "resource.list_type") }
        guard list.page == 1 else { throw .invalidValue(field: "resource.page") }
        guard (try? RESTHref.target(of: list.href).uri) == RESTHref.bucketURI(bucket) else {
            throw .invalidValue(field: "resource.href")
        }
        guard !list.resources.isEmpty else { throw .invalidValue(field: "resource.resources") }
        guard list.resultsCount == list.resources.count else { throw .invalidValue(field: "resource.results_count") }
        var sections: [FavoriteSection] = []
        var seen: Set<Int> = []
        for group in list.resources {
            let section = try self.section(of: group, bucket: bucket)
            guard case .forum(let category)? = section.categoryID, seen.insert(category).inserted else {
                throw .invalidValue(field: "resource.resources.links.category.href")
            }
            sections.append(section)
        }
        return FavoritesPage(sections: sections)
    }

    // MARK: - Implementation

    /// One category group of a global bucket.
    private static func section(of group: BucketGroup, bucket: RESTFlagBucket) throws(ParsingError) -> FavoriteSection {
        let path = "resource.resources"
        guard group.listType == "topic" else { throw .invalidValue(field: "\(path).list_type") }
        guard group.page == 1 else { throw .invalidValue(field: "\(path).page") }
        let category: Int
        do {
            category = try RESTHref.category(of: group.links.category.href)
        } catch {
            throw .invalidValue(field: "\(path).links.category.href")
        }
        guard (try? RESTHref.target(of: group.href).uri) == RESTHref.bucketURI(bucket, category: category) else {
            throw .invalidValue(field: "\(path).href")
        }
        guard !group.resources.isEmpty else { throw .invalidValue(field: "\(path).resources") }
        guard group.resultsCount == group.resources.count else { throw .invalidValue(field: "\(path).results_count") }
        // The favourites page's header names the category's list filtered on the same `owntopic` (`R10`, `R603e`); the
        // REST group names none, so the path is built (LOT-010 `topicListPath`).
        guard let forumPath = ForumCatalogue.topicListPath(categoryID: .forum(category), filter: bucket.filter) else {
            throw .invalidValue(field: "\(path).links.category.href")
        }
        let title = try text(group.links.category.title, field: "\(path).links.category.title")
        var topics: [TopicSummary] = []
        for row in group.resources {
            let rowPath = "\(path).resources"
            var topic = try summary(of: row, at: rowPath, readsSticky: false)
            guard topic.topicID?.category == .forum(category) else {
                throw .invalidValue(field: "\(rowPath).links.category.href")
            }
            topic.flag = try flag(row.flagOwntopic, field: "\(rowPath).flag_owntopic")
            // A favourites row opens where the member stopped (`FavoritesParser`): the flag link, else the last post. The
            // JSON's `last_post_read_id` and `last_position` are not tied to a flag link by any capture, so the row opens at
            // the last page, as an HTML row without a flag link does.
            topic.firstPagePath = topic.path
            topic.path = topic.lastPagePath
            topic.currentPage = topic.pageCount
            topics.append(topic)
        }
        return FavoriteSection(forum: ForumLink(title: title, path: forumPath), categoryID: .forum(category), topics: topics)
    }

    /// The flag image an HTML row of the same topic would show: `flag_owntopic` is the topic's strongest flag, not the
    /// bucket's (HFR-PROTOCOL §6c, `R335a`-`R335c`): 3 a favourite, 1 a flag. 0 (every `read` row) is no flag; 2 is the
    /// read flag in redface2 C12 only, never captured, so it is no flag either (ADR 0015 point 4).
    private static func flag(_ value: Int?, field: String) throws(ParsingError) -> TopicFlag? {
        switch value {
        case 3: .yellow
        case 1: .blue
        case 0, 2: nil
        default: throw .invalidValue(field: field)
        }
    }

    /// A topic row; `path` names where it sits in the JSON, for the errors.
    private static func summary(of row: Topic, at path: String, readsSticky: Bool) throws(ParsingError) -> TopicSummary {
        let category: Int
        do {
            category = try RESTHref.category(of: row.links.category.href)
        } catch {
            throw .invalidValue(field: "\(path).links.category.href")
        }
        guard row.id >= 1 else { throw .invalidValue(field: "\(path).id") }
        guard (try? RESTHref.names(topic: row.id, category: category, href: row.href)) == true else {
            throw .invalidValue(field: "\(path).href")
        }
        let posts = row.links.posts.count
        guard posts >= 1 else { throw .invalidValue(field: "\(path).links.posts.count") }
        guard let date = HFRDate.restDate(from: row.lastPostDate) else { throw .invalidValue(field: "\(path).last_post_date") }
        let topicID = TopicID(category: .forum(category), topic: row.id)
        // Quotient and remainder: `posts + postsPerPage - 1` would trap on a count near `Int.max`.
        let (pages, rest) = posts.quotientAndRemainder(dividingBy: postsPerPage)
        let pageCount = rest == 0 ? pages : pages + 1
        let lastPagePath = try self.path(of: topicID, page: pageCount)
        return TopicSummary(
            topicID: topicID,
            title: try text(row.title, field: "\(path).title"),
            path: try self.path(of: topicID, page: 1),
            repliesCount: posts - 1,
            pageCount: pageCount,
            lastPagePath: lastPagePath,
            lastPost: LastPost(author: row.links.lastAuthor.title, path: lastPagePath, date: date),
            starterOrInterlocutors: row.links.author.title,
            isSticky: readsSticky && row.isSticky,
            isClosed: row.isClosed
        )
    }

    /// The forum-relative `forum2.php` path the network layer requests for that page (LOT-041), which HFR redirects
    /// to the canonical page: the REST answer names no page URL.
    private static func path(of topic: TopicID, page: Int) throws(ParsingError) -> String {
        guard
            let url = try? HFREndpoint.topicPage(topic: topic, page: page).url,
            let query = url.query(percentEncoded: true)
        else { throw .invalidValue(field: "topic page") }
        return "\(url.path(percentEncoded: true))?\(query)"
    }

    /// Entities decoded, then trimmed like an HTML list title (`TopicListParser.trimmed`): `R57b` serves topic 115425
    /// with a leading space that `R04`'s row loses.
    private static func text(_ raw: String, field: String) throws(ParsingError) -> String {
        guard let decoded = HFRText.decodingHTMLEntities(raw) else { throw .invalidValue(field: field) }
        let isSpace = { (character: Character) in character.unicodeScalars.allSatisfy(\.properties.isWhitespace) }
        guard let first = decoded.firstIndex(where: { !isSpace($0) }), let last = decoded.lastIndex(where: { !isSpace($0) }) else {
            throw .invalidValue(field: field)
        }
        return String(decoded[first...last])
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws(ParsingError) -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw .invalidValue(field: fieldName(context.codingPath + [key]))
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw .invalidValue(field: fieldName(context.codingPath))
        } catch {
            // Not JSON at all: an HTML error page, an empty body. The decoder's text could quote the body.
            throw .malformedDocument
        }
    }

    /// The JSON keys of a coding path, array indices left out.
    private static func fieldName(_ path: [any CodingKey]) -> String {
        path.filter { $0.intValue == nil }.map(\.stringValue).joined(separator: ".")
    }

    // MARK: - JSON

    private struct Envelope<Resource: Decodable>: Decodable {
        let resource: Resource
    }

    private struct CategoryList: Decodable {
        let resources: [Category]
    }

    private struct Category: Decodable {
        let id: Int
        let name: String
        let href: String
    }

    private struct TopicList: Decodable {
        let page: Int
        let resultsPerPage: Int
        let listType: String
        let resources: [Topic]
    }

    private struct Topic: Decodable {
        let id: Int
        let title: String
        let lastPostDate: String
        let isClosed: Bool
        let isSticky: Bool
        let href: String
        let links: Links
        /// Flag buckets only (`R335a`-`R335e`); absent from `R57b`, `R57c`.
        let flagOwntopic: Int?
    }

    private struct BucketList: Decodable {
        let page: Int
        let resultsCount: Int
        let listType: String
        let href: String
        let resources: [BucketGroup]
    }

    private struct BucketGroup: Decodable {
        let page: Int
        let resultsCount: Int
        let listType: String
        let href: String
        let links: GroupLinks
        let resources: [Topic]
    }

    private struct GroupLinks: Decodable {
        let category: TitledLink
    }

    private struct TitledLink: Decodable {
        let href: String
        let title: String
    }

    private struct Links: Decodable {
        let category: Link
        let posts: CountedLink
        let author: User
        let lastAuthor: User
    }

    private struct Link: Decodable {
        let href: String
    }

    private struct CountedLink: Decodable {
        let count: Int
    }

    private struct User: Decodable {
        let title: String
    }
}
