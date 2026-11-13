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
