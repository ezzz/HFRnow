import Foundation
import Observation

/// What a tap on the Version row does: copy the build report, announce it, and show « Copié » for a while (#970).
@Observable @MainActor
final class VersionCopyModel {
    /// True while the « Copié » confirmation is shown.
    private(set) var copied = false
    /// The task that ends the confirmation; a new tap cancels it so the last tap always gets the full duration.
    private(set) var reset: Task<Void, Never>?

    private let report: () -> String
    private let write: (String) -> Void
    private let announce: (String) -> Void
    private let confirmation: Duration

    /// A model over the report to copy, the pasteboard write, the VoiceOver announcement and the confirmation's duration.
    init(
        report: @escaping () -> String, write: @escaping (String) -> Void, announce: @escaping (String) -> Void,
        confirmation: Duration = .seconds(2)
    ) {
        self.report = report
        self.write = write
        self.announce = announce
        self.confirmation = confirmation
    }

    /// Copies the report, then confirms it.
    func copy() {
        write(report())
        copied = true
        announce("Copié")
        reset?.cancel()
        reset = Task {
            try? await Task.sleep(for: confirmation)
            if !Task.isCancelled { copied = false }
        }
    }
}
