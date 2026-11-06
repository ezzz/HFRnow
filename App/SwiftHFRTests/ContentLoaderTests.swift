@testable import SwiftHFR
import Testing

// The suite limit is a backstop for a hang only: on a loaded simulator it measures the shared main-actor queue (#366).
@MainActor @Suite(.timeLimit(.minutes(5)))
struct ContentLoaderTests {
    @Test func resetForgetsTheValueAndTheError() async {
        let loader = ContentLoader<Int>()
        await loader.load { () async throws(ListLoadError) -> Int in 1 }
        await loader.load { () async throws(ListLoadError) -> Int in throw .offline }
        #expect(loader.value == 1 && loader.error == .offline)
        loader.reset()
        #expect(loader.value == nil && loader.error == nil && !loader.isLoading)
    }

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
        let gate = CheckGate()
        let reload = gate.run { await loader.load { await gate.wait(); return 2 } }
        guard await gate.entered() else { Issue.record("The reload never started"); return }
        #expect(loader.value == 1)
        #expect(loader.isLoading)
        await gate.open()
        await reload.value
        #expect(loader.value == 2)
    }

    @Test func aSupersededLoadCannotOverwriteTheNewerOne() async {
        let loader = ContentLoader<Int>()
        let gate = CheckGate()
        let slow = gate.run { await loader.load { await gate.wait(); return 1 } }
        guard await gate.entered() else { Issue.record("The load never started"); return }
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
        let gate = CheckGate()
        let slow = gate.run { await loader.load { await gate.wait(); return 1 } }
        guard await gate.entered() else { Issue.record("The load never started"); return }
        loader.cancel()
        await gate.open()
        await slow.value
        #expect(loader.value == nil)
        #expect(!loader.isLoading)
    }
}
