import Foundation
import HFRModels
import Observation

/// The reader's settings, read again on every `UserDefaults` change while the reader is on screen: the page swipe and the
/// reply button settings, and the page's own display settings (`changed`). Started and stopped with the reader's presence
/// (`ReaderWebController+Presence`), not by a `.task`: SwiftUI cancels a view's tasks on the `onDisappear` it sends a reader
/// pushed again, which then stays on screen with no `onAppear` (issue #750; measured on #786).
@MainActor
@Observable
final class ReaderSettingsWatch {
    /// `topic_page_swipe_navigation`: with it off no gesture is attached to the web view, as legacy's `including: .none`.
    private(set) var swipesPages = true
    /// `reply_button_behavior` (LOT-086).
    private(set) var replyButton = ReplyButtonBehavior.quick
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Whether the watch runs.
    var isRunning: Bool { task != nil }

    /// Reads `settings` and calls `changed` now (a change made while the reader was away), then again on every change until
    /// `stop()`. A watch already running is kept.
    func start(_ settings: ReaderSettings, changed: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        ReaderLog.debug("settings watch start")
        read(settings)
        changed()
        // Made here, not in the task: a change between this call and the task's first run is not lost.
        let changes = NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification)
        task = Task { [weak self] in
            for await _ in changes {
                // A change that resumed this task before `stop()` ran waits for the main actor: `stop()` cancels first, so
                // it is dropped here and nothing is read or delivered after `stop()` (#839).
                guard let self, !Task.isCancelled else { return }
                read(settings)
                changed()
            }
        }
    }

    /// The reader left the screen.
    func stop() {
        if task != nil { ReaderLog.debug("settings watch stop") }
        task?.cancel()
        task = nil
    }

    private func read(_ settings: ReaderSettings) {
        swipesPages = settings.swipesPages()
        replyButton = settings.replyButton()
    }
}
