import Observation
import SwiftUI

// Port: none @ 87fe0d1c. Legacy runs its launch work once in the app delegate; these holders give the SwiftUI scene content
// that guarantee back when several windows exist (LOT-146, GAP-219).
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

/// Which window presents what a shared model raises (the dated-icon question, the import summary): one window each, as the
/// seasonal arrival alert does (`SeasonalThemeModel.alert(for:)`). Without it every window would show the same alert.
@MainActor
@Observable
final class SceneClaims {
    /// The window presenting each thing, by key.
    private(set) var owners: [String: UUID] = [:]

    /// `scene` presents `key` unless another window already does.
    func claim(_ key: String, scene: UUID) {
        if owners[key] == nil { owners[key] = scene }
    }

    /// Whether `scene` is the window presenting `key`.
    func isPresenting(_ key: String, scene: UUID) -> Bool {
        owners[key] == scene
    }

    /// The window's own scene phase changed: only a window on screen presents. A window going to the background gives up what it
    /// presented, so the next one on screen takes it (as the seasonal alerts wait for an active scene); an active window claims
    /// `key` when nobody holds it.
    func phaseChanged(_ phase: ScenePhase, scene: UUID, key: String) {
        switch phase {
        case .active: claim(key, scene: scene)
        case .background: release(scene: scene)
        default: break
        }
    }

    /// The window is gone: what it presented goes to the next window that claims it.
    func release(scene: UUID) {
        owners = owners.filter { $0.value != scene }
    }
}

extension EnvironmentValues {
    /// The window claims, injected by the app; nil in previews and tests (the window then presents everything).
    @Entry var sceneClaims: SceneClaims?
}

/// One window's claim on one thing a shared model presents. A view reads `isOpen` to know whether it may present it.
@MainActor
struct SceneGate: DynamicProperty {
    let key: String
    @Environment(\.sceneClaims) private var claims
    @Environment(\.scenePhase) private var phase
    @State private var scene = UUID()

    /// True when this window presents `key` (always without claims).
    var isOpen: Bool { claims?.isPresenting(key, scene: scene) ?? true }
    /// The current owner, for `onChange`: a window re-claims when the owner left.
    var owner: UUID? { claims?.owners[key] }

    /// This window's own phase (read inside the scene), for `onChange`.
    var scenePhase: ScenePhase { phase }

    /// The window's phase changed, or the owner left: an active window claims, a background one gives up.
    func refresh() { claims?.phaseChanged(phase, scene: scene, key: key) }
    /// The window is gone.
    func release() { claims?.release(scene: scene) }
}
