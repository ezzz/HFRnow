import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// LOT-023: the private messages list, against the LOT-002 oracle and against facts read from the raw captures.
@Suite("Private message list parser")
struct PrivateMessageListParserTests {
    static let listURL = "/forum1.php?config=hfr.inc&cat=prive&page=1"
    static let cases = ["R13a", "R13b", "R13c", "R13u1", "R13u1b"]

    @Test("Rows reproduce the oracle: order, topic, title, replies, last page, own read state, interlocutor", arguments: cases)
    func matchesOracle(_ name: String) throws {
        let oracle = try TopicListOracle.load(name)
        let legacy = try #require(oracle.result)
        let page = try PrivateMessageListParser.parse(oracle.capture(), pageURL: try #require(oracle.input.currentURL))
        let expected = try #require(legacy.topics)
        #expect(page.threads.count == expected.count)
        for (thread, row) in zip(page.threads, expected) {
            let context = Comment(rawValue: "\(name) post \(row.aURL)")
            // The oracle title still carries the marker (D1); the port splits it off.
            let marked = row.aTitle.lowercased().hasPrefix(Self.marker)
            #expect(thread.isUnreadByOthers == marked, context)
            let title = marked ? String(row.aTitle.dropFirst(Self.marker.count)).trimmingCharacters(in: .whitespaces) : row.aTitle
            #expect(thread.summary.title == title, context)
            #expect(thread.summary.path == row.aURL, context)
            #expect(thread.summary.repliesCount == row.aRepCount, context)
            #expect(thread.summary.lastPagePath == row.aURLOfLastPage, context)
            #expect(thread.summary.lastPost?.author == row.aAuthorOfLastPost, context)
            // Legacy `isViewed` is the icon alone (`closedp.gif` Off = viewed); MPListView mixed it with the title marker.
            #expect(thread.isUnread == !row.isViewed, context)
            #expect(thread.isGroup == row.aAuthorOrInter.contains("multiples"), context)
            if !thread.isGroup {
                #expect(thread.interlocutors == [row.aAuthorOrInter], context)
            }
            #expect(thread.summary.topicID == TopicID(category: .privateMessages, topic: row.postIDFromURL), context)
        }
    }

    @Test("`[non lu]` tooltips and group names equal what the raw rows hold", arguments: ["R13a", "R13u1", "R13u1b"])
    func namesMatchRawRows(_ name: String) throws {
        let oracle = try TopicListOracle.load(name)
        let html = try oracle.capture()
        let rows = CaptureRowEvidence(html: html).rows
        let page = try PrivateMessageListParser.parse(html, pageURL: Self.listURL)
        #expect(rows.count == page.threads.count)
        for (raw, thread) in zip(rows, page.threads) {
            let tooltip = raw.firstMatch(of: Self.unreadTooltip).map { String($0.output.1) }
            #expect(thread.isUnreadByOthers == (tooltip != nil))
            #expect(thread.unreadBy == Self.names(in: tooltip ?? ""))
            if let group = raw.firstMatch(of: Self.groupTooltip) {
                #expect(thread.interlocutors == Self.names(in: String(group.output.1)))
            }
        }
    }

    @Test("R13u1: a group thread, a one-to-one thread, and the four read/unread combinations")
    func recipientList() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R13u1-mp-list-recipient-unread"), pageURL: Self.listURL)
        #expect(page.threads.count == 50)
        #expect(page.unreadThreadCount == 10)
        let first = page.threads[0]
        #expect(first.summary.title == "fixture-test-1")
        #expect(first.isUnread)
        #expect(first.unreadBy == ["user2"])
        #expect(first.interlocutors == ["user2\u{200B}"])
        #expect(!first.isGroup)
        let group = page.threads[1]
        #expect(group.isGroup)
        #expect(group.interlocutors.first == "user3")
        #expect(group.interlocutors.count == 7)
        #expect(group.unreadBy.count == 34)
        #expect(group.id == "topic:prive-3197250")
        // Own state and the others' state are independent: read here, `[non lu]` for the others.
        let readButMarked = page.threads[3]
        #expect(!readButMarked.isUnread)
        #expect(readButMarked.isUnreadByOthers)
        let plain = page.threads[5]
        #expect(!plain.isUnread && !plain.isUnreadByOthers && plain.unreadBy.isEmpty)
    }

    @Test("R13a/R13b: marking a thread unread (W18) flips the member's state, not the `[non lu]` marker")
    func markUnread() throws {
        let before = try PrivateMessageListParser.parse(Fixture.capture("R13a-mp-list"), pageURL: Self.listURL)
        let after = try PrivateMessageListParser.parse(Fixture.capture("R13b-mp-list-after-mark-unread"), pageURL: Self.listURL)
        #expect(before.threads.first?.isUnread == false)
        #expect(after.threads.first?.isUnread == true)
        #expect(before.threads.first?.isUnreadByOthers == true)
        #expect(after.threads.first?.isUnreadByOthers == true)
    }

    @Test("Pagination and the new-message link come from the shared list parser")
    func pagination() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R13u1-mp-list-recipient-unread"), pageURL: Self.listURL)
        #expect(page.navigation.current == 1)
        #expect(page.navigation.last == 7)
        #expect(page.navigation.nextPath?.contains("&page=2&") == true)
        #expect(page.newMessagePath == "/message.php?config=hfr.inc&cat=prive&sond=0&p=1&subcat=0&dest=&subcatgroup=0")
    }

    @Test("An empty mailbox is an empty page, not a failure (R13c)")
    func emptyMailbox() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R13c-mp-list-empty-after-delete"), pageURL: Self.listURL)
        #expect(page.threads.isEmpty)
        #expect(page.unreadThreadCount == 0)
    }

    @Test("A message page answering the MP list is the login wall, whatever URL it is parsed with")
    func loginWall() throws {
        // R08-1 is a `.hop` page (captured for another list): the only captured shape of HFR's message page.
        #expect(throws: ListPageFailure.notAuthenticated("Aucun sujet auquel vous avez participé n'est connu")) {
            try PrivateMessageListParser.parse(
                Fixture.capture("R08-1-list-cat13-owntopic1-empty"),
                pageURL: "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=1"
            )
        }
    }

    @Test("A list of another category is refused", arguments: ["R04-list-cat13-p1-anon", "R50b-search-results-no-cookie"])
    func otherList(_ capture: String) throws {
        #expect(throws: ListPageFailure.self) {
            try PrivateMessageListParser.parse(Fixture.capture(capture), pageURL: "/hfr/Discussions/liste_sujet-1.htm")
        }
    }

    private static let marker = "[non lu]"
    // Independent of SwiftSoup and of the parser: raw-HTML regexes over the capture (LESSONS 33).
    nonisolated(unsafe) private static let unreadTooltip = /class="red" title="Ce message n'a pas été lu par : ([^"]*)"/
    nonisolated(unsafe) private static let groupTooltip = /<span title="([^"]*)">Interlocuteurs multiples<\/span>/

    private static func names(in text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

private extension TopicListOracle.Topic {
    /// Topic number of the `post=` parameter of the title URL.
    var postIDFromURL: Int {
        URLComponents(string: aURL)?.queryItems?.first { $0.name == "post" }?.value.flatMap(Int.init) ?? -1
    }
}
