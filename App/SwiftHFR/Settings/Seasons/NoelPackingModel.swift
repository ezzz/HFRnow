import Foundation
import Observation

/// The elves of the packing (THEMES.md §5), one for the app: on the first launch 27/12–02/01 with a Noël theme on and animations
/// allowed, the scheduler has already restored the user's theme in the store (a kill meanwhile loses nothing); this keeps the
/// seasonal theme drawn until the elves have taken it down, at most `duration` (THEMES.md §4 rule 3), in one active scene, on a
/// clear screen (rule 5). Without animations nothing is queued and the user's theme shows at once.
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
        /// « Allez on remballe » was announced to VoiceOver, by whichever scene played it.
        var announced = false
    }

    /// How long the elves play: within the 5 s of an overlay (THEMES.md §4 rule 3).
    static let duration: TimeInterval = 4.5
    /// Elves cut this soon after they started (an alert of the same launch, a window resized away) wait and play again, at
    /// most `maxReplays` times; cut later, they are done and the decorations go.
    static let replayWindow: TimeInterval = 1
    static let maxReplays = 2

    /// The packing waiting or playing; nil once done.
    private(set) var current: Packing?
    /// The elves are on screen: the decorations fade while they play.
    var isPlaying: Bool { current?.scene != nil }

    @ObservationIgnored private let now: @MainActor () -> Date
    /// The scenes active now: only one of them plays the elves (iPad: another window's phase never ends them).
    @ObservationIgnored private var activeScenes: Set<UUID> = []
    /// When the elves started on screen.
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var replays = 0

    /// A packing model on the clock `now` (the tests move it by hand).
    init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    /// The scheduler packed `theme` of season `year` with animations allowed: it stays drawn until the elves have played.
    func queue(year: Int, theme: SeasonalTheme) {
        current = Packing(year: year, theme: theme)
        replays = 0
    }

    /// `scene` became active (`true`) or left. Elves playing there stop when it leaves (replayed if they had only just begun).
    func sceneChanged(_ scene: UUID, active: Bool) {
        if active {
            activeScenes.insert(scene)
        } else {
            activeScenes.remove(scene)
            cut(in: scene)
        }
    }

    /// The packing `scene` may play now: the one it already plays, or the waiting one once `scene` is active, `screen` is clear
    /// and no other scene plays it. Animations turned off before it played drop it: the decorations go at once.
    func start(for scene: UUID, screen: SeasonalThemeModel.ScreenState, animationsAllowed: Bool) -> Packing? {
        guard let current else { return nil }
        if let playing = current.scene { return playing == scene ? current : nil }
        guard animationsAllowed else {
            self.current = nil
            return nil
        }
        guard activeScenes.contains(scene), screen.allowsAlert else { return nil }
        self.current?.scene = scene
        startedAt = now()
        return self.current
    }

    /// `scene`'s screen changed: the elves stop as soon as the keyboard, a sheet, an alert or the lock comes up (rule 5).
    func screenChanged(for scene: UUID, screen: SeasonalThemeModel.ScreenState) {
        if !screen.allowsAlert { cut(in: scene) }
    }

    /// The packing's words are to be announced now: true once per packing, whichever scene plays it and however many times
    /// it is replayed (rule 6: the overlay is hidden, its sentence is spoken once).
    func shouldAnnounce() -> Bool {
        guard let current, !current.announced else { return false }
        self.current?.announced = true
        return true
    }

    /// The elves are done, or were tapped away (THEMES.md §4 rule 3): the user's theme shows.
    func finish() {
        current = nil
    }

    /// `scene` went away while its elves played: they stop, as when it leaves.
    func release(scene: UUID) {
        sceneChanged(scene, active: false)
    }

    /// Elves playing in `scene` stop before their end: in their first `replayWindow` they wait to play again (the decorations
    /// stay), at most `maxReplays` times; after that the packing is over.
    private func cut(in scene: UUID) {
        guard current?.scene == scene else { return }
        if let startedAt, now().timeIntervalSince(startedAt) < Self.replayWindow, replays < Self.maxReplays {
            replays += 1
            current?.scene = nil
        } else {
            current = nil
        }
    }
}
