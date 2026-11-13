import SwiftUI

// Port of Classes/HFRNavigationController.m (userThemeDidChange, refreshTheme: the animated "snow" image behind the navigation
// bar, `:85-90, 134-139`) and Classes/HFRplusAppDelegate.m (setTheme `:382-388`) @ 87fe0d1c. Differences (GAP-147): procedural
// snow falling over the content, not frames in the bar.
extension View {
    /// The seasonal layer of the app root (LOT-166): the active theme's decorations over the content, and the arrival alert
    /// once nothing stands in its way (`isCovered`: the app lock; sheets and the keyboard are checked here, THEMES.md §4 rule 5).
    func seasonalDecorations(_ model: SeasonalThemeModel, isCovered: @escaping @MainActor () -> Bool) -> some View {
        modifier(SeasonalDecorationsModifier(model: model, isCovered: isCovered))
            .modifier(SeasonalArrivalAlert(model: model, isCovered: isCovered))
    }
}

private struct SeasonalDecorationsModifier: ViewModifier {
    let model: SeasonalThemeModel
    let isCovered: @MainActor () -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if model.activeTheme == .noelSoft {
                    NoelSnowLayer(falls: model.snowFalls && !reduceMotion)
                    NoelBottomDrifts()
                }
            }
            // The sleigh crosses on any theme (25–26/12, automatic themes off); the small objects in Noël soft only.
            .overlay { NoelBand { NoelCrossingLayer(seasonal: model, isCovered: isCovered) } }
    }
}

/// The band between the bars where decorations move: clear of the navigation bar with a large title, of the tab bar or toolbar,
/// of the status bar and of the home indicator (THEMES.md §4 rule 9).
struct NoelBand<Content: View>: View {
    /// Height kept clear at the top for the navigation bar and its large title (about 96 pt), and at the bottom for the tab bar.
    static var topBand: CGFloat { 104 }
    static var bottomBand: CGFloat { 64 }
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.topBand)
            content
            Color.clear.frame(height: Self.bottomBand)
        }
    }
}

/// Light falling snow, in the band between the bars (`NoelBand`), so that no button, badge, status bar or home
/// indicator is covered (THEMES.md §4 rule 9); never touched, never read by VoiceOver.
struct NoelSnowLayer: View {
    /// Flakes fall; without it (Reduce Motion, « Animations de saison » off) none is drawn. Piled snow is static and drawn apart
    /// (`NoelSnowPile.swift`), off the rows' text.
    let falls: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private let scroll = SeasonalScrollActivity.shared

    /// Flakes stop while the scene is not active, in Low Power Mode and while a list or the reader scrolls (THEMES.md §4 rule 8).
    static func isPaused(active: Bool, lowPower: Bool, scrolling: Bool) -> Bool { !active || lowPower || scrolling }

    var body: some View {
        NoelBand {
            if falls {
                let paused = Self.isPaused(active: scenePhase == .active, lowPower: lowPower, scrolling: scroll.isScrolling)
                Snowfall(color: flakeColor, paused: paused)
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    /// A blue-grey in light, so flakes show on white; white in dark (≥ 3:1 on the dark surfaces, THEMES.md §4 rule 7).
    private var flakeColor: Color {
        scheme == .dark ? .white : Color(red: 0.55, green: 0.66, blue: 0.80)
    }
}

/// The falling flakes, redrawn at 30 frames per second at most and not at all while `paused` (inactive, Low Power Mode,
/// scrolling).
private struct Snowfall: View {
    let color: Color
    let paused: Bool
    private let field = SnowField.light

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for (flake, point) in zip(field.flakes, field.positions(at: time, in: size)) {
                    let side = flake.radius * 2
                    let rect = CGRect(x: point.x - flake.radius, y: point.y - flake.radius, width: side, height: side)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(flake.opacity)))
                }
            }
        }
    }
}
