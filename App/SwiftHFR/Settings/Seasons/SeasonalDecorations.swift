import SwiftUI

// Port of Classes/HFRNavigationController.m (userThemeDidChange, refreshTheme: the animated "snow" image behind the navigation
// bar, `:85-90, 134-139`) and Classes/HFRplusAppDelegate.m (setTheme `:382-388`) @ 87fe0d1c. Differences (GAP-147): procedural
// snow falling over the content, not frames in the bar.
extension View {
    /// The seasonal layer of the app root (LOT-166): the active theme's decorations over the content, and the arrival alert
    /// once nothing stands in its way (`isCovered`: the app lock; sheets and the keyboard are checked here, THEMES.md §4 rule 5).
    func seasonalDecorations(_ model: SeasonalThemeModel, isCovered: @escaping @MainActor () -> Bool) -> some View {
        modifier(SeasonalDecorationsModifier(model: model))
            .modifier(SeasonalArrivalAlert(model: model, isCovered: isCovered))
    }
}

private struct SeasonalDecorationsModifier: ViewModifier {
    let model: SeasonalThemeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if model.activeTheme == .noelSoft {
                    NoelSnowLayer(falls: model.snowFalls && !reduceMotion)
                }
            }
    }
}

/// Light falling snow, between the navigation bar and the bottom bar so that no button, badge, status bar or home
/// indicator is covered (THEMES.md §4 rule 9); never touched, never read by VoiceOver.
struct NoelSnowLayer: View {
    /// Flakes fall; without it (Reduce Motion, « Animations de saison » off) nothing is drawn. Piled snow comes with PR 2: a
    /// drift drawn over the content crossed row text (screenshot of PR 1).
    let falls: Bool
    /// Height kept clear at the top for the navigation bar, and at the bottom for the tab bar or toolbar.
    static let topBand: CGFloat = 56
    static let bottomBand: CGFloat = 64

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.topBand)
            if falls {
                Snowfall(color: flakeColor, paused: scenePhase != .active || lowPower)
            } else {
                Color.clear
            }
            Color.clear.frame(height: Self.bottomBand)
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

/// The falling flakes, redrawn at 30 frames per second at most and not at all while `paused` (inactive, Low Power Mode).
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
