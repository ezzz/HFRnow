import CoreGraphics
import SwiftUI

// No legacy counterpart @ 87fe0d1c (legacy had no packing animation; GAP row of LOT-191).
/// Where the packing witch stands in the band between the bars (THEMES.md §5, Samain packing): she crosses it once, from the
/// leading edge to the trailing one, sweeping with her broom, at the foot of the band. Pure, so the limits are tested.
nonisolated enum SamainSweepLayout {
    /// Width over height of the operator's `samain_witch_sweep` render trimmed to its alpha > 8 box, 775 × 627.
    static let aspectRatio: Double = 775.0 / 627
    /// The tallest witch, in points.
    static let maxHeight: CGFloat = 220
    /// Her small bob while she sweeps, as a share of her height, and how many she makes in the run.
    static let bobShare = 0.03
    static let bobs = 6

    /// Her height: a quarter of the window, at most `maxHeight`, never taller than the band.
    static func height(window: CGFloat, band: CGFloat) -> CGFloat {
        min(max(window, 0) / 4, maxHeight, max(band, 0))
    }

    /// Her frame in a band of `area` at `progress` (0…1 of the run, clamped): she enters fully outside the leading edge and
    /// leaves fully outside the trailing one. Nil in a band too small to hold her.
    static func frame(in area: CGSize, windowHeight: CGFloat, progress: Double) -> CGRect? {
        let height = height(window: windowHeight, band: area.height)
        let width = height * aspectRatio
        guard height > 0, width > 0, area.width > 0 else { return nil }
        let progress = min(max(progress.isFinite ? progress : 0, 0), 1)
        let bob = height * bobShare * abs(sin(progress * .pi * Double(bobs)))
        let x = -width + (area.width + width) * progress
        return CGRect(x: x, y: area.height - height - bob, width: width, height: height)
    }
}

/// What plays a packing: Noël's elves, or Samain's witch (THEMES.md §5). Pure, so « Samain shows Noël's elves » is tested.
nonisolated enum PackingOverlay: Equatable {
    case elves
    case witch

    init(theme: SeasonalTheme?) {
        self = theme?.family == .samain ? .witch : .elves
    }
}

/// The witch of the packing crossing the band with « Allez on remballe » above her; redrawn every frame only while she plays (one
/// view per packing). A tap anywhere in the band ends her (THEMES.md §4 rule 3); hidden from VoiceOver, which hears the words as
/// an announcement.
struct WitchSweep: View {
    let area: CGSize
    let windowHeight: CGFloat
    let close: () -> Void
    @State private var begin = Date()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                let progress = timeline.date.timeIntervalSince(begin) / NoelPackingModel.duration
                ZStack {
                    if let frame = SamainSweepLayout.frame(in: area, windowHeight: windowHeight, progress: progress) {
                        Image("SamainWitchSweep")
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .samainRim(scheme)
                            .position(x: frame.midX, y: frame.midY)
                    }
                    Text("Allez on remballe")
                        .font(.headline)
                        .padding()
                        .background(.regularMaterial, in: .capsule)
                        .opacity(NoelPackingLayout.rise(at: progress))
                }
                .frame(width: area.width, height: area.height)
            }
            Button(action: close) {
                Color.clear.contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(width: area.width, height: area.height)
        .clipped()
        .accessibilityHidden(true)
    }
}
