import Foundation
import HFRModels
import HFRParsing
@testable import SwiftHFR
import Testing

/// The long-press menus of the MP rows and of the search results (#1311): legacy `TopicQuickActionPolicy.privateMessages` and
/// `.globalSearch` (`Common.swift:2587-2625`, `:3558-3600` @ 87fe0d1c), on the captured lists (`R13u1`, `R50b`).
@MainActor
struct TopicRowMenuTests {
    private static let mpListURL = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1"
    private static let searchURL = "/forum1.php?recherches=1&cat=13&orderSearch=0&config=hfr.inc&pseud=&search=pizza+napolitaine&titre=3"

    private static func mpThreads() throws -> [PrivateMessageThread] {
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture("R13u1-mp-list-recipient-unread.html"), encoding: .utf8))
        return try PrivateMessageListParser.parse(html, pageURL: mpListURL).threads
    }

    private static func searchRows() throws -> [TopicSummary] {
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture("R50b-search-results-no-cookie.html"), encoding: .utf8))
        return try TopicListParser.parse(html, pageURL: searchURL).topics
    }

    private func kinds(_ entries: [TopicRowMenuEntry]) -> [String] {
        entries.map {
            switch $0 {
            case .searchMatch: "match"
            case .firstPage: "first"
            case .lastPage: "last"
            case .lastReply: "reply"
            case .pagePrompt: "page"
            case .copyLink: "copy"
            }
        }
    }

    // MARK: MP rows

    /// Legacy `showOpenLastReply: false` for `.privateMessages`.
    @Test func anMPRowOffersFourEntriesAndNoLastReply() throws {
        for thread in try Self.mpThreads() {
            #expect(kinds(TopicQuickActions.menu(of: thread.summary, in: .privateMessages)) == ["first", "last", "page", "copy"])
        }
    }

    @Test func theLongCapturedConversationOpensItsFirstAndItsLastPageFromTheRowLinks() throws {
        let long = try #require(try Self.mpThreads().first { $0.summary.pageCount == 457 })
        let entries = TopicQuickActions.menu(of: long.summary, in: .privateMessages)
        let id = try #require(long.summary.topicID)
        #expect(id.category == .privateMessages)
        #expect(entries.contains(.firstPage(TopicOpening(target: ReaderTarget(source: .topic(id), page: 1)))))
        #expect(entries.contains(.lastPage(TopicOpening(target: ReaderTarget(source: .topic(id), page: 457)))))
        // "Page numéro…" stays inside the thread's pages.
        #expect(TopicQuickActions.page(458, of: long.summary) == nil)
        #expect(TopicQuickActions.page(1, of: long.summary) != nil)
    }

    @Test func anMPRowCopiesItsFirstPageLinkAsAForumLink() throws {
        let thread = try #require(try Self.mpThreads().first)
        let link = try #require(TopicQuickActions.link(of: thread.summary))
        #expect(link.host() == "forum.hardware.fr")
        #expect(link.absoluteString.contains("cat=prive&post="))
    }

    @Test func anMPRowWithNoLinkAndNoTopicNumberOffersNothingItCannotRun() {
        let row = TopicSummary(title: "x", path: "https://example.com/elsewhere")
        #expect(TopicQuickActions.menu(of: row, in: .privateMessages).isEmpty)
    }

    @Test func choosingAnMPEntryOpensTheReaderAtItsTarget() async throws {
        let thread = try #require(try Self.mpThreads().first { $0.summary.pageCount == 457 })
        let model = MessageListModel(source: FakePrivateMessages(), isLoggedIn: { true })
        let id = try #require(thread.summary.topicID)
        let opening = try #require(TopicQuickActions.firstPage(of: thread.summary))
        model.open(thread, at: opening)
        #expect(model.selected == thread)
        #expect(model.reader(for: thread)?.requested == ReaderTarget(source: .topic(id), page: 1))
        // Another entry on the conversation already on screen replaces its reader (and rebuilds the view).
        let generation = model.readerGeneration
        let last = try #require(TopicQuickActions.lastPage(of: thread.summary))
        model.open(thread, at: last)
        #expect(model.readerGeneration == generation + 1)
        #expect(model.reader(for: thread)?.requested == ReaderTarget(source: .topic(id), page: 457))
    }

    /// #1089: the stack only changes identity when the conversation stays selected, so what a link pushed must be closed.
    @Test func anMPEntryOnTheConversationOnScreenClosesItsPushedReaders() async throws {
        let thread = try #require(try Self.mpThreads().first { $0.summary.pageCount == 457 })
        let id = try #require(thread.summary.topicID)
        let model = MessageListModel(
            source: FakePrivateMessages(), isLoggedIn: { true }, topicPages: FakeTopicPages { _ in readerPage(page: 1) }
        )
        model.selected = thread
        let shown = try #require(model.reader(for: thread))
        shown.follow(ReaderTarget(source: .topic(id), page: 4))
        #expect(shown.linkedReader != nil)
        model.open(thread, at: try #require(TopicQuickActions.lastPage(of: thread.summary)))
        #expect(shown.linkedReader == nil)
    }

    // MARK: Search results

    @Test func aSearchEntryOnTheResultOnScreenClosesItsPushedReaders() async throws {
        let row = try #require(try Self.searchRows().first)
        let id = try #require(row.topicID)
        let model = ForumSearchModel(source: FakeSearchSource(), topicPages: FakeTopicPages { _ in readerPage(page: 1) })
        model.selected = row
        let shown = try #require(model.reader(for: row))
        shown.follow(ReaderTarget(source: .topic(id), page: 4))
        #expect(shown.linkedReader != nil)
        model.open(row, at: try #require(TopicQuickActions.firstPage(of: row)))
        #expect(shown.linkedReader == nil)
    }

    /// Legacy order: "Dernière correspondance" first, then the five.
    @Test func aSearchResultOffersTheSixEntriesInLegacyOrder() throws {
        for row in try Self.searchRows() {
            #expect(kinds(TopicQuickActions.menu(of: row, in: .globalSearch)) == ["match", "first", "last", "reply", "page", "copy"])
        }
    }

    @Test func derniereCorrespondanceOpensTheMatchingMessageAtItsAnchor() throws {
        let row = try #require(try Self.searchRows().first)
        let opening = try #require(TopicQuickActions.searchMatch(of: row))
        #expect(opening == ForumSearchModel.target(of: row).map { TopicOpening(target: $0) })
        #expect(opening.target.numreponse == 75_456_630)
        #expect(!opening.atLastMessage)
    }

    @Test func aResultWithoutMatchHasNoDerniereCorrespondance() throws {
        var row = try #require(try Self.searchRows().first)
        row.searchHit = nil
        #expect(!kinds(TopicQuickActions.menu(of: row, in: .globalSearch)).contains("match"))
    }

    @Test func aRowMenuNeverOffersDerniereCorrespondanceOutsideSearch() throws {
        let row = try #require(try Self.searchRows().first)
        #expect(!kinds(TopicQuickActions.menu(of: row, in: .privateMessages)).contains("match"))
        #expect(!kinds(TopicQuickActions.menu(of: row, in: .privateMessages)).contains("reply"))
    }

    @Test func choosingASearchEntryOpensTheReaderAtItsTargetAndTheTapStaysTheMatch() async throws {
        let row = try #require(try Self.searchRows().first)
        let model = ForumSearchModel(source: FakeSearchSource())
        let id = try #require(row.topicID)
        // A plain tap keeps opening the matching message.
        model.selected = row
        #expect(model.reader(for: row)?.requested == ForumSearchModel.target(of: row))
        let opening = try #require(TopicQuickActions.firstPage(of: row))
        let generation = model.readerGeneration
        model.open(row, at: opening)
        #expect(model.readerGeneration == generation + 1)
        #expect(model.reader(for: row)?.requested == ReaderTarget(source: .topic(id), page: 1))
    }
}
