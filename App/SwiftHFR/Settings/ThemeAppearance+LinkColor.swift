import HFRStorage
import SwiftUI

/// The colour of a body link in Legacy's reader (#1374). The accent is a fill colour (saturation 0.65, brightness 1 by day), so as
/// text it was 1.5:1 on white at the default hue; a link takes the accent moved toward black (light) or white (dark) until it holds
/// `linkContrast` on every surface a link can sit on. The accent itself keeps painting fills, controls and the app tint.
extension ThemeAppearance {
    /// What a link must reach: WCAG's 4.5:1 plus a margin for the surfaces the page composites in CSS (tints over tints).
    static let linkContrast = 4.7
    /// `.continuation { opacity: 0.75 }` in `reader.css`.
    static let continuationOpacity = 0.75

    /// The reader's variables of the link colour, for Legacy only: a gallery theme brings its own `link` token (THEMES.md §3).
    var readerLinkVariables: [(name: String, value: String)] {
        guard themeVariants == nil else { return [] }
        return [("--app-link-light", linkColor(dark: false).cssRGB), ("--app-link-dark", linkColor(dark: true).cssRGB)]
    }

    /// The accent of the variant, moved toward black or white by the smallest share that reaches `linkContrast` on `linkSurfaces`.
    func linkColor(dark: Bool) -> ThemeColor {
        let accent = dark ? nightAccent : dayAccent
        let target = dark ? ThemeColor(hex: 0xFFFFFF) : ThemeColor(hex: 0x000000)
        let surfaces = linkSurfaces(dark: dark)
        let page = surfaces[0]
        // A continuation fades its whole message (`opacity: 0.75`) toward the page: the faded link must hold on the faded surface too.
        func fades(_ color: ThemeColor) -> ThemeColor { page.mixed(with: color, share: Self.continuationOpacity) }
        func holds(_ color: ThemeColor) -> Bool {
            surfaces.allSatisfy {
                color.contrast(with: $0) >= Self.linkContrast && fades(color).contrast(with: fades($0)) >= Self.linkContrast
            }
        }
        guard !holds(accent) else { return accent }
        var (low, high) = (0.0, 1.0)
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if holds(accent.mixed(with: target, share: middle)) { high = middle } else { low = middle }
        }
        return accent.mixed(with: target, share: high)
    }

    /// The surfaces a body link sits on, light or dark: the page, the placeholder, the visibility fills (`--love`, `--modo`) and the
    /// tints the page composites (quotes nested in tinted quotes add up to about 15 % of the text colour, a header or own message 15 % of
    /// the accent).
    func linkSurfaces(dark: Bool) -> [ThemeColor] {
        let text = dark ? Self.darkText : ThemeColor(hex: 0x1C1C1E)
        let accent = dark ? nightAccent : dayAccent
        let variables = Dictionary(uniqueKeysWithValues: (dark ? readerSurfaces : lightSurfaces).map { ($0.variable, $0.color) })
        let prefix = dark ? "--app-dark-" : "--app-light-"
        let page = variables[prefix + "background"] ?? ThemeColor(hex: dark ? 0x2E2F33 : 0xFFFFFF)
        let placeholder = variables[prefix + "placeholder"] ?? ThemeColor(hex: dark ? 0x35363B : 0xE5E5EA)
        let fills = (dark ? [0x4D0831, 0x4A2E3C] : [0xFFE6F5, 0xFFEEEE]).map { ThemeColor(hex: $0) }
        let nested = ([page] + fills).map { $0.mixed(with: text, share: 0.15) }
        return [page, placeholder] + fills + nested + [page.mixed(with: accent, share: 0.15)]
    }
}

extension ThemeColor {
    /// This colour with `share` (0...1) of `other` mixed in, in sRGB as CSS `color-mix` does.
    func mixed(with other: ThemeColor, share: Double) -> ThemeColor {
        ThemeColor(
            red: red + (other.red - red) * share, green: green + (other.green - green) * share,
            blue: blue + (other.blue - blue) * share, alpha: alpha
        )
    }
}
