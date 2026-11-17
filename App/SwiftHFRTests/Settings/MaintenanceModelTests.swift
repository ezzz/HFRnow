import Foundation
@testable import SwiftHFR
import Testing

@MainActor
struct MaintenanceModelTests {
    @Test func theShortcutOpensTheSystemSettingsOncePerTap() {
        var opened = 0
        let model = MaintenanceModel(openSettings: { opened += 1 })
        #expect(opened == 0)
        model.openSystemSettings()
        #expect(opened == 1)
        model.openSystemSettings()
        #expect(opened == 2)
    }

    @Test func creatingTheModelOpensNothing() {
        var opened = 0
        _ = MaintenanceModel(openSettings: { opened += 1 })
        #expect(opened == 0)
    }

    @Test func theSizesAreEmptyUntilMeasuredThenHoldTheMeasure() async {
        let expected = CacheStorageSnapshot(totalBytes: 3_000, htmlBytes: 2_000, htmlFileCount: 4)
        let model = MaintenanceModel(openSettings: {}, measureCaches: { expected })
        #expect(model.cacheStorage == nil)
        await model.refreshCacheStorage()
        #expect(model.cacheStorage == expected)
    }

    @Test func theMeasureStartedLastWinsWhateverTheOrderOfTheEnds() async {
        let gate = SlowFirstMeasure()
        let model = MaintenanceModel(openSettings: {}, measureCaches: { gate.measure() })
        let first = Task { await model.refreshCacheStorage() }
        while !gate.firstHasStarted { await Task.yield() }
        // The second measure ends while the first is still held: the first then ends last, with an older result.
        await model.refreshCacheStorage()
        #expect(model.cacheStorage?.totalBytes == 2)
        gate.releaseFirst()
        await first.value
        #expect(model.cacheStorage?.totalBytes == 2)
    }
}

/// A measure whose first call waits to be released, so the first of two refreshes ends after the second.
private final class SlowFirstMeasure: @unchecked Sendable {
    private let condition = NSCondition()
    private var calls = 0
    private var released = false

    var firstHasStarted: Bool {
        condition.withLock { calls >= 1 }
    }

    func releaseFirst() {
        condition.withLock {
            released = true
            condition.broadcast()
        }
    }

    func measure() -> CacheStorageSnapshot {
        condition.lock()
        calls += 1
        let call = calls
        if call == 1 {
            while !released { condition.wait() }
        }
        condition.unlock()
        return CacheStorageSnapshot(totalBytes: Int64(call), htmlBytes: 0, htmlFileCount: 0)
    }
}
