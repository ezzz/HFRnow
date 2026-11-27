import HFRModels
import Testing
@testable import HFRParsing

/// #1074: the account's MPStorage thread stays out of the member's list and unread counts, while its finder still sees it.
/// #1200 P1: a storage-subject row is hidden only when it is the located thread or a one-to-one thread with the storage
/// recipient; another member's MP with the subject stays visible. The captures alias the recipient `MultiMP` per file
/// (FIXTURES.md): `R13u1` names it `user117`, `R333b` `user3`, as their `[non lu]` tooltips show.
@Suite("MPStorage thread hidden from the MP list")
struct MPStorageThreadHidingTests {
    static let listURL = "/forum1.php?config=hfr.inc&cat=prive&page=1"
    static let pageTwoURL = "/forum1.php?config=hfr.inc&cat=prive&page=2"

    /// The storage thread of `R13u1` and of `R333b` row 1 (`R60a`).
    static let storagePost = 3_157_083

    /// The storage recipient as `R13u1` and `R333b` alias it.
    static let recipientInR13u1 = "user117"
    static let recipientInR333b = "user3"
    static let recipientInR1203a = "user107"

    /// The thread with the storage subject that user2 sent to the account (#1203, `R1203a` row 1).
    static let foreignPost = 3_209_728

    private static func thread(
        _ title: String, post: Int? = nil, readState: TopicReadState, with interlocutors: [String] = ["user9"], group: Bool = false
    ) -> PrivateMessageThread {
        let topicID = post.map { TopicID(category: .privateMessages, topic: $0) }
        return PrivateMessageThread(
            summary: TopicSummary(topicID: topicID, title: title, path: "/x", readState: readState),
            interlocutors: interlocutors, isGroup: group
        )
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

    @Test("#1200 P1, R333b: both of the account's storage rows (to the recipient) are dropped, located or not")
    func dropsTheAccountsStorageRowsByRecipient() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R333b-mp-list-p2-storage-row-first"), pageURL: Self.pageTwoURL)
        let storageRows = page.threads.filter { MPStoragePageParser.isStorageSubject($0.summary.title) }
        #expect(storageRows.map { $0.summary.topicID?.topic } == [Self.storagePost, 3_139_922])
        #expect(storageRows.allSatisfy { !$0.isGroup && $0.interlocutors == [Self.recipientInR333b] })
        for located in [Self.storagePost, nil] as [Int?] {
            let shown = page.hidingStorageThread(post: located, recipient: Self.recipientInR333b)
            #expect(shown.threads == page.threads.filter { !MPStoragePageParser.isStorageSubject($0.summary.title) })
        }
    }

    @Test("#1200 P1: R13u1's storage row is hidden before the sync located it, by its recipient")
    func dropsTheStorageRowBeforeItIsLocated() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R13u1-mp-list-recipient-unread"), pageURL: Self.listURL)
        let shown = page.hidingStorageThread(post: nil, recipient: Self.recipientInR13u1)
        #expect(!shown.threads.contains { $0.summary.topicID?.topic == Self.storagePost })
        #expect(shown.threads.count == page.threads.count - 1)
    }

    @Test("#1200 P1: a row another member sent with the storage subject is not hidden, unread or not")
    func keepsForeignStorageSubjectRowVisible() {
        let page = PrivateMessageListPage(threads: [
            Self.thread(MPStorageDocument.subject, post: Self.storagePost, readState: .read, with: ["MultiMP"]),
            Self.thread(MPStorageDocument.subject, post: 99, readState: .unread, with: ["user9"]),
            Self.thread(MPStorageDocument.subject, post: 98, readState: .unread, with: ["MultiMP", "user9"], group: true)
        ])
        for located in [Self.storagePost, nil] as [Int?] {
            let shown = page.hidingStorageThread(post: located)
            #expect(shown.threads.map { $0.summary.topicID?.topic } == [99, 98])
            #expect(shown.unreadThreadCount == 2)
        }
    }

    @Test("#1203, R1203a: the captured row user2 sent with the storage subject stays visible, the account's own is hidden")
    func keepsCapturedForeignStorageRowVisible() throws {
        let page = try PrivateMessageListParser.parse(Fixture.capture("R1203a-mp-list-foreign-storage-row-unread"), pageURL: Self.listURL)
        let storageRows = page.threads.filter { MPStoragePageParser.isStorageSubject($0.summary.title) }
        #expect(storageRows.map { $0.summary.topicID?.topic } == [Self.foreignPost, Self.storagePost])
        let foreign = try #require(storageRows.first)
        // HFR prints the interlocutor with a U+200B (long pseudos, HFR-PROTOCOL "Printed pseudos").
        #expect(!foreign.isGroup && foreign.interlocutors.map { $0.replacing("\u{200B}", with: "") } == ["user2"])
        #expect(foreign.summary.readState == .unread)
        for located in [Self.storagePost, nil] as [Int?] {
            let shown = page.hidingStorageThread(post: located, recipient: Self.recipientInR1203a)
            #expect(shown.threads == page.threads.filter { $0.summary.topicID?.topic != Self.storagePost })
            #expect(shown.unreadThreadCount == page.unreadThreadCount)
        }
    }

    @Test("#1203, R1203a → R1203c: the storage search's GET of the thread's first page alone marks it read for the account")
    func searchGetMarksTheForeignThreadRead() throws {
        let before = try PrivateMessageListParser.parse(Fixture.capture("R1203a-mp-list-foreign-storage-row-unread"), pageURL: Self.listURL)
        let after = try PrivateMessageListParser.parse(
            Fixture.capture("R1203c-mp-list-foreign-storage-row-after-get"), pageURL: Self.listURL
        )
        let row = { (page: PrivateMessageListPage) in page.threads.first { $0.summary.topicID?.topic == Self.foreignPost } }
        #expect(try #require(row(before)).summary.readState == .unread)
        #expect(try #require(row(after)).summary.readState == .read)
        #expect(after.unreadThreadCount == before.unreadThreadCount - 1)
    }

    @Test("#1200 P1: the located thread is hidden whatever its row names")
    func dropsTheLocatedThreadWhateverItsInterlocutor() {
        let page = PrivateMessageListPage(threads: [Self.thread(MPStorageDocument.subject, post: Self.storagePost, readState: .read)])
        #expect(page.hidingStorageThread(post: Self.storagePost).threads.isEmpty)
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
