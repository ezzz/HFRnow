import HFRModels
import Testing
@testable import HFRParsing

/// #1074: the MPStorage thread stays out of the member's list and unread counts, while its finder still sees it.
@Suite("MPStorage thread hidden from the MP list")
struct MPStorageThreadHidingTests {
    static let listURL = "/forum1.php?config=hfr.inc&cat=prive&page=1"
    static let pageTwoURL = "/forum1.php?config=hfr.inc&cat=prive&page=2"

    private static func thread(_ title: String, readState: TopicReadState) -> PrivateMessageThread {
        PrivateMessageThread(summary: TopicSummary(title: title, path: "/x", readState: readState))
    }

    @Test("R13u1: the storage row (marked [non lu]) is dropped, the other rows keep their order")
    func dropsMarkedRow() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R13u1-mp-list-recipient-unread"), pageURL: Self.listURL)
        let shown = page.hidingStorageThread()
        #expect(page.threads.contains { MPStoragePageParser.isStorageSubject($0.summary.title) })
        #expect(!shown.threads.contains { MPStoragePageParser.isStorageSubject($0.summary.title) })
        #expect(shown.threads == page.threads.filter { !MPStoragePageParser.isStorageSubject($0.summary.title) })
        #expect(shown.threads.count == page.threads.count - 1)
        #expect(shown.navigation == page.navigation)
        #expect(shown.newMessagePath == page.newMessagePath)
    }

    @Test("R333b: both storage-subject rows of page 2 are dropped")
    func dropsEveryStorageRow() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R333b-mp-list-p2-storage-row-first"), pageURL: Self.pageTwoURL)
        #expect(page.threads.filter { MPStoragePageParser.isStorageSubject($0.summary.title) }.count == 2)
        #expect(page.hidingStorageThread().threads.count == page.threads.count - 2)
    }

    @Test("A page without its storage thread counts only the other unread threads")
    func filteredPageCountsOtherUnreadThreads() {
        let page = PrivateMessageListPage(threads: [
            Self.thread(MPStorageDocument.subject, readState: .unread),
            Self.thread("Private subject", readState: .unread),
            Self.thread("Another", readState: .read)
        ])
        #expect(page.unreadThreadCount == 2)
        #expect(page.hidingStorageThread().unreadThreadCount == 1)
    }

    @Test("A page without the storage thread is returned unchanged")
    func untouchedWithoutStorage() {
        let page = PrivateMessageListPage(threads: [Self.thread("Re: \(MPStorageDocument.subject)", readState: .unread)])
        #expect(page.hidingStorageThread() == page)
    }

    @Test("Hiding is a view of the page: the finder still locates the thread in the same HTML")
    func finderStillFindsThread() throws {
        let html = try Fixture.capture("R13u1-mp-list-recipient-unread")
        #expect(try MPStoragePageParser.findThread(in: html, pageURL: Self.listURL) == .found(post: 3_157_083))
    }
}
