import SwiftUI

// Port of none @ 87fe0d1c: legacy was the app this update replaces and never imported its data (GAP-170, new UX: #754).
/// What the root screen shows while the first-launch import runs (LOT-158): a small original construction worker, so the wait
/// feels intended. The art is made by `tooling/art/import-worker/make.py` (three SVG layers, light and dark, in the asset
/// catalogue); SwiftUI turns one layer (the hammer arm) and fades another (the spark), no frame sequence.
///
/// Reduce Motion shows the still drawing and a standard progress indicator instead of the loop (the operator chose the
/// animated worker, #754). The text carries counts only, never an account's data.
struct LegacyImportProgressView: View {
    /// What is on screen once Reduce Motion is read.
    enum Display: Sendable, Equatable {
        case animated
        case staticWithIndicator
    }

    /// Where the hammer arm is and how visible the spark is at one instant of the loop.
    struct Pose: Sendable, Equatable {
        /// Degrees clockwise from the raised pose, around the shoulder.
        var angle: Double
        /// 0 (hidden) to 1 (full).
        var spark: Double
    }

    static let title = "Import de vos données HFR+…"
    /// Matches `IMPACT_ANGLE` and `SHOULDER` in `make.py`.
    static let impactAngle = 58.0
    static let shoulder = UnitPoint(x: 72.0 / 128.0, y: 62.0 / 128.0)
    /// The still pose: the hammer half way down, readable at a glance.
    static let restAngle = 29.0
    static let period = 1.4

    /// Forces Reduce Motion on or off for previews; nil follows the system setting (the environment value is get-only).
    let reduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// The drawing grows with the text size.
    @ScaledMetric(relativeTo: .body) private var drawingSize = 128.0

    init(reduceMotionOverride: Bool? = nil) {
        self.reduceMotionOverride = reduceMotionOverride
    }

    /// What is shown: the loop, or the still drawing with a progress indicator under Reduce Motion.
    static func display(reduceMotion: Bool) -> Display {
        reduceMotion ? .staticWithIndicator : .animated
    }

    /// The loop: raised and still, a quick strike, a hold on the nail with a spark, a slow return. `seconds` is any clock.
    static func pose(at seconds: TimeInterval) -> Pose {
        let phase = seconds.truncatingRemainder(dividingBy: period) / period
        switch phase {
        case ..<0.45:
            return Pose(angle: 0, spark: 0)
        case ..<0.58:
            let progress = (phase - 0.45) / 0.13
            return Pose(angle: impactAngle * progress * progress, spark: 0)
        case ..<0.72:
            return Pose(angle: impactAngle, spark: 1 - (phase - 0.58) / 0.14)
        default:
            let progress = (phase - 0.72) / 0.28
            let eased = progress * progress * (3 - 2 * progress)
            return Pose(angle: impactAngle * (1 - eased), spark: 0)
        }
    }

    var body: some View {
        let display = Self.display(reduceMotion: reduceMotionOverride ?? systemReduceMotion)
        VStack(spacing: 16) {
            drawing(display)
                // Capped: at accessibility sizes the text matters more than the picture.
                .frame(width: min(drawingSize, 200), height: min(drawingSize, 200))
                // The drawing says nothing the label does not.
                .accessibilityHidden(true)
            if display == .staticWithIndicator {
                ProgressView()
            }
            Text(Self.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.title)
        .accessibilityValue("En cours")
    }

    @ViewBuilder
    private func drawing(_ display: Display) -> some View {
        switch display {
        case .animated:
            TimelineView(.animation) { timeline in
                layers(Self.pose(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        case .staticWithIndicator:
            layers(Pose(angle: Self.restAngle, spark: 0))
        }
    }

    private func layers(_ pose: Pose) -> some View {
        ZStack {
            Image("ImportWorkerBody").resizable().scaledToFit()
            Image("ImportWorkerArm").resizable().scaledToFit()
                .rotationEffect(.degrees(pose.angle), anchor: Self.shoulder)
            Image("ImportWorkerSpark").resizable().scaledToFit()
                .opacity(pose.spark)
        }
    }
}

#Preview("Animé") {
    LegacyImportProgressView()
}

#Preview("Réduire les animations") {
    LegacyImportProgressView(reduceMotionOverride: true)
        .preferredColorScheme(.dark)
}
