@testable import SwiftHFR
import Testing

/// Lets a test hold a load open until it decides to finish it.
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
struct ContentLoaderTests {
    @Test func aSuccessfulLoadStoresTheValue() async {
        let loader = ContentLoader<Int>()
        await loader.load { 1 }
        #expect(loader.value == 1)
        #expect(loader.error == nil)
        #expect(!loader.isLoading)
    }

    @Test func aFailedReloadKeepsTheContentAndReportsTheError() async {
        let loader = ContentLoader<Int>()
        await loader.load { 1 }
        await loader.load { () async throws(ListLoadError) -> Int in throw .offline }
        #expect(loader.value == 1)
        #expect(loader.error == .offline)
        await loader.load { 2 }
        #expect(loader.value == 2)
        #expect(loader.error == nil)
    }

    @Test func contentStaysVisibleWhileAReloadRuns() async {
        let loader = ContentLoader<Int>()
        await loader.load { 1 }
        let gate = Gate()
        let reload = Task { await loader.load { await gate.wait(); return 2 } }
        await Task.yield()
        #expect(loader.value == 1)
        #expect(loader.isLoading)
        await gate.open()
        await reload.value
        #expect(loader.value == 2)
    }

    @Test func aSupersededLoadCannotOverwriteTheNewerOne() async {
        let loader = ContentLoader<Int>()
        let gate = Gate()
        let slow = Task { await loader.load { await gate.wait(); return 1 } }
        await Task.yield()
        await loader.load { 2 }
        await gate.open()
        await slow.value
        #expect(loader.value == 2)
        #expect(!loader.isLoading)
    }

    @Test func aCancelledLoadIsNotAnError() async {
        let loader = ContentLoader<Int>()
        await loader.load { () async throws(ListLoadError) -> Int in throw .cancelled }
        #expect(loader.error == nil)
        #expect(loader.value == nil)
        #expect(!loader.isLoading)
    }

    @Test func cancelStopsTheLoadAndDropsItsResult() async {
        let loader = ContentLoader<Int>()
        let gate = Gate()
        let slow = Task { await loader.load { await gate.wait(); return 1 } }
        await Task.yield()
        loader.cancel()
        await gate.open()
        await slow.value
        #expect(loader.value == nil)
        #expect(!loader.isLoading)
    }
}
