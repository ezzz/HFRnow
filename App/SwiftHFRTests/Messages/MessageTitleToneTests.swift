@testable import SwiftHFR
import HFRModels
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
        let read = try #require(Self.centre(of: Self.swatch(.secondary, dark: dark, background: background)))
        let unread = try #require(Self.centre(of: Self.swatch(.primary, dark: dark, background: background)))
        #expect(Self.distance(read, Self.painted(ReadTitleStyle.color(for: theme.traits), on: background, theme)) < 0.02)
        #expect(Self.distance(unread, Self.painted(.label, on: background, theme)) < 0.02)
    }

    @Test("On the iPad's accent selection a read title is drawn like an unread one, never in a fainter secondary", arguments: [false, true])
    func prominentBackgroundUsesThePrimaryStyle(dark: Bool) throws {
        let accent = Monogram.RGB(red: 0.22, green: 0.5, blue: 0.93)
        let read = try #require(Self.centre(of: Self.swatch(.secondary, dark: dark, background: accent, prominence: .increased)))
        let unread = try #require(Self.centre(of: Self.swatch(.primary, dark: dark, background: accent, prominence: .increased)))
        #expect(Self.distance(read, unread) < 0.02)
    }

    @Test("A conversation row draws its title in the read colour once read, in the primary colour while unread", arguments: [false, true])
    func rowDrawsTheTitleTone(dark: Bool) throws {
        let theme = Theme(dark: dark, increasedContrast: false)
        let background = Self.rgba(.secondarySystemGroupedBackground, theme).rgb
        let read = try #require(Self.rowTitlePixel(isUnread: false, dark: dark, background: background))
        let unread = try #require(Self.rowTitlePixel(isUnread: true, dark: dark, background: background))
        #expect(Self.distance(read, Self.painted(ReadTitleStyle.color(for: theme.traits), on: background, theme)) < 0.02)
        #expect(Self.distance(unread, Self.painted(.label, on: background, theme)) < 0.02)
    }

    // MARK: - Helpers

    /// A square filled with `tone.style` over `background`.
    private static func swatch(
        _ tone: MessageTitleTone, dark: Bool, background: Monogram.RGB, prominence: BackgroundProminence = .standard
    ) -> some View {
        Rectangle().fill(tone.style).frame(width: 40, height: 40)
            .environment(\.backgroundProminence, prominence)
            .padding()
            .background(Color(red: background.red, green: background.green, blue: background.blue))
            .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// The colour a `MessageRowView` paints inside its title, a run of full blocks: the first pixel off the background
    /// from the top of a column right of the avatar, then a few points lower, inside the glyph.
    private static func rowTitlePixel(isUnread: Bool, dark: Bool, background: Monogram.RGB) -> Monogram.RGB? {
        let summary = TopicSummary(
            topicID: TopicID(category: .privateMessages, topic: 3_207_033),
            title: String(repeating: "\u{2588}", count: 30),
            path: "/forum2.php?config=hfr.inc&cat=prive&post=3207033",
            readState: isUnread ? .unread : .read
        )
        let row = MessageRowView(thread: PrivateMessageThread(summary: summary, unreadBy: [], isUnreadByOthers: false), isUnread: isUnread)
            .frame(width: 400)
            .background(Color(red: background.red, green: background.green, blue: background.blue))
            .environment(\.colorScheme, dark ? .dark : .light)
        guard let image = render(row) else { return nil }
        let column = 150
        for line in 0..<image.height {
            guard let pixel = pixel(of: image, x: column, y: line), distance(pixel, background) > 0.1 else { continue }
            return Self.pixel(of: image, x: column, y: min(line + 4, image.height - 1))
        }
        return nil
    }

    private static func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    private static func centre(of view: some View) -> Monogram.RGB? {
        guard let image = render(view) else { return nil }
        return pixel(of: image, x: image.width / 2, y: image.height / 2)
    }

    /// The sRGB colour of the pixel at (`x`, `y`) from the top left.
    private static func pixel(of image: CGImage, x: Int, y: Int) -> Monogram.RGB? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // The 1×1 context shows the image pixel at (x, y); Core Graphics counts rows from the bottom.
            context.draw(image, in: CGRect(x: -x, y: y + 1 - image.height, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        return Monogram.RGB(red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255)
    }

    private static func distance(_ first: Monogram.RGB, _ second: Monogram.RGB) -> Double {
        max(abs(first.red - second.red), abs(first.green - second.green), abs(first.blue - second.blue))
    }

    /// What the text colour `text` paints over the opaque `background`.
    private static func painted(_ text: UIColor, on background: Monogram.RGB, _ theme: Theme) -> Monogram.RGB {
        let resolved = rgba(text, theme)
        return over(background, resolved.rgb, alpha: resolved.alpha)
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
