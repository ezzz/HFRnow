//
//  NatifTheme.swift
//  HFRswift
//
//  Design tokens of the "Natif calme" direction (see Design/natif/README.md).
//

import SwiftUI
import UIKit

// MARK: - Variants and accents

enum NatifThemeVariant: String {
    case light
    case dark
    case oled

    var isDark: Bool { self != .light }
}

/// User facing theme choice ("Thème : Auto / Clair / Sombre / OLED").
enum NatifThemeMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark
    case oled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .light: "Clair"
        case .dark: "Sombre"
        case .oled: "OLED"
        }
    }
}

struct NatifAccent: Identifiable, Equatable {
    let id: Int
    let name: String
    /// Light theme: text, icons and filled backgrounds.
    let light: UIColor
    /// Dark themes: text and icons (oklch L 0.72 / C 0.13).
    let darkText: UIColor
    /// Dark themes: filled backgrounds (oklch L 0.56 / C 0.16).
    let darkFill: UIColor

    /// "Couleur" choices, in display order. Same lightness and chroma for the hues; white on each
    /// `light` / `darkFill` stays at 4.5:1.
    static let all: [NatifAccent] = [
        // Black in the light theme, near white in the dark ones (filled backgrounds stay dark grey).
        NatifAccent(id: 7, name: "Noir", light: UIColor(natifHex: 0x1D1D1F), darkText: UIColor(natifHex: 0xF0F2F4), darkFill: UIColor(natifHex: 0x636366)),
        NatifAccent(id: 0, name: "Bleu", light: UIColor(natifHex: 0x2171CC), darkText: UIColor(natifHex: 0x6AA7F4), darkFill: UIColor(natifHex: 0x2474CF)),
        NatifAccent(id: 4, name: "Rouge", light: UIColor(natifHex: 0xBD423A), darkText: UIColor(natifHex: 0xEB8377), darkFill: UIColor(natifHex: 0xC0453D)),
        NatifAccent(id: 3, name: "Orange", light: UIColor(natifHex: 0xB25400), darkText: UIColor(natifHex: 0xE48B54), darkFill: UIColor(natifHex: 0xBA5100)),
        NatifAccent(id: 6, name: "Violet", light: UIColor(natifHex: 0x735CC7), darkText: UIColor(natifHex: 0xA495F0), darkFill: UIColor(natifHex: 0x765FCA)),
        NatifAccent(id: 5, name: "Rose", light: UIColor(natifHex: 0xC13F78), darkText: UIColor(natifHex: 0xEF86B2), darkFill: UIColor(natifHex: 0xC4427B)),
        // Former choices (Sarcelle 1, Vert 2) fall back to Bleu.
    ]

    /// Looked up by `id` (the stored value), not by position in `all`.
    static let blackID = 7

    static func accent(at id: Int) -> NatifAccent {
        all.first { $0.id == id } ?? all.first { $0.id == 0 } ?? all[0]
    }
}

// MARK: - Tokens

struct NatifTokens {
    let variant: NatifThemeVariant
    let accentChoice: NatifAccent

    let bg: Color
    let bgGrouped: Color
    let cell: Color
    let surface: Color
    let surface2: Color
    let text: Color
    let text2: Color
    let text3: Color
    let separator: Color
    let destructive: Color

    var accent: Color { Color(uiAccent) }
    var accentFill: Color { Color(uiAccentFill) }
    var accentSoft: Color { Color(uiAccentSoft) }

    var uiAccent: UIColor { variant.isDark ? accentChoice.darkText : accentChoice.light }
    var uiAccentFill: UIColor { variant.isDark ? accentChoice.darkFill : accentChoice.light }

    /// Track of switches that are on. "Noir" in the dark themes needs a lighter grey than its fill,
    /// or on and off tracks look the same.
    var switchFill: Color {
        if variant.isDark && accentChoice.id == NatifAccent.blackID {
            return Color(natifHex: 0x8E8E93)
        }
        return accentFill
    }

    /// Tinted background of category / Plus pictograms.
    var uiAccentSoft: UIColor {
        switch variant {
        case .light: accentChoice.light.natifBlended(with: .white, ratio: 0.88)
        case .dark: accentChoice.darkFill.natifBlended(with: UIColor(natifHex: 0x191B1D), ratio: 0.78)
        case .oled: accentChoice.darkFill.natifBlended(with: UIColor(natifHex: 0x131416), ratio: 0.82)
        }
    }

    init(variant: NatifThemeVariant, accent: NatifAccent) {
        self.variant = variant
        self.accentChoice = accent
        switch variant {
        case .light:
            bg = Color(natifHex: 0xFFFFFF)
            bgGrouped = Color(natifHex: 0xF2F3F5)
            cell = Color(natifHex: 0xFFFFFF)
            surface = Color(natifHex: 0xF2F3F5)
            surface2 = Color(natifHex: 0xE6E8EB)
            text = Color(natifHex: 0x151618)
            text2 = Color(natifHex: 0x606369)
            text3 = Color(natifHex: 0xA2A5AA)
            separator = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: 0.18)
            destructive = Color(natifHex: 0xE23532)
        case .dark:
            bg = Color(natifHex: 0x111213)
            bgGrouped = Color(natifHex: 0x0A0B0D)
            cell = Color(natifHex: 0x191B1D)
            surface = Color(natifHex: 0x202224)
            surface2 = Color(natifHex: 0x2F3033)
            text = Color(natifHex: 0xF0F2F4)
            text2 = Color(natifHex: 0xA1A5AB)
            text3 = Color(natifHex: 0x606369)
            separator = Color.white.opacity(0.12)
            destructive = Color(natifHex: 0xFF5B57)
        case .oled:
            bg = Color(natifHex: 0x000000)
            bgGrouped = Color(natifHex: 0x000000)
            cell = Color(natifHex: 0x131416)
            surface = Color(natifHex: 0x151618)
            surface2 = Color(natifHex: 0x232426)
            text = Color(natifHex: 0xF0F2F4)
            text2 = Color(natifHex: 0xA1A5AB)
            text3 = Color(natifHex: 0x606369)
            separator = Color.white.opacity(0.12)
            destructive = Color(natifHex: 0xFF5B57)
        }
    }

    static let fallback = NatifTokens(variant: .light, accent: NatifAccent.accent(at: 0))
}

private struct NatifTokensKey: EnvironmentKey {
    static let defaultValue = NatifTokens.fallback
}

extension EnvironmentValues {
    var natif: NatifTokens {
        get { self[NatifTokensKey.self] }
        set { self[NatifTokensKey.self] = newValue }
    }
}

// MARK: - Settings

/// Persists the theme mode and accent, and keeps the legacy keys (`auto_theme`, `theme`,
/// `theme_*_color_action`) in sync so that Objective-C screens and the topic WebView follow.
enum NatifAppearance {
    static let themeModeKey = "natif_theme_mode"
    static let accentKey = "natif_accent"
    /// Smiley zoom in topics: 1, 1.5 or 2.
    static let smileyScaleKey = "natif_smiley_scale"

    static func smileyScale(defaults: UserDefaults = .standard) -> Double {
        let value = defaults.double(forKey: smileyScaleKey)
        return [1, 1.5, 2].contains(value) ? value : 1
    }

    static func themeMode(defaults: UserDefaults = .standard) -> NatifThemeMode {
        if let raw = defaults.string(forKey: themeModeKey), let mode = NatifThemeMode(rawValue: raw) {
            return mode
        }
        // First launch of the reskin: derive the mode from the legacy settings.
        if AppThemeResolver.usesSystemColorScheme {
            return .auto
        }
        return defaults.integer(forKey: AppThemeResolver.manualThemeKey) == AppThemeResolver.darkThemeValue ? .dark : .light
    }

    static func setThemeMode(_ mode: NatifThemeMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: themeModeKey)
        switch mode {
        case .auto:
            AppThemeResolver.setUsesSystemColorScheme(defaults: defaults)
        case .light:
            AppThemeResolver.setManualLegacyThemeValue(AppThemeResolver.lightThemeValue, defaults: defaults)
        case .dark, .oled:
            AppThemeResolver.setManualLegacyThemeValue(AppThemeResolver.darkThemeValue, defaults: defaults)
        }
        AppThemeStore.shared.refresh(forceThemeRevision: true, notifyLegacy: true)
    }

    static func accentIndex(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: accentKey)
    }

    static func setAccent(_ accent: NatifAccent, defaults: UserDefaults = .standard) {
        defaults.set(accent.id, forKey: accentKey)
        ThemeUserColorStore.storeColor(accent.light, forKey: "theme_day_color_action")
        ThemeUserColorStore.storeColor(accent.darkText, forKey: "theme_night_color_action")
        AppThemeStore.shared.refresh(forceThemeRevision: true, notifyLegacy: true)
    }

    static func variant(for colorScheme: ColorScheme, mode: NatifThemeMode) -> NatifThemeVariant {
        guard colorScheme == .dark else { return .light }
        return mode == .oled ? .oled : .dark
    }

    static func tokens(for colorScheme: ColorScheme, defaults: UserDefaults = .standard) -> NatifTokens {
        NatifTokens(
            variant: variant(for: colorScheme, mode: themeMode(defaults: defaults)),
            accent: NatifAccent.accent(at: accentIndex(defaults: defaults))
        )
    }
}

// MARK: - Avatars

enum NatifAvatarColor {
    /// `oklch(0.62 0.13 h)` sampled every 20°, the hue being derived from a stable hash of the pseudo.
    private static let palette: [UInt32] = [
        0xC86265, 0xC66846, 0xBE7125, 0xAF7C00, 0x998700, 0x7C9128, 0x58994A, 0x239D6A,
        0x009F89, 0x009CA5, 0x0097BC, 0x248FCC, 0x5685D4, 0x787BD2, 0x9372C8, 0xA86AB6,
        0xB9649F, 0xC46183,
    ]

    static func color(for pseudo: String) -> Color {
        var hash: UInt32 = 5381
        for scalar in pseudo.lowercased().unicodeScalars {
            hash = (hash &* 33) &+ scalar.value
        }
        return Color(natifHex: palette[Int(hash % UInt32(palette.count))])
    }
}

// MARK: - Color helpers

extension Color {
    init(natifHex hex: UInt32) {
        self.init(UIColor(natifHex: hex))
    }
}

extension UIColor {
    convenience init(natifHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Mixes `self` with `other`; `ratio` is the share of `other`.
    func natifBlended(with other: UIColor, ratio: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let keep = 1 - ratio
        return UIColor(red: r1 * keep + r2 * ratio, green: g1 * keep + g2 * ratio, blue: b1 * keep + b2 * ratio, alpha: 1)
    }

    /// CSS `#RRGGBB` string, for the topic WebView.
    var natifCSSHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
