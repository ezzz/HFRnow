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

    /// HFR's error answer (`R57i`, `R57k`): `{"resource":null,"error":true,"error_code":N,…}`, served 200 like a success, so
    /// the code is in the body only. Nil for any other body, which the readers below check as usual.
    static func errorCode(in data: Data) -> Int? {
        guard
            let answer = try? JSONDecoder.snakeCase.decode(ErrorAnswer.self, from: data),
            answer.error, answer.resource == nil
        else { return nil }
        return answer.errorCode
    }

    /// The sub-categories of `category` (`R285a`-`R285c`), in the answer's order: every one in one answer
    /// (`results_count` = their number), each a link to its list filtered on its `subcat` number, the query `R603d`
    /// captured (`ForumCatalogue.topicListPath`). That a sub-category's `id` is the HTML lists' `subcat` is a run
    /// observation (#285: the 19 `subcat` values of categories 1, 2 and 10 on #830's flags pages are all in these
    /// lists). The answer names no slug, so the home page's `/hfr/<cat>/<slug>/` path cannot be built; the title is the
    /// name, entities decoded and trimmed (« BI/Big Data » ends with a space).
    static func subcategories(from data: Data, category: Int) throws(ParsingError) -> [ForumLink] {
        let list = try decode(Envelope<SubcategoryList>.self, from: data).resource
        guard list.listType == "forum_subcategory" else { throw .invalidValue(field: "resource.list_type") }
        guard list.page == 1 else { throw .invalidValue(field: "resource.page") }
        guard (try? RESTHref.target(of: list.href)) == RESTHref.Target(uri: RESTHref.subcategoriesURI(category: category)) else {
            throw .invalidValue(field: "resource.href")
        }
        // Every captured category has sub-categories (`R57a`'s `number_of_subcategories`); an empty answer is not
        // captured, so the home page is read instead (LESSONS 44).
        guard !list.resources.isEmpty else { throw .invalidValue(field: "resource.resources") }
        guard list.resultsCount == list.resources.count else { throw .invalidValue(field: "resource.results_count") }
        var links: [ForumLink] = []
        var seen: Set<Int> = []
        for row in list.resources {
            let path = "resource.resources"
            guard row.id >= 1, seen.insert(row.id).inserted else { throw .invalidValue(field: "\(path).id") }
            let target = RESTHref.Target(uri: RESTHref.subcategoryURI(category: category, subcategory: row.id))
            guard (try? RESTHref.target(of: row.href)) == target else { throw .invalidValue(field: "\(path).href") }
            guard (try? RESTHref.category(of: row.links.category.href)) == category else {
                throw .invalidValue(field: "\(path).links.category.href")
            }
            guard let listPath = ForumCatalogue.topicListPath(categoryID: .forum(category), subcategory: row.id) else {
                throw .invalidValue(field: "\(path).id")
            }
            links.append(ForumLink(title: try text(row.name, field: "\(path).name"), path: listPath))
        }
        return links
    }

    /// Page `page` of the last topics of `category` (`R57b`, `R57d`-`R57g`), rows in the answer's order (the sticky topics
    /// first, on page 1 only, `R57e`).
    ///
    /// The page count is ⌈`results_count` / `results_per_page`⌉ (`R57g`: the page after it is empty), so the navigation is
    /// exact. A page past the last is HFR's empty page (`R57g`), returned without rows; an empty page 1, or an empty page
    /// within the count, is refused, so the HTML page tells an empty list from a failure (LESSONS 44).
    static func lastTopics(from data: Data, category: Int, page: Int = 1) throws(ParsingError) -> TopicListPage {
        let list = try decode(Envelope<TopicList>.self, from: data).resource
        guard list.listType == "topic" else { throw .invalidValue(field: "resource.list_type") }
        guard list.page == page else { throw .invalidValue(field: "resource.page") }
        guard list.resultsPerPage >= 1 else { throw .invalidValue(field: "resource.results_per_page") }
        guard list.resultsCount >= 1 else { throw .invalidValue(field: "resource.results_count") }
        guard
            let target = try? RESTHref.target(of: list.href),
            target.uri == RESTHref.lastTopicsURI(category: category), target.page == page,
            target.resultsPerPage == list.resultsPerPage
        else { throw .invalidValue(field: "resource.href") }
        let (pages, rest) = list.resultsCount.quotientAndRemainder(dividingBy: list.resultsPerPage)
        let last = rest == 0 ? pages : pages + 1
        guard list.resources.isEmpty == (page > last) else { throw .invalidValue(field: "resource.resources") }
        var topics: [TopicSummary] = []
        for row in list.resources {
            let topic = try summary(of: row, at: "resource.resources", readsSticky: true)
            guard topic.topicID?.category == .forum(category) else {
                throw .invalidValue(field: "resource.resources.links.category.href")
            }
            topics.append(topic)
        }
        // A REST page has no HTML path: the caller asks for the next page by number.
        return TopicListPage(
            topics: topics,
            navigation: PageNavigation(current: page, last: last, isExact: true),
            categoryID: .forum(category)
        )
    }

    /// One topic (`R57c`); it must be `topic`. Nil for HFR's placeholder of a topic it does not know (`R57j`): 200, the
    /// asked id and hrefs, but an empty `title` and a null `last_post_date`.
    static func topic(from data: Data, expected topic: TopicID) throws(ParsingError) -> TopicSummary? {
        if let placeholder = try? JSONDecoder.snakeCase.decode(Envelope<Placeholder>.self, from: data).resource,
           placeholder.title.isEmpty, placeholder.lastPostDate == nil {
            guard
                case .forum(let category) = topic.category, placeholder.id == topic.topic,
                (try? RESTHref.category(of: placeholder.links.category.href)) == category,
                (try? RESTHref.names(topic: topic.topic, category: category, href: placeholder.href)) == true
            else { throw .invalidValue(field: "resource.id") }
            return nil
        }
        // `R57c` calls topic 28563 sticky where `R57b`, `R04` and its sub-forum `R06` do not: the flag of a single topic
        // means something else, not known, so it is not read.
        let summary = try summary(of: decode(Envelope<Topic>.self, from: data).resource, at: "resource", readsSticky: false)
        guard summary.topicID == topic else { throw .invalidValue(field: "resource.id") }
        return summary
    }

    /// The global flag bucket `bucket` of the session's account (`R335a`-`R335c`), as the favourites page models it: one
    /// section per category group in the answer's order, the topics in their group's order.
    ///
    /// Every level's `results_count` must equal its number of entries (HFR serves a bucket whole, `R335d`): a consistency
    /// check of the answer, not a proof that HFR left nothing out, which no capture can show (#830). An answer without a
    /// group is not "nothing flagged": what HFR sends to an anonymous or expired session is not captured, so the favourites
    /// page, which tells them apart, is read instead. `postsPerPage` is the account's page size (`topicpp`, `R55-p3`, E19):
    /// it sets each row's page count and last page.
    static func bucket(from data: Data, bucket: RESTFlagBucket, postsPerPage: Int) throws(ParsingError) -> FavoritesPage {
        // The client refuses a size below 1 before any request; a division by 0 must not be reachable anyway.
        guard postsPerPage >= 1 else { throw .invalidValue(field: "posts per page") }
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
            let section = try self.section(of: group, bucket: bucket, postsPerPage: postsPerPage)
            guard case .forum(let category)? = section.categoryID, seen.insert(category).inserted else {
                throw .invalidValue(field: "resource.resources.links.category.href")
            }
            sections.append(section)
        }
        return FavoritesPage(sections: sections)
    }

    // MARK: - Implementation

    /// One category group of a global bucket.
    private static func section(
        of group: BucketGroup, bucket: RESTFlagBucket, postsPerPage: Int
    ) throws(ParsingError) -> FavoriteSection {
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
        // REST group names none, so the path is built (LOT-010 `topicListPath`, its short form: without the header's
        // `sondage` … `subcatgroup` parameters, as every list path the app builds).
        guard let forumPath = ForumCatalogue.topicListPath(categoryID: .forum(category), filter: bucket.filter) else {
            throw .invalidValue(field: "\(path).links.category.href")
        }
        let title = try text(group.links.category.title, field: "\(path).links.category.title")
        var topics: [TopicSummary] = []
        for row in group.resources {
            let rowPath = "\(path).resources"
            var topic = try summary(of: row, at: rowPath, readsSticky: false, postsPerPage: postsPerPage)
            guard topic.topicID?.category == .forum(category) else {
                throw .invalidValue(field: "\(rowPath).links.category.href")
            }
            topic.flag = try flag(row.flagOwntopic, in: bucket, field: "\(rowPath).flag_owntopic")
            try resume(&topic, from: row, at: rowPath, postsPerPage: postsPerPage)
            topics.append(topic)
        }
        return FavoriteSection(forum: ForumLink(title: title, path: forumPath), categoryID: .forum(category), topics: topics)
    }

    /// Where a bucket row opens, and its read state, as the favourites page row of the same topic (#830, HFR-PROTOCOL §6c
    /// LOT-057 "Resume point" and "Read state", a run observation on 943 topics; the published captures are aliased by
    /// position, so the tie itself is not in a fixture).
    ///
    /// `is_read` false is a row with news: the page's flag link, `#t<last_post_read_id>` on page `last_position` div the
    /// page size + 1 (`last_position` is the 0-based offset of the last post read), the last page when the offset is past
    /// it. `is_read` true is a row without news and without a flag link: it opens at its last page, as `FavoritesParser`
    /// opens a row without one. The title link moves to `firstPagePath`, as on the page.
    private static func resume(
        _ topic: inout TopicSummary, from row: Topic, at path: String, postsPerPage: Int
    ) throws(ParsingError) {
        guard let isRead = row.isRead else { throw .invalidValue(field: "\(path).is_read") }
        guard let position = row.lastPosition, position >= 0 else { throw .invalidValue(field: "\(path).last_position") }
        guard let post = row.lastPostReadId, post >= 1 else { throw .invalidValue(field: "\(path).last_post_read_id") }
        topic.firstPagePath = topic.path
        if isRead {
            topic.flagPath = nil
            topic.path = topic.lastPagePath
            topic.currentPage = topic.pageCount
            topic.readState = .read
            return
        }
        guard let topicID = topic.topicID else { throw .invalidValue(field: "\(path).id") }
        // Capped before the + 1: an offset near `Int.max` at one post per page must not trap (Fable review of #918).
        let page = min(position / postsPerPage, topic.pageCount - 1) + 1
        let flagPath = "\(try self.path(of: topicID, page: page))#t\(post)"
        topic.flagPath = flagPath
        topic.path = flagPath
        topic.currentPage = page
        topic.readState = .unread
    }

    /// The flag of a bucket row. `flag_owntopic` is the topic's strongest flag, not the bucket's (HFR-PROTOCOL §6c,
    /// `R335a`-`R335c`): 3 a favourite, 1 a flag. It is 0 on every `read` row (`R335b`), where the favourites page of the
    /// same filter shows `flag0.gif` on every row (`R603e`): `.red`. A 0 elsewhere is no flag; 2 is the read flag in
    /// redface2 C12 only, never captured, so it is no flag either (ADR 0015 point 4). Unlike the page, which shows a flag
    /// image only on a row with news (§6c, `R603a`), the JSON gives one on every row.
    private static func flag(_ value: Int?, in bucket: RESTFlagBucket, field: String) throws(ParsingError) -> TopicFlag? {
        switch value {
        case 3: .yellow
        case 1: .blue
        case 0: bucket == .read ? .red : nil
        case 2: nil
        default: throw .invalidValue(field: field)
        }
    }

    /// A topic row; `path` names where it sits in the JSON, for the errors.
    private static func summary(
        of row: Topic, at path: String, readsSticky: Bool, postsPerPage: Int = RESTDocument.postsPerPage
    ) throws(ParsingError) -> TopicSummary {
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
        guard let date = row.lastPostDate.flatMap(HFRDate.restDate(from:)) else { throw .invalidValue(field: "\(path).last_post_date") }
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
        do {
            return try JSONDecoder.snakeCase.decode(type, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw .invalidValue(field: fieldName(context.codingPath + [key]))
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw .invalidValue(field: fieldName(context.codingPath))
        } catch {
            // Not JSON at all: an HTML error page, an empty body. The decoder's text could quote the body.
            throw .malformedDocument
        }
    }

    /// The JSON keys of a coding path, array indices left out. The decoder hands some keys back converted (`isRead` for
    /// a type mismatch), so they are written in the JSON's snake case again: every key of the API is lower snake case.
    private static func fieldName(_ path: [any CodingKey]) -> String {
        path.filter { $0.intValue == nil }.map { key in
            key.stringValue.reduce(into: "") { name, character in
                if character.isUppercase { name += "_" + character.lowercased() } else { name.append(character) }
            }
        }.joined(separator: ".")
    }
}
