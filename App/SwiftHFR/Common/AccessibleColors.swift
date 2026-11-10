import SwiftUI
import UIKit

/// Text and badge colours held at WCAG 4.5:1 on the backgrounds they sit on, in light and dark (LOT-162, #646).
///
/// The system accent, red and orange measure 1.5 to 3.6:1 as text on the list cards, so a capsule or a message in those colours
/// uses these fixed values instead. They are plain RGB so the ratios are computed and tested, not eyeballed.
enum AccessibleColors {
    /// An sRGB colour, 0 to 255 per channel.
    struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int

        static let white = RGB(red: 255, green: 255, blue: 255)
        static let black = RGB(red: 0, green: 0, blue: 0)

        /// WCAG 2.x relative luminance.
        var luminance: Double {
            func linear(_ value: Int) -> Double {
                let channel = Double(value) / 255
                return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    /// WCAG contrast ratio of two colours, 1 to 21.
    static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let (lighter, darker) = (max(first.luminance, second.luminance), min(first.luminance, second.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    enum Role: CaseIterable {
        /// A count capsule's fill; its text is `badgeText`.
        case badgeFill
        case badgeText
        /// A failure message, session-expired state or destructive entry written as text.
        case errorText
        /// A warning written as text.
        case warningText
    }

    /// The colour of `role` in light or dark.
    static func rgb(_ role: Role, dark: Bool) -> RGB {
        switch (role, dark) {
        case (.badgeFill, false): RGB(red: 90, green: 90, blue: 96)
        case (.badgeFill, true): RGB(red: 209, green: 209, blue: 214)
        case (.badgeText, false): .white
        case (.badgeText, true): .black
        case (.errorText, false): RGB(red: 176, green: 0, blue: 32)
        case (.errorText, true): RGB(red: 255, green: 130, blue: 122)
        case (.warningText, false): RGB(red: 150, green: 70, blue: 0)
        case (.warningText, true): RGB(red: 255, green: 179, blue: 64)
        }
    }

    /// `rgb(_:dark:)` as a dynamic colour.
    static func color(_ role: Role) -> Color {
        Color(uiColor: UIColor { traits in
            let value = rgb(role, dark: traits.userInterfaceStyle == .dark)
            return UIColor(red: Double(value.red) / 255, green: Double(value.green) / 255, blue: Double(value.blue) / 255, alpha: 1)
        })
    }

    static var errorText: Color { color(.errorText) }
}

/// A count capsule ("3", "non lu") that reads at 4.5:1: filled, or outlined for the quieter state (#646).
struct BadgeCapsule: View {
    let text: String
    var isBold = false
    /// The quieter state: the fill colour as text and outline on the row's own background.
    var isOutlined = false

    var body: some View {
        Text(text)
            .scaledFont(.caption2)
            .fontWeight(isBold ? .bold : .regular)
            .foregroundStyle(isOutlined ? AccessibleColors.color(.badgeFill) : AccessibleColors.color(.badgeText))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background { if !isOutlined { Capsule().fill(AccessibleColors.color(.badgeFill)) } }
            .overlay { if isOutlined { Capsule().strokeBorder(AccessibleColors.color(.badgeFill), lineWidth: 1) } }
    }
}

/// A label whose icon carries the colour and whose text stays in the primary colour, so a coloured message keeps its contrast.
struct StatusLabel: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
    }
}
