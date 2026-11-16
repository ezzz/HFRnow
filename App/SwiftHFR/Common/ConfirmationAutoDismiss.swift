import Foundation
import UIKit

/// The timer behind every success confirmation HFR sends back (reply, edit, delete, new topic, new MP, mark unread): it
/// clears the sentence 4 s after the last one was shown (#864, operator range 3-5 s). It belongs to the model, not to a
/// view's `.task`: a view that is rebuilt or covered while the page reloads after the send used to cancel the sleep and
/// leave the sentence up. Errors and "unconfirmed" messages never arm it: the member must read those. While VoiceOver
/// runs nothing is armed either: the system gives no reading time to wait for, so the sentence stays until the cross (#864
/// asks that the auto-dismiss never cut an announcement short).
@MainActor
final class ConfirmationAutoDismiss {
    /// How long a success stays: long enough to read, short enough not to linger.
    static let delay: Duration = .seconds(4)

    /// The wait, replaceable in tests so no real second passes.
    var sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// Whether VoiceOver is running, replaceable in tests.
    var isVoiceOverRunning: @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }
    private var task: Task<Void, Never>?
    /// Grows with every arm and cancel: a wait that finishes under an older number does nothing, whether or not its sleep
    /// honours cancellation, so an old timer can never clear a newer confirmation.
    private var generation = 0

    /// Starts the wait for a confirmation just shown, replacing the one pending; `clear` runs once it ends undisturbed.
    func arm(_ clear: @escaping @MainActor () -> Void) {
        task?.cancel()
        generation += 1
        guard !isVoiceOverRunning() else { return task = nil }
        let mine = generation
        // Strong on purpose: the model owns this timer, so the task cannot outlive it by more than the delay.
        task = Task {
            do { try await sleep(Self.delay) } catch { return }
            guard generation == mine else { return }
            task = nil
            clear()
        }
    }

    /// Stops the wait: the confirmation went away (the cross, or a new screen).
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }
}
