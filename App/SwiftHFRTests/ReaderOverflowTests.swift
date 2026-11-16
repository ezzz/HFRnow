import HFRClient
import HFRModels
import HFRNetwork
import Testing
@testable import SwiftHFR

/// #645: the reader's "…" overflow reads like legacy's (`MessagesView.swift:5589-5604` @ 87fe0d1c): Rechercher, then the
/// offline save, the post filter, and the page items last.
struct ReaderOverflowTests {
    @Test func theFullMenuEndsWithThePageItems() {
        let all = ReaderOverflow.entries(search: true, offline: true, filter: true, pages: true)
        #expect(all == [.search, .offline, .filter, .pages])
    }

    @Test func absentEntriesLeaveTheOthersInOrder() {
        #expect(ReaderOverflow.entries(search: false, offline: true, filter: true, pages: true) == [.offline, .filter, .pages])
        #expect(ReaderOverflow.entries(search: true, offline: false, filter: false, pages: true) == [.search, .pages])
        #expect(ReaderOverflow.entries(search: false, offline: false, filter: false, pages: false).isEmpty)
    }
}

/// #821: logged out, the reader's menu keeps « Rechercher » and a tap asks to sign in instead of searching.
@MainActor
struct ReaderSearchLoggedOutTests {
    private struct NeverSearch: TopicSearching {
        func search(_ query: TopicSearchQuery) async throws(TopicSearchError) -> TopicSearchResult {
            Issue.record("a search request was sent")
            return .noMatch
        }
    }

    private func offered(
        topic: Bool = true, isPrivate: Bool = false, suspended: Bool = false, searcher: Bool = false, live: Bool = true
    ) -> Bool {
        ReaderSearchFlow.isOffered(
            hasTopic: topic, isPrivate: isPrivate, suspended: suspended, hasSearcher: searcher, isLiveReader: live)
    }

    @Test func theEntryIsInTheMenuWithoutAnAccount() {
        #expect(offered(searcher: false))
        #expect(offered(searcher: true))
        #expect(ReaderOverflow.entries(search: offered(), offline: false, filter: false, pages: true) == [.search, .pages])
    }

    @Test func theOfflineReaderHasNoEntryWithoutASearcher() {
        // Signed in or not, the saved copy has no composer: no search to run and no sign-in to ask for.
        #expect(!offered(searcher: false, live: false))
    }

    @Test func theEntryStaysOutOfPrivateConversationsAndUnderAnOpenComposer() {
        #expect(!offered(isPrivate: true))
        #expect(!offered(suspended: true))
        #expect(!offered(topic: false))
    }

    @Test func aTapLoggedOutAsksToSignInAndSendsNoSearch() {
        guard case .signIn = ReaderSearchFlow.tap(topic: readerTopic, searcher: nil) else {
            Issue.record("expected the sign-in prompt")
            return
        }
    }

    @Test func aTapLoggedInOpensTheSearch() {
        guard case .search(let topic, _) = ReaderSearchFlow.tap(topic: readerTopic, searcher: NeverSearch()) else {
            Issue.record("expected the search")
            return
        }
        #expect(topic == readerTopic)
    }

    @Test func aPageWithoutTopicDoesNothing() {
        #expect(ReaderSearchFlow.tap(topic: nil, searcher: nil) == nil)
    }
}
