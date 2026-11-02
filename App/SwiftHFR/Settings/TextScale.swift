import SwiftUI
import UIKit

// Port of HFRswift/Swift/Common.swift (AppTextSizeScale.scaledUIFont, :265-293) @ 21173e77. Differences: a 70–130 % percentage
// (step 5) instead of four steps from 100 %, so the text can go below the default; one environment value read by every screen
// instead of an @AppStorage read per view (LOT-169).
/// The app-wide type scale: a system text style at the current Dynamic Type size, times the in-app percentage.
///
/// The percentage multiplies the system size, so accessibility sizes still grow the text at every slider value.
struct TextScale: Equatable, Sendable {
    /// 100 %: the system sizes unchanged.
    static let standard = TextScale(percent: 100)

    /// The in-app percentage (`text_size_percent`, 70–130).
    let percent: Int

    /// The multiplier applied to every system size.
    var factor: CGFloat { CGFloat(percent) / 100 }

    /// Point size of `style` at Dynamic Type size `size`, times the percentage.
    func pointSize(_ style: Font.TextStyle, at size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        return UIFont.preferredFont(forTextStyle: style.uiTextStyle, compatibleWith: traits).pointSize * factor
    }

    /// `value` (an icon or spacing size, already scaled by Dynamic Type through `@ScaledMetric`) times the percentage.
    func scaled(_ value: CGFloat) -> CGFloat { value * factor }

    /// The font of `style` at Dynamic Type size `size`, times the percentage. A headline keeps its semibold weight.
    func font(_ style: Font.TextStyle, at size: DynamicTypeSize) -> Font {
        .system(size: pointSize(style, at: size), weight: style == .headline ? .semibold : .regular)
    }
}

extension Font.TextStyle {
    /// The UIKit text style of the same name.
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

extension EnvironmentValues {
    /// The app-wide type scale; the app root sets it from the "Taille du texte" setting.
    @Entry var textScale = TextScale.standard
}

/// Sets the font of `style` from the environment's type scale and Dynamic Type size.
private struct ScaledFont: ViewModifier {
    let style: Font.TextStyle
    @Environment(\.textScale) private var scale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(scale.font(style, at: dynamicTypeSize))
    }
}

extension View {
    /// The font of `style` on the app-wide type scale (LOT-169): use it instead of `.font(.body)` and fixed point sizes.
    func scaledFont(_ style: Font.TextStyle) -> some View {
        modifier(ScaledFont(style: style))
    }
}
