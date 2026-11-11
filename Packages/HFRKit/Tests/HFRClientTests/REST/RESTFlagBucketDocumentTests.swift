import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// The logged-in flag buckets (`R335a`-`R335e`, `R603f`, #335) decoded into the favourites page model (LOT-057).
@Suite("REST flag bucket document (LOT-057)")
struct RESTFlagBucketDocumentTests {
    static let buckets: [(RESTFlagBucket, String)] = [
        (.participated, RESTCapture.participated), (.read, RESTCapture.read), (.favorites, RESTCapture.favorites)
    ]

    @Test("R335a-R335c: one section per category group, in order, every row as the JSON walked on its own says")
    func bucketsMatchTheirJSON() throws {
        for (bucket, file) in Self.buckets {
            let page = try RESTDocument.bucket(from: RESTCapture.data(file), bucket: bucket)
            let groups = try #require(try RESTCapture.object(file)["resource"] as? [String: Any])["resources"] as? [[String: Any]]
            let expected = try #require(groups)
            try #require(page.sections.count == expected.count)
            #expect(page.unreadPrivateMessages == nil)
            #expect(page.hashCheck == nil)
            #expect(page.notice == nil)
            for (section, group) in zip(page.sections, expected) {
                let category = try Self.category(of: group)
                #expect(section.categoryID == .forum(category))
                let link = (group["links"] as? [String: Any])?["category"] as? [String: Any]
                #expect(section.forum.title == link?["title"] as? String)
                // The header link of the favourites page (`R10`, `R603e`): the category's list on the same `owntopic`.
                #expect(section.forum.path
                    == "/forum1.php?config=hfr.inc&cat=\(category)&page=1&subcat=&owntopic=\(bucket.filter.rawValue)")
                let rows = try #require(group["resources"] as? [[String: Any]])
                try #require(section.topics.count == rows.count)
                for (topic, row) in zip(section.topics, rows) {
                    try Self.expect(topic, matches: row, category: category)
                }
            }
        }
    }

    @Test("Bucket rows: the flag is `flag_owntopic` (3 favourite, 1 flag, 0 none), never the bucket's")
    func flags() throws {
        let flags = try Self.buckets.map { bucket, file in
            try RESTDocument.bucket(from: RESTCapture.data(file), bucket: bucket).sections.flatMap(\.topics).map(\.flag)
        }
        // `R335a`, `R335c`: both topics are favourites too (3); `R335b`: 0 everywhere.
        #expect(flags == [[.yellow, .yellow], [nil, nil], [.yellow, .yellow]])
        for (value, flag) in [(0, nil), (1, TopicFlag.blue), (2, nil), (3, .yellow)] as [(Int, TopicFlag?)] {
            let data = try Self.editedFirstRow(RESTCapture.participated) { $0["flag_owntopic"] = value }
            #expect(try RESTDocument.bucket(from: data, bucket: .participated).sections.first?.topics.first?.flag == flag)
        }
    }

    @Test("R335d: a page 2 of 5 asked of the global bucket is answered as page 1, whole: it decodes like R335a")
    func pagingIsIgnored() throws {
        let page1 = try RESTDocument.bucket(from: RESTCapture.data(RESTCapture.participated), bucket: .participated)
        let page2 = try RESTDocument.bucket(from: RESTCapture.data(RESTCapture.participatedPage2), bucket: .participated)
        #expect(page2 == page1)
    }

    @Test("The flat form of one category (R335e, R603f) is not the global bucket: refused, never read as a section")
    func flatFormRefused() throws {
        // Its rows are topics, not groups: the first group field they lack names the failure.
        #expect(throws: ParsingError.invalidValue(field: "resource.resources.page")) {
            try RESTDocument.bucket(from: RESTCapture.data(RESTCapture.participatedCategory), bucket: .participated)
        }
        #expect(throws: ParsingError.invalidValue(field: "resource.resources.page")) {
            try RESTDocument.bucket(from: RESTCapture.data(RESTCapture.readCategory), bucket: .read)
        }
    }

    @Test("A bucket's answer is not another bucket's: the list's href names the bucket asked for")
    func otherBucketRefused() throws {
        #expect(throws: ParsingError.invalidValue(field: "resource.href")) {
            try RESTDocument.bucket(from: RESTCapture.data(RESTCapture.participated), bucket: .read)
        }
        #expect(throws: ParsingError.invalidValue(field: "resource.href")) {
            try RESTDocument.bucket(from: RESTCapture.data(RESTCapture.favorites), bucket: .participated)
        }
    }

    /// One checked field broken in `R335a`, and the field the decode must name.
    private struct Breakage: Sendable {
        let field: String
        let edit: @Sendable (inout [String: Any]) -> Void
    }

    private static let api = "https://forum.hardware.fr/api/forums/hardwarefr/"

    /// The list and its groups.
    private static let listBreakages = [
        Breakage(field: "resource.list_type") { $0["list_type"] = "topic" },
        Breakage(field: "resource.page") { $0["page"] = 2 },
        Breakage(field: "resource.href") { $0["href"] = "\(Self.api)topics/participated/posts/" },
        Breakage(field: "resource.resources") { $0["resources"] = [] as [Any]; $0["results_count"] = 0 },
        // A bucket longer than what it holds is cut: never return a partial list (LESSONS 44).
        Breakage(field: "resource.results_count") { $0["results_count"] = 3 },
        Breakage(field: "resource.resources.list_type") { Self.editGroup(&$0) { $0["list_type"] = "list" } },
        Breakage(field: "resource.resources.page") { Self.editGroup(&$0) { $0["page"] = 2 } },
        Breakage(field: "resource.resources.href") {
            Self.editGroup(&$0) { $0["href"] = "\(Self.api)categories/102/topics/participated/?page=1&results_per_page=1" }
        },
        Breakage(field: "resource.resources.href") {
            Self.editGroup(&$0) { $0["href"] = "\(Self.api)categories/101/topics/read/?page=1&results_per_page=1" }
        },
        Breakage(field: "resource.resources.links.category.href") {
            Self.editGroup(&$0) { $0["links"] = ["category": ["href": "https://example.com/api/x/", "title": "Category 1"]] }
        },
        Breakage(field: "resource.resources.links.category.title") {
            Self.editGroup(&$0) { $0["links"] = ["category": ["href": "\(Self.api)categories/101/"]] }
        },
        Breakage(field: "resource.resources.links.category.title") {
            Self.editGroup(&$0) { $0["links"] = ["category": ["href": "\(Self.api)categories/101/", "title": " "]] }
        },
        Breakage(field: "resource.resources.resources") {
            Self.editGroup(&$0) { $0["resources"] = [] as [Any]; $0["results_count"] = 0 }
        },
        Breakage(field: "resource.resources.results_count") { Self.editGroup(&$0) { $0["results_count"] = 2 } },
        // Two groups of one category: the second is not a section of its own.
        Breakage(field: "resource.resources.links.category.href") { resource in
            var groups = resource["resources"] as? [[String: Any]] ?? []
            groups[1] = groups[0]
            resource["resources"] = groups
        }
    ]

    /// The rows of a group.
    private static let rowBreakages = [
        Breakage(field: "resource.resources.resources.flag_owntopic") { Self.editRow(&$0) { $0["flag_owntopic"] = nil } },
        Breakage(field: "resource.resources.resources.flag_owntopic") { Self.editRow(&$0) { $0["flag_owntopic"] = 4 } },
        Breakage(field: "resource.resources.resources.flag_owntopic") { Self.editRow(&$0) { $0["flag_owntopic"] = -1 } },
        // A row of another category than its group's.
        Breakage(field: "resource.resources.resources.links.category.href") {
            Self.editRow(&$0) { row in
                var links = row["links"] as? [String: Any] ?? [:]
                links["category"] = ["href": "\(Self.api)categories/102/"]
                row["links"] = links
                row["href"] = "\(Self.api)categories/102/topics/9800001/"
            }
        },
        Breakage(field: "resource.resources.resources.href") { Self.editRow(&$0) { $0["href"] = "\(Self.api)categories/101/topics/1/" } },
        Breakage(field: "resource.resources.resources.links.posts.count") {
            Self.editRow(&$0) { row in
                var links = row["links"] as? [String: Any] ?? [:]
                links["posts"] = ["count": 0]
                row["links"] = links
            }
        }
    ]

    @Test("Each checked field of an edited R335a fails the decode, naming the field")
    func checkedFields() throws {
        for breakage in Self.listBreakages + Self.rowBreakages {
            var object = try RESTCapture.object(RESTCapture.participated)
            var resource = try #require(object["resource"] as? [String: Any])
            breakage.edit(&resource)
            object["resource"] = resource
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: ParsingError.invalidValue(field: breakage.field)) {
                try RESTDocument.bucket(from: data, bucket: .participated)
            }
        }
    }

    @Test("A bucket row's `is_sticky` is not read: never true in the raw buckets, while `R603e` shows a sticky row")
    func stickyNotRead() throws {
        let data = try Self.editedFirstRow(RESTCapture.favorites) { $0["is_sticky"] = true }
        #expect(try RESTDocument.bucket(from: data, bucket: .favorites).sections.first?.topics.first?.isSticky == false)
    }

    @Test("A bucket row with no sub-category in its href (HFR-PROTOCOL §6c) is read like the others")
    func rowWithoutSubcategory() throws {
        let data = try Self.editedFirstRow(RESTCapture.participated) { row in
            row["href"] = "https://forum.hardware.fr/api/forums/hardwarefr/categories/101/topics/9800001/"
            var links = row["links"] as? [String: Any] ?? [:]
            links["subcategory"] = nil
            row["links"] = links
        }
        let topic = try #require(try RESTDocument.bucket(from: data, bucket: .participated).sections.first?.topics.first)
        #expect(topic.topicID == TopicID(category: .forum(101), topic: 9_800_001))
    }

    // MARK: - Helpers

    /// What the row must be, read from the JSON without the client's decoder.
    private static func expect(_ topic: TopicSummary, matches row: [String: Any], category: Int) throws {
        let id = try #require(row["id"] as? Int)
        let links = try #require(row["links"] as? [String: Any])
        let posts = try #require((links["posts"] as? [String: Any])?["count"] as? Int)
        let pages = (posts + 39) / 40
        let base = "/forum2.php?config=hfr.inc&cat=\(category)&post=\(id)"
        #expect(topic.topicID == TopicID(category: .forum(category), topic: id))
        #expect(topic.title == row["title"] as? String)
        #expect(topic.repliesCount == posts - 1)
        #expect(topic.pageCount == pages)
        // HFR's own `links.posts.href` names the last page, at 40 per page.
        let postsHref = try #require((links["posts"] as? [String: Any])?["href"] as? String)
        #expect(postsHref.hasSuffix("/posts/?page=\(pages)&results_per_page=40"))
        #expect(topic.firstPagePath == "\(base)&page=1")
        #expect(topic.lastPagePath == "\(base)&page=\(pages)")
        #expect(topic.path == topic.lastPagePath)
        #expect(topic.currentPage == pages)
        #expect(topic.flagPath == nil)
        #expect(topic.readState == .unknown)
        #expect(topic.lastPost?.author == (links["last_author"] as? [String: Any])?["title"] as? String)
        #expect(topic.lastPost?.path == topic.lastPagePath)
        #expect(topic.lastPost?.date == HFRDate.restDate(from: row["last_post_date"] as? String ?? ""))
        #expect(topic.starterOrInterlocutors == (links["author"] as? [String: Any])?["title"] as? String)
        #expect(topic.isClosed == row["is_closed"] as? Bool)
        #expect(!topic.isSticky)
        #expect(!topic.isPoll)
    }

    private static func category(of group: [String: Any]) throws -> Int {
        let href = try #require(((group["links"] as? [String: Any])?["category"] as? [String: Any])?["href"] as? String)
        let number = href.split(separator: "/").last.flatMap { Int($0) }
        return try #require(number)
    }

    private static func editGroup(_ resource: inout [String: Any], _ edit: (inout [String: Any]) -> Void) {
        var groups = resource["resources"] as? [[String: Any]] ?? []
        edit(&groups[0])
        resource["resources"] = groups
    }

    private static func editRow(_ resource: inout [String: Any], _ edit: (inout [String: Any]) -> Void) {
        editGroup(&resource) { group in
            var rows = group["resources"] as? [[String: Any]] ?? []
            edit(&rows[0])
            group["resources"] = rows
        }
    }

    private static func editedFirstRow(_ file: String, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try RESTCapture.object(file)
        var resource = try #require(object["resource"] as? [String: Any])
        editRow(&resource, edit)
        object["resource"] = resource
        return try JSONSerialization.data(withJSONObject: object)
    }
}
