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

    // MARK: - Implementation

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
