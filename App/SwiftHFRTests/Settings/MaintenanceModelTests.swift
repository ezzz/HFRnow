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

    @Test func aNewMeasureReplacesTheOldOne() async {
        let counter = Counter()
        let model = MaintenanceModel(openSettings: {}, measureCaches: {
            CacheStorageSnapshot(totalBytes: Int64(counter.next()), htmlBytes: 0, htmlFileCount: 0)
        })
        await model.refreshCacheStorage()
        await model.refreshCacheStorage()
        #expect(model.cacheStorage?.totalBytes == 2)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
