import Foundation

/// The placeholder of a member without a cached avatar: initials on a disc whose colour is a stable function of the pseudo.
///
/// Pure value, no SwiftUI: the colour rule and its contrast are tested without a view. The saturation and brightness are
/// fixed per colour scheme and only the hue follows the pseudo, so every hue keeps at least 4.5:1 between the initials and
/// the disc (checked over the whole hue circle in `MonogramTests`).
struct Monogram: Equatable, Sendable {
    /// An sRGB colour, components in 0...1.
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// One or two uppercased letters or digits; "?" for a pseudo that has none.
    let initials: String
    /// Hue in turns (0..<1), from a hash of the lower-cased pseudo.
    let hue: Double

    /// A monogram with the given parts (tests sweep the hue circle).
    init(initials: String, hue: Double) {
        self.initials = initials
        self.hue = hue
    }

    /// The monogram of `pseudo`; case and zero-width spaces do not change it, as the avatar cache key (LOT-066).
    init(pseudo: String) {
        let normalized = pseudo.filter { $0 != "\u{200B}" }
        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let letters = words.prefix(2).compactMap(\.first)
        initials = letters.isEmpty ? "?" : String(letters).uppercased()
        hue = Double(Self.hash(normalized.lowercased()) % 360) / 360
    }

    /// The disc colour. Light: pale, dark initials. Dark: deep, light initials.
    func background(dark: Bool) -> RGB {
        Self.rgb(hue: hue, saturation: dark ? 0.55 : 0.35, brightness: dark ? 0.35 : 0.92)
    }

    /// The initials' colour: black on the light disc, white on the dark one.
    static func foreground(dark: Bool) -> RGB {
        dark ? RGB(red: 1, green: 1, blue: 1) : RGB(red: 0, green: 0, blue: 0)
    }

    /// WCAG contrast ratio between two colours, 1...21.
    static func contrast(_ first: RGB, _ second: RGB) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Private

    /// FNV-1a over UTF-8: unlike `Hashable`, it is the same in every launch.
    private static func hash(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private static func luminance(_ color: RGB) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> RGB {
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        switch index {
        case 0: return RGB(red: brightness, green: rising, blue: low)
        case 1: return RGB(red: falling, green: brightness, blue: low)
        case 2: return RGB(red: low, green: brightness, blue: rising)
        case 3: return RGB(red: low, green: falling, blue: brightness)
        case 4: return RGB(red: rising, green: low, blue: brightness)
        default: return RGB(red: brightness, green: low, blue: falling)
        }
    }
}
