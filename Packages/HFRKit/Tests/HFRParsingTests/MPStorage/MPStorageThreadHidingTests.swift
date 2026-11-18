import HFRModels
import Testing
@testable import HFRParsing

/// #1074: the account's MPStorage thread stays out of the member's list and unread counts, while its finder still sees it.
/// #1200 P1: only the thread the storage sync located is hidden; another row with the storage subject stays visible.
@Suite("MPStorage thread hidden from the MP list")
struct MPStorageThreadHidingTests {
    static let listURL = "/forum1.php?config=hfr.inc&cat=prive&page=1"
    static let pageTwoURL = "/forum1.php?config=hfr.inc&cat=prive&page=2"

    /// The storage thread of `R13u1` and of `R333b` row 1 (`R60a`).
    static let storagePost = 3_157_083

    private static func thread(_ title: String, post: Int? = nil, readState: TopicReadState) -> PrivateMessageThread {
        let topicID = post.map { TopicID(category: .privateMessages, topic: $0) }
        return PrivateMessageThread(summary: TopicSummary(topicID: topicID, title: title, path: "/x", readState: readState))
    }

    @Test("R13u1: the storage row (marked [non lu]) is dropped, the other rows keep their order")
    func dropsMarkedRow() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R13u1-mp-list-recipient-unread"), pageURL: Self.listURL)
        let shown = page.hidingStorageThread(post: Self.storagePost)
        #expect(page.threads.contains { MPStoragePageParser.isStorageSubject($0.summary.title) })
        #expect(!shown.threads.contains { MPStoragePageParser.isStorageSubject($0.summary.title) })
        #expect(shown.threads == page.threads.filter { !MPStoragePageParser.isStorageSubject($0.summary.title) })
        #expect(shown.threads.count == page.threads.count - 1)
        #expect(shown.navigation == page.navigation)
        #expect(shown.newMessagePath == page.newMessagePath)
    }

    @Test("#1200 P1, R333b: only the located storage row is dropped; the other storage-subject row stays visible")
    func keepsForeignStorageSubjectRowVisible() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R333b-mp-list-p2-storage-row-first"), pageURL: Self.pageTwoURL)
        let storageRows = page.threads.filter { MPStoragePageParser.isStorageSubject($0.summary.title) }
        #expect(storageRows.map { $0.summary.topicID?.topic } == [Self.storagePost, 3_139_922])
        let shown = page.hidingStorageThread(post: Self.storagePost)
        #expect(shown.threads == page.threads.filter { $0.summary.topicID?.topic != Self.storagePost })
        #expect(shown.threads.contains { $0.summary.topicID?.topic == 3_139_922 })
    }

    @Test("#1200 P1: a row another member sent with the storage subject is not hidden, unread or not")
    func keepsAnotherMembersStorageSubjectThread() {
        let page = PrivateMessageListPage(threads: [
            Self.thread(MPStorageDocument.subject, post: Self.storagePost, readState: .read),
            Self.thread(MPStorageDocument.subject, post: 99, readState: .unread)
        ])
        let shown = page.hidingStorageThread(post: Self.storagePost)
        #expect(shown.threads.map { $0.summary.topicID?.topic } == [99])
        #expect(shown.unreadThreadCount == 1)
    }

    @Test("#1200 P1: with no located storage thread, no row is hidden")
    func hidesNothingWithoutALocatedThread() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R13u1-mp-list-recipient-unread"), pageURL: Self.listURL)
        #expect(page.hidingStorageThread(post: nil) == page)
    }

    @Test("A page without its storage thread counts only the other unread threads")
    func filteredPageCountsOtherUnreadThreads() {
        let page = PrivateMessageListPage(threads: [
            Self.thread(MPStorageDocument.subject, post: Self.storagePost, readState: .unread),
            Self.thread("Private subject", post: 1, readState: .unread),
            Self.thread("Another", post: 2, readState: .read)
        ])
        #expect(page.unreadThreadCount == 2)
        #expect(page.hidingStorageThread(post: Self.storagePost).unreadThreadCount == 1)
    }

    @Test("A page without the storage thread is returned unchanged")
    func untouchedWithoutStorage() {
        let page = PrivateMessageListPage(threads: [
            Self.thread("Re: \(MPStorageDocument.subject)", post: Self.storagePost, readState: .unread)
        ])
        #expect(page.hidingStorageThread(post: Self.storagePost) == page)
    }

    @Test("Hiding is a view of the page: the finder still locates the thread in the same HTML")
    func finderStillFindsThread() throws {
        let html = try Fixture.capture("R13u1-mp-list-recipient-unread")
        #expect(try MPStoragePageParser.findThread(in: html, pageURL: Self.listURL).candidates == [Self.storagePost])
    }
}
