import SwiftUI

// Port of Classes/HFRNavigationController.m (userThemeDidChange, refreshTheme: the animated "snow" image behind the navigation
// bar, `:85-90, 134-139`) and Classes/HFRplusAppDelegate.m (setTheme `:382-388`; the alert `:645-676`) @ 87fe0d1c.
// Differences (GAP-147): procedural snow falling over the content, not frames in the bar; a snow drift; the operator's alert
// text and its « Désactiver » instead of legacy's one-button « C'est bientôt Noël ! ».
extension View {
    /// The seasonal layer of the app root (LOT-166): the active theme's decorations over the content, and the arrival alert
    /// once `alertAllowed` (nothing covers the screen, THEMES.md §4 rule 5).
    func seasonalDecorations(_ model: SeasonalThemeModel, alertAllowed: Bool) -> some View {
        modifier(SeasonalDecorationsModifier(model: model, alertAllowed: alertAllowed))
    }
}

private struct SeasonalDecorationsModifier: ViewModifier {
    let model: SeasonalThemeModel
    let alertAllowed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if model.activeTheme == .noelSoft {
                    NoelSnowLayer(falls: model.snowFalls && !reduceMotion)
                }
            }
            // A normal alert, spoken by VoiceOver (THEMES.md §4 rule 6). The setter ignores the dismissal: each button
            // answers, so the alert stays pending until the user does.
            .alert(
                "Oh Oh Oh !",
                isPresented: Binding(get: { alertAllowed && model.pendingAlert != nil }, set: { _ in }),
                presenting: model.pendingAlert
            ) { _ in
                Button("OK") { model.answerArrival(disable: false) }
                Button("Désactiver") { model.answerArrival(disable: true) }
            } message: { _ in
                Text("Thème disponible dans les réglages")
            }
    }
}

/// Light falling snow and a drift, between the navigation bar and the bottom bar so that no button, badge, status bar or home
/// indicator is covered (THEMES.md §4 rule 9); never touched, never read by VoiceOver.
struct NoelSnowLayer: View {
    /// Flakes fall; without it (Reduce Motion, « Animations de saison » off) only the drift stays.
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
            ZStack(alignment: .bottom) {
                if falls {
                    Snowfall(color: flakeColor, paused: scenePhase != .active || lowPower)
                }
                SnowDrift()
                    .fill(driftColor)
                    .overlay(SnowDrift().stroke(flakeColor.opacity(0.6), lineWidth: 1))
                    .frame(height: 10)
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

    private var driftColor: Color {
        scheme == .dark ? Color.white.opacity(0.85) : Color.white.opacity(0.95)
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

/// A low wavy heap of snow along the bottom of its frame.
struct SnowDrift: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        let bumps = max(Int(rect.width / 60), 1)
        let step = rect.width / CGFloat(bumps)
        for index in 0..<bumps {
            let start = rect.minX + CGFloat(index) * step
            let crest = index.isMultiple(of: 2) ? rect.minY : rect.minY + rect.height * 0.3
            path.addQuadCurve(to: CGPoint(x: start + step, y: rect.midY), control: CGPoint(x: start + step / 2, y: crest))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
