import Observation
import SwiftUI

// Port of HFRswift/Swift/HFRswiftApp.swift (HFRswiftApp: the shared singletons behind every `WindowGroup` window) @ 87fe0d1c.
// Differences: legacy's singletons are the app delegate's; here the shared models live in `SwiftHFRApp` and these two small
// holders keep what runs once per process or per change from running once per window (LOT-146, GAP-219).
/// Remembers what the app already did, so a handler attached to every window's content (SwiftUI runs it once per window) acts
/// once. The scene phase the `App` reads is the aggregate of all windows: two windows see the same change, and the second
/// must not repeat it.
@MainActor
final class AppWideEvents {
    private var seen: [String: AnyHashable] = [:]

    /// True when `value` is not the one last recorded under `key`, and records it: the first window to see a change acts,
    /// the others see the same value and do nothing.
    func isNew(_ value: some Hashable, for key: String) -> Bool {
        if seen[key] == AnyHashable(value) { return false }
        seen[key] = AnyHashable(value)
        return true
    }

    /// True the first time `key` is asked for in this process: work that belongs to the launch, not to a window.
    func firstTime(_ key: String) -> Bool {
        isNew(true, for: key)
    }
}

/// The unread private messages count of the current session, one for every window. Each window builds its own root
/// navigation, and a count per window would leave one window's Messages badge on a number another window has already
/// read (or sent the app icon back to). A new session generation (login, switch, logout) starts a new count, as the
/// per-root count did when there was one window.
@MainActor
final class SharedPrivateMessageCounts {
    private var generation: Int?
    private var count = PrivateMessageCount()

    /// The count of the session generation `generation`: the same object for every window asking about it.
    func count(forGeneration generation: Int) -> PrivateMessageCount {
        if self.generation != generation {
            self.generation = generation
            count = PrivateMessageCount()
        }
        return count
    }
}

extension EnvironmentValues {
    /// The per-process count holder, injected by the app; nil in previews and tests (each root then has its own count).
    @Entry var sharedPrivateMessageCounts: SharedPrivateMessageCounts?
}
