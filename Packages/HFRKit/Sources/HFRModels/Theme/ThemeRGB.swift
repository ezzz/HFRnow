import Foundation

/// An sRGB colour of a theme file, written `#RRGGBB` or `#RRGGBBAA` (THEMES.md §3, LOT-188).
public struct ThemeRGB: Sendable, Hashable, Decodable, CustomStringConvertible {
    /// Red, 0...255.
    public let red: Int
    /// Green, 0...255.
    public let green: Int
    /// Blue, 0...255.
    public let blue: Int
    /// Opacity, 0...255 (255 when the file gives six digits).
    public let alpha: Int

    /// Creates a colour from its channels, each clamped to 0...255.
    public init(red: Int, green: Int, blue: Int, alpha: Int = 255) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
        self.alpha = min(max(alpha, 0), 255)
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA` (hex digits in either case); nil for anything else.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(
            red: Int((rgba >> 24) & 0xFF), green: Int((rgba >> 16) & 0xFF), blue: Int((rgba >> 8) & 0xFF), alpha: Int(rgba & 0xFF)
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = ThemeRGB(hex: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a #RRGGBB or #RRGGBBAA colour: \(text)")
        }
        self = color
    }

    /// True when the colour is fully opaque.
    public var isOpaque: Bool { alpha == 255 }

    /// `#RRGGBB`, plus `AA` when not opaque.
    public var description: String {
        let channels = isOpaque ? [red, green, blue] : [red, green, blue, alpha]
        return "#" + channels.map { channel in
            let digits = String(channel, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }

    /// WCAG 2.x relative luminance of the colour (opacity ignored).
    public var luminance: Double {
        func linear(_ value: Int) -> Double {
            let channel = Double(value) / 255
            return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// `other` mixed into this colour by `amount` (0...1), channel by channel in sRGB, as CSS `color-mix(in srgb, …)`.
    public func mixed(with other: ThemeRGB, amount: Double) -> ThemeRGB {
        func mix(_ base: Int, _ added: Int) -> Int { Int((Double(base) * (1 - amount) + Double(added) * amount).rounded()) }
        return ThemeRGB(red: mix(red, other.red), green: mix(green, other.green), blue: mix(blue, other.blue))
    }

    /// WCAG 2.x contrast ratio against `other`, 1...21 (opacity ignored: the rules only pair opaque colours).
    public func contrast(with other: ThemeRGB) -> Double {
        let (lighter, darker) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }
}
