import CoreGraphics
import Foundation

/// The choreography of the 14 July overlay (THEMES.md §5): a bust rising in the middle of the band, fireworks bursting around it
/// one after the other. Pure functions of `progress` (0…1 of the run), so the limits are tested.
nonisolated enum FeteNationaleLayout {
    /// One firework burst: where it opens (fractions of the band), when it starts (fraction of the run), its size (fraction of the
    /// band's width) and which render it uses.
    struct Burst: Equatable {
        let centre: CGPoint
        let start: Double
        let size: Double
        let variant: Variant
    }

    /// The three firework renders (`FeteFireworks`, `FeteFireworksRed`, `FeteFireworksGold`).
    enum Variant: String, CaseIterable {
        case tricolour = "FeteFireworks"
        case red = "FeteFireworksRed"
        case gold = "FeteFireworksGold"
    }

    /// The bursts, around the bust (which stands in the middle): at most five, staggered across the run.
    static let bursts: [Burst] = [
        Burst(centre: CGPoint(x: 0.25, y: 0.30), start: 0.10, size: 0.50, variant: .tricolour),
        Burst(centre: CGPoint(x: 0.78, y: 0.22), start: 0.22, size: 0.46, variant: .red),
        Burst(centre: CGPoint(x: 0.80, y: 0.62), start: 0.38, size: 0.50, variant: .gold),
        Burst(centre: CGPoint(x: 0.20, y: 0.68), start: 0.50, size: 0.46, variant: .tricolour),
        Burst(centre: CGPoint(x: 0.50, y: 0.15), start: 0.62, size: 0.52, variant: .red)
    ]
    /// How long a burst lasts, as a share of the run.
    static let burstSpan = 0.32
    /// The share of the run spent fading in, and again fading out.
    static let fadeShare = 0.15
    /// The overlay's words, also announced to VoiceOver.
    static let text = "Fête nationale"
    /// The tallest bust, in points.
    static let maxBustHeight: CGFloat = 300

    /// How present the bust, the text and the dimmed backdrop are at `progress`: 0 hidden, 1 fully there.
    static func presence(at progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)
        return min(min(progress / fadeShare, 1), min((1 - progress) / fadeShare, 1))
    }

    /// The bust's height: 40 % of the band, at most `maxBustHeight`.
    static func bustHeight(band: CGFloat) -> CGFloat {
        min(max(band, 0) * 0.4, maxBustHeight)
    }

    /// A burst's scale and opacity at `progress`, nil before it starts and after it is gone: it opens fast, then fades.
    static func state(of burst: Burst, at progress: Double) -> BurstState? {
        let local = (progress - burst.start) / burstSpan
        guard local >= 0, local <= 1 else { return nil }
        let open = 1 - (1 - local) * (1 - local)
        return BurstState(scale: 0.3 + 0.7 * open, opacity: local < 0.55 ? 1 : (1 - local) / 0.45)
    }

    /// How a burst looks at one moment.
    struct BurstState: Equatable {
        let scale: Double
        let opacity: Double
    }
}
