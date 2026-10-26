import Foundation

/// A user-tinted theme colour as the legacy app stores it: the string `{r, g, b, a}` with three decimals
/// (`ThemeUserColorStore`, `Common.swift:545-590`). Components are sRGB-like values, normally in 0...1.
public struct ThemeColor: Sendable, Hashable {
    /// Red component.
    public var red: Double
    /// Green component.
    public var green: Double
    /// Blue component.
    public var blue: Double
    /// Opacity.
    public var alpha: Double

    /// Creates a colour from its components.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `{r, g, b, a}`; returns nil unless there are exactly four finite numbers between braces.
    public init?(serialized: String) {
        let trimmed = serialized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        let parts = trimmed.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
        let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.filter(\.isFinite)
        guard parts.count == 4, values.count == 4 else { return nil }
        self.init(red: values[0], green: values[1], blue: values[2], alpha: values[3])
    }

    /// The legacy string form, with three decimals and a point separator whatever the locale.
    public var serialized: String {
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(3))
            .grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX"))
        let parts = [red, green, blue, alpha].map { $0.formatted(style) }
        return "{" + parts.joined(separator: ", ") + "}"
    }
}
