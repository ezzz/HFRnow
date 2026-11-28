import Foundation
import HFRClient
import HFRModels
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// The AQ doubles of the tests: the captured feed `T01` (LOT-001 corpus, run 10), parsed by the real `AQFeedParser`, behind a
/// scripted source. No network; no AQ answer is written by hand.
enum QualityAlertsTestSupport {
    /// The 25 items of `T01`, in document order.
    static func capturedItems() throws -> [AQFeedItem] {
        let captures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures")
        let data = try Data(contentsOf: captures.appending(path: "T01-aq-rss-feed.xml"))
        let text = try #require(String(data: data, encoding: .utf8))
        return try AQFeedParser.parse(text)
    }

    /// `item` as if it had been raised in forum 25: the captured link with its `cat` changed. `T01` holds no category 25 item
    /// (23 of its 25 links carry a `cat`, none is 25): a capture of one is pending, so the rule is tested on this derived value.
    static func inForum25(_ item: AQFeedItem) throws -> AQFeedItem {
        var derived = item
        let link = item.link.absoluteString.replacing(/cat=\d+/, with: "cat=25")
        derived.link = try #require(URL(string: link))
        return derived
    }

    /// 2026-10-01 00:00 UTC: two items of `T01` are newer (the oracle `LOT-028/T01.oracle.json` counts 2 for that last check).
    static let lastCheckOfTheOracle = Date(timeIntervalSince1970: 1_790_812_800)
    /// The instant a list is shown in the tests: after the newest item of `T01` (2026-10-11), so nothing is new after a visit.
    static let shownAt = Date(timeIntervalSince1970: 1_793_491_200)

    @MainActor
    static func model(
        source: (any QualityAlertsSource)?, store: InMemorySettingsStore = InMemorySettingsStore(),
        accountName: String? = nil, isLoggedIn: Bool = false, launchFeed: QualityAlertsLaunchFeed = QualityAlertsLaunchFeed()
    ) -> QualityAlertsModel {
        QualityAlertsModel(
            source: source, isLoggedIn: { isLoggedIn }, accountName: { accountName }, store: store, now: { shownAt },
            launchFeed: launchFeed
        )
    }
}

/// A source answering each call from a closure (called with its index, from 0) and counting them.
final class FakeQualityAlertsSource: QualityAlertsSource, @unchecked Sendable {
    typealias Answer = @Sendable (Int) async throws(AQError) -> [AQFeedItem]

    private let lock = NSLock()
    private var count = 0
    private let answer: Answer

    init(_ answer: @escaping Answer) { self.answer = answer }

    /// A source that always gives `items`.
    convenience init(items: [AQFeedItem]) {
        self.init { _ async throws(AQError) in items }
    }

    /// Requests received so far.
    var calls: Int { lock.withLock { count } }

    func feed() async throws(AQError) -> [AQFeedItem] {
        let index = lock.withLock { () -> Int in
            defer { count += 1 }
            return count
        }
        return try await answer(index)
    }
}

/// A latch: `wait()` returns once `open()` was called, before or after.
actor AQGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}
