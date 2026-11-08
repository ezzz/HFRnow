@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The title of a conversation row (#651): unread primary and semibold, read secondary and regular, each at 4.5:1 or more
/// on the list's backgrounds, measured on the system colours of every theme the MP list has.
@MainActor
struct MessageTitleToneTests {
    /// Light and dark, with and without Increase Contrast. LOT-122's darker dark and OLED black are not in the app yet, and
    /// the classic and modern styles are the reader's (`ThemeStyle`): neither reaches the MP list.
    struct Theme: CustomTestStringConvertible, Sendable {
        let dark: Bool
        let increasedContrast: Bool

        static let all = [false, true].flatMap { dark in [false, true].map { Theme(dark: dark, increasedContrast: $0) } }

        var traits: UITraitCollection {
            UITraitCollection {
                $0.userInterfaceStyle = dark ? .dark : .light
                $0.accessibilityContrast = increasedContrast ? .high : .normal
            }
        }

        /// `RowTint`'s strength in this theme.
        var tintStrength: Double {
            RowTint.strength(scheme: dark ? .dark : .light, contrast: increasedContrast ? .increased : .standard)
        }

        var testDescription: String { (dark ? "dark" : "light") + (increasedContrast ? ", Increase Contrast" : "") }
    }

    @Test("An unread title is primary and semibold, a read one secondary and regular")
    func toneFollowsTheMembersReadState() {
        #expect(MessageTitleTone.of(isUnread: true) == .primary)
        #expect(MessageTitleTone.of(isUnread: false) == .secondary)
        #expect(MessageTitleTone.primary.weight == .semibold)
        #expect(MessageTitleTone.secondary.weight == .regular)
    }

    @Test("A read title is never drawn in the primary colour", arguments: Theme.all)
    func readTitleIsNotPrimary(_ theme: Theme) {
        let card = Self.rgba(.secondarySystemGroupedBackground, theme).rgb
        let read = Self.contrast(ReadTitleStyle.color(for: theme.traits), on: card, theme)
        let primary = Self.contrast(.label, on: card, theme)
        #expect(read < primary * 0.75)
    }

    @Test("A read title keeps 4.5:1 on the card", arguments: Theme.all)
    func readTitleContrast(_ theme: Theme) {
        let card = Self.rgba(.secondarySystemGroupedBackground, theme).rgb
        #expect(Self.contrast(ReadTitleStyle.color(for: theme.traits), on: card, theme) >= 4.5)
    }

    @Test("An unread title keeps 4.5:1 on the tinted card whatever the accent, and on the untinted selected row", arguments: Theme.all)
    func unreadTitleContrast(_ theme: Theme) {
        let card = Self.rgba(.secondarySystemGroupedBackground, theme).rgb
        #expect(Self.contrast(.label, on: card, theme) >= 4.5)
        // Luminance grows with every channel, so a black or a white tint is the worst any accent can do to either text.
        for tint in [Monogram.RGB(red: 0, green: 0, blue: 0), Monogram.RGB(red: 1, green: 1, blue: 1)] {
            let tinted = Self.over(card, tint, alpha: theme.tintStrength)
            #expect(Self.contrast(.label, on: tinted, theme) >= 4.5)
        }
    }

    @Test("In dark the read title is the system's secondary label, legacy's `.secondary`")
    func darkIsTheSystemSecondary() {
        for theme in Theme.all where theme.dark {
            #expect(ReadTitleStyle.color(for: theme.traits) == UIColor.secondaryLabel.resolvedColor(with: theme.traits))
        }
    }

    @Test("In light the read title is the secondary label at its Increase Contrast strength, the standard one being under 4.5:1")
    func lightUsesTheIncreasedContrastSecondary() {
        let standard = Theme(dark: false, increasedContrast: false)
        let increased = Theme(dark: false, increasedContrast: true)
        let card = Self.rgba(.secondarySystemGroupedBackground, standard).rgb
        #expect(Self.contrast(.secondaryLabel, on: card, standard) < 4.5)
        let expected = UIColor.secondaryLabel.resolvedColor(with: increased.traits)
        #expect(ReadTitleStyle.color(for: standard.traits) == expected)
        #expect(ReadTitleStyle.color(for: increased.traits) == expected)
    }

    @Test("The style a row gives a read title paints the read colour, an unread one's the primary colour", arguments: [false, true])
    func drawnColour(dark: Bool) throws {
        let theme = Theme(dark: dark, increasedContrast: false)
        let background = Self.rgba(.secondarySystemGroupedBackground, theme).rgb
        let read = try #require(Self.drawnPixel(.secondary, dark: dark, background: background))
        let unread = try #require(Self.drawnPixel(.primary, dark: dark, background: background))
        let readTitle = Self.rgba(ReadTitleStyle.color(for: theme.traits), theme)
        let label = Self.rgba(.label, theme)
        #expect(Self.distance(read, Self.over(background, readTitle.rgb, alpha: readTitle.alpha)) < 0.02)
        #expect(Self.distance(unread, Self.over(background, label.rgb, alpha: label.alpha)) < 0.02)
    }

    // MARK: - Helpers

    /// The colour `tone.style` paints in the middle of a full block glyph over `background`, rendered off screen.
    private static func drawnPixel(_ tone: MessageTitleTone, dark: Bool, background: Monogram.RGB) -> Monogram.RGB? {
        let view = Text("\u{2588}\u{2588}").font(.largeTitle).foregroundStyle(tone.style)
            .padding()
            .background(Color(red: background.red, green: background.green, blue: background.blue))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // The 1×1 context shows the image pixel at its centre.
            context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        return Monogram.RGB(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    private static func distance(_ first: Monogram.RGB, _ second: Monogram.RGB) -> Double {
        max(abs(first.red - second.red), abs(first.green - second.green), abs(first.blue - second.blue))
    }

    private static func rgba(_ color: UIColor, _ theme: Theme) -> (rgb: Monogram.RGB, alpha: Double) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: theme.traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Monogram.RGB(red: red, green: green, blue: blue), alpha)
    }

    /// `top` at `alpha` over the opaque `base`.
    private static func over(_ base: Monogram.RGB, _ top: Monogram.RGB, alpha: Double) -> Monogram.RGB {
        func mix(_ under: Double, _ above: Double) -> Double { under * (1 - alpha) + above * alpha }
        return Monogram.RGB(red: mix(base.red, top.red), green: mix(base.green, top.green), blue: mix(base.blue, top.blue))
    }

    /// WCAG contrast of the text colour `text`, translucent or not, on the opaque `background`.
    private static func contrast(_ text: UIColor, on background: Monogram.RGB, _ theme: Theme) -> Double {
        let resolved = rgba(text, theme)
        return Monogram.contrast(over(background, resolved.rgb, alpha: resolved.alpha), background)
    }
}
