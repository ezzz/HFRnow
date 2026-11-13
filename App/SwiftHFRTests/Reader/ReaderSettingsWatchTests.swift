import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// Fable round 1 on #786, finding 3: the reader's settings follow `UserDefaults` while the reader is on screen, from a watch
/// its presence starts and stops, not from a `.task` SwiftUI cancels on the `onDisappear` of a reader pushed again (#750).
@MainActor
struct ReaderSettingsWatchTests {
    private final class Values: @unchecked Sendable {
        private let lock = NSLock()
        private var swipes = true
        private var reply = ReplyButtonBehavior.quick
        var swipesPages: Bool {
            get { lock.withLock { swipes } }
            set { lock.withLock { swipes = newValue } }
        }
        var replyButton: ReplyButtonBehavior {
            get { lock.withLock { reply } }
            set { lock.withLock { reply = newValue } }
        }
    }

    private func settings(_ values: Values) -> ReaderSettings {
        ReaderSettings(
            autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() },
            swipesPages: { values.swipesPages }, replyButton: { values.replyButton }
        )
    }

    /// Posts the change until the watch has read it: the watch's task may not be iterating yet at the first post.
    private func postChange(until condition: () -> Bool) async -> Bool {
        for attempt in 0..<2_000 {
            if condition() { return true }
            if attempt.isMultiple(of: 50) {
                NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
            }
            await Task.yield()
        }
        return condition()
    }

    @Test func aStartedWatchReadsNowThenFollowsEveryChangeUntilStopped() async {
        let values = Values()
        values.swipesPages = false
        let watch = ReaderSettingsWatch()
        var changes = 0
        watch.start(settings(values)) { changes += 1 }
        #expect(!watch.swipesPages)
        #expect(changes == 1)
        values.replyButton = .hidden
        #expect(await postChange { watch.replyButton == .hidden })
        #expect(changes >= 2)
        watch.stop()
        #expect(!watch.isRunning)
        let stopped = changes
        values.swipesPages = true
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        for _ in 0..<200 { await Task.yield() }
        #expect(!watch.swipesPages)
        #expect(changes == stopped)
    }

    /// #839: a change already posted when `stop()` runs sits in the notification stream; the watch's task must not read it
    /// afterwards. Forced interleaving: the task is parked waiting for a change, then the post resumes it and `stop()` runs with
    /// no suspension in between, so the resumed task reaches its body only after the cancellation.
    @Test func aChangeQueuedBeforeStopIsNeverDelivered() async {
        for _ in 0..<20 {
            let values = Values()
            let watch = ReaderSettingsWatch()
            var changes = 0
            watch.start(settings(values)) { changes += 1 }
            for _ in 0..<50 { await Task.yield() }
            values.swipesPages = false
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
            watch.stop()
            for _ in 0..<50 { await Task.yield() }
            #expect(watch.swipesPages)
            #expect(changes == 1)
        }
    }

    /// The window bringing a reader back starts the watch again; starting a running one changes nothing.
    @Test func startingARunningWatchKeepsIt() {
        let watch = ReaderSettingsWatch()
        var changes = 0
        watch.start(settings(Values())) { changes += 1 }
        watch.start(settings(Values())) { changes += 1 }
        #expect(changes == 1)
        #expect(watch.isRunning)
        watch.stop()
    }
}
