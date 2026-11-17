import Foundation
import Observation

/// The elves of the packing (THEMES.md §5), one for the app: on the first launch 27/12–02/01 with a Noël theme on and animations
/// allowed, the scheduler has already restored the user's theme in the store (a kill meanwhile loses nothing); this keeps the
/// seasonal theme drawn until the elves have taken it down, at most `duration` (THEMES.md §4 rule 3), in one scene, on a clear
/// screen (rule 5). Without animations nothing is queued and the user's theme shows at once.
@MainActor
@Observable
final class NoelPackingModel {
    /// One packing, waiting for a clear screen or playing in `scene`.
    struct Packing: Equatable {
        /// The season being packed.
        let year: Int
        /// The seasonal theme still drawn until the elves are done.
        let theme: SeasonalTheme
        /// The scene playing it; nil while it waits.
        var scene: UUID?
    }

    /// How long the elves play: within the 5 s of an overlay (THEMES.md §4 rule 3).
    static let duration: TimeInterval = 4.5

    /// The packing waiting or playing; nil once done.
    private(set) var current: Packing?
    /// The elves are on screen: the decorations fade while they play.
    var isPlaying: Bool { current?.scene != nil }

    @ObservationIgnored private var isForeground = false

    /// The scheduler packed `theme` of season `year` with animations allowed: it stays drawn until the elves have played.
    func queue(year: Int, theme: SeasonalTheme) {
        current = Packing(year: year, theme: theme)
    }

    /// The app came to the foreground (`true`) or left it; elves on screen stop when it leaves, and the decorations go with
    /// them. A packing still waiting keeps waiting.
    func foregroundChanged(active: Bool) {
        isForeground = active
        if !active, isPlaying { current = nil }
    }

    /// The packing `scene` may play now: the one it already plays, or the waiting one once `screen` is clear, the app is in the
    /// foreground and no other scene plays it. Animations turned off before it played drop it: the decorations go at once.
    func start(for scene: UUID, screen: SeasonalThemeModel.ScreenState, animationsAllowed: Bool) -> Packing? {
        guard let current else { return nil }
        if let playing = current.scene { return playing == scene ? current : nil }
        guard animationsAllowed else {
            self.current = nil
            return nil
        }
        guard isForeground, screen.allowsAlert else { return nil }
        self.current?.scene = scene
        return self.current
    }

    /// `scene`'s screen changed: the elves stop as soon as the keyboard, a sheet, an alert or the lock comes up (rule 5).
    func screenChanged(for scene: UUID, screen: SeasonalThemeModel.ScreenState) {
        if current?.scene == scene, !screen.allowsAlert { current = nil }
    }

    /// The elves are done, or were tapped away (THEMES.md §4 rule 3): the user's theme shows.
    func finish() {
        current = nil
    }

    /// `scene` went away while its elves played: the packing ends with it.
    func release(scene: UUID) {
        if current?.scene == scene { current = nil }
    }
}
