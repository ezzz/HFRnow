import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// The picker's lists live as long as the composer (#1397): a second opening reads nothing again; a failure is asked again.
struct SmileyListMemoTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func next() -> Int { lock.withLock { value += 1; return value } }
    }

    @Test func aSecondOpeningReadsNothingAgain() async {
        let reads = Counter()
        let memo = SmileyListMemo<ForumSmiley>()
        let load = memo.memoized { _ = reads.next(); return [] }
        for _ in 0..<3 { _ = await load() }
        #expect(reads.count == 1)
    }

    @Test func aFailureIsNotKeptSoRetryReachesTheForum() async {
        let reads = Counter()
        let memo = SmileyListMemo<ForumSmiley>()
        let load = memo.memoized { reads.next() == 1 ? nil : [] }
        #expect(await load() == nil)
        #expect(await load() != nil)
        #expect(await load() != nil)
        #expect(reads.count == 2)
    }
}
