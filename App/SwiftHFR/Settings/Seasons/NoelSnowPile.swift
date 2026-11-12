import SwiftUI

/// Where Noël soft piles its snow (THEMES.md §2, §4 rules 7 and 9): small caps sitting on the top edge of the first card, in the
/// gap above it, and drifts in the bottom corners of the window, either side of the home indicator. Neither reaches a line of
/// text: a cap enters the card by less than a row's top padding, a drift stays inside the bottom safe area.
enum SnowPileLayout {
    /// A cap's height and how far it enters the card's top padding (a row's text starts at least 8 pt below the edge).
    static let capHeight: CGFloat = 11
    static let capOverlap: CGFloat = 3
    /// The smallest top padding of a list row before its text.
    static let rowTextPadding: CGFloat = 8
    /// The caps along the card, in fractions of its width (the board `theme-noel`: two, left and right).
    static let capSpans: [ClosedRange<Double>] = [0.05...0.30, 0.62...0.85]

    /// Each cap's frame, relative to the card's top-leading corner (negative y: above the card).
    static func capFrames(cardWidth: CGFloat) -> [CGRect] {
        guard cardWidth > 0 else { return [] }
        return capSpans.map { span in
            CGRect(
                x: cardWidth * span.lowerBound, y: capOverlap - capHeight,
                width: cardWidth * (span.upperBound - span.lowerBound), height: capHeight
            )
        }
    }

    /// The home indicator's width, centred, kept clear of drifts (THEMES.md §4 rule 9).
    static let homeIndicatorClearance: CGFloat = 160

    /// The bottom drifts in a window `width` wide whose bottom safe area is `bottomInset` high: nothing without a home indicator
    /// (no inset), else two drifts at most 16 pt high in the safe area, each corner up to the indicator's clearance.
    static func bottomFrames(width: CGFloat, height: CGFloat, bottomInset: CGFloat) -> [CGRect] {
        guard bottomInset > 0, width > homeIndicatorClearance else { return [] }
        let drift = min(16, bottomInset / 2)
        let side = min((width - homeIndicatorClearance) / 2, 220)
        let top = height - drift
        return [
            CGRect(x: 0, y: top, width: side, height: drift),
            CGRect(x: width - side, y: top, width: side, height: drift)
        ]
    }
}

/// The rows of a list's first card, with snow caps on its top edge while Noël soft is on (LOT-166): the caps are the section's
/// header, since a list cell clips what leaves it. Without Noël soft the rows are given as they are, with no section.
struct SeasonalSnowCapSection<Rows: View>: View {
    /// Optional: previews and test hosts run without the app's seasonal model.
    @Environment(SeasonalThemeModel.self) private var seasonal: SeasonalThemeModel?
    @ViewBuilder let rows: Rows

    var body: some View {
        if seasonal?.activeTheme == .noelSoft {
            Section {
                rows
            } header: {
                SnowCaps()
            }
        } else {
            rows
        }
    }
}

/// The caps along the card's width, sitting on its top edge.
private struct SnowCaps: View {
    /// The header's own gap above the card, which the caps reach down across.
    private let headerGap: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(SnowPileLayout.capFrames(cardWidth: proxy.size.width).enumerated()), id: \.offset) { _, frame in
                SnowPileImage()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: proxy.size.height + headerGap + frame.midY)
            }
        }
        .frame(height: SnowPileLayout.capHeight)
        .listRowInsets(EdgeInsets())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The drifts in the bottom corners of the window, static (they stay with Reduce Motion, THEMES.md §4 rule 1).
struct NoelBottomDrifts: View {
    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width, height: proxy.size.height + proxy.safeAreaInsets.bottom)
            ForEach(
                Array(SnowPileLayout.bottomFrames(width: size.width, height: size.height, bottomInset: proxy.safeAreaInsets.bottom)
                    .enumerated()),
                id: \.offset
            ) { _, frame in
                SnowPileImage().frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The operator's snow-pile render, stretched to its frame.
private struct SnowPileImage: View {
    var body: some View {
        Image("NoelSnowPile").resizable()
    }
}
