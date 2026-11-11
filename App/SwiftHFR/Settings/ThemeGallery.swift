import HFRModels
import HFRStorage
import SwiftUI

// Port of none @ 87fe0d1c: legacy had two themes, light and dark (`Classes/Constants.h` `Theme`, `HFRswift/Swift/
// AppSettingsView.swift:421-466` `themeSection`), no gallery. Differences: the whole view is new (LOT-188, GAP-729, b·operator
// 2026-10-28; Legacy stays the default).
/// The theme gallery of Réglages › Thème (THEMES.md §1): one section per family, each theme with its light and dark swatch
/// (one swatch and « clair = sombre » for a single-variant theme), its name, « par <auteur> » and a check mark on the active
/// one. Its own view so that LOT-180 (#420) can move it into a « Thème » sub-menu with previews instead of building another.
struct ThemeGallery: View {
    @Environment(ThemeSettingsModel.self) private var theme

    var body: some View {
        let families = theme.catalog.galleryFamilies
        ForEach(Array(families.enumerated()), id: \.element.family) { index, group in
            Section {
                ForEach(group.themes) { item in
                    ThemeGalleryRow(theme: item, legacy: theme.appearance, isSelected: item.id == theme.theme.id) {
                        theme.select(item)
                    }
                }
            } header: {
                Text(group.family)
            } footer: {
                if index == families.count - 1 {
                    Text("Envie de proposer un thème ? Les règles sont dans le dépôt : docs/THEMES.md (voir le README).")
                }
            }
        }
    }
}

/// One theme of the gallery: swatches, name, author, check mark.
struct ThemeGalleryRow: View {
    let theme: ThemeDefinition
    /// The app's own colours, which Legacy's swatches show (the user's hue and dark style).
    let legacy: ThemeAppearance
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in ThemeSwatch(swatch: swatch) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name).foregroundStyle(.primary)
                    if let author = theme.author {
                        Text("par \(author)").scaledFont(.footnote).foregroundStyle(.secondary)
                    }
                    if case .single? = theme.variants {
                        Text("clair = sombre").scaledFont(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The button stays the element (VoiceOver activates it); its label replaces the texts it reads one by one.
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        var parts = [theme.name]
        if let author = theme.author { parts.append("par \(author)") }
        if case .single? = theme.variants { parts.append("clair = sombre") }
        return parts.joined(separator: ", ")
    }

    /// Light then dark, or the one variant.
    private var swatches: [ThemeSwatch.Colors] {
        switch theme.variants {
        case nil:
            let darkBackground = legacy.readerSurfaces.first { $0.variable == "--app-dark-background" }?.color ?? ThemeColor(hex: 0)
            return [
                .init(background: ThemeColor(hex: 0xF2F2F7), page: ThemeColor(hex: 0xFFFFFF), accent: legacy.dayAccent),
                .init(background: darkBackground, page: darkBackground, accent: legacy.nightAccent)
            ]
        case let .lightDark(light, dark)?:
            return [.init(light), .init(dark)]
        case let .single(tokens)?:
            return [.init(tokens)]
        }
    }
}

/// A small sample of a variant, in the colours the app draws with it: the screen background, a card of the reader's page and a
/// dot of the tint (LOT-188: a theme's `background`, `surface` and `accentText`; Legacy's grouped background, its reader page and
/// the user's accent).
struct ThemeSwatch: View {
    /// The colours a swatch shows.
    struct Colors {
        let background: ThemeColor
        let page: ThemeColor
        let accent: ThemeColor

        init(background: ThemeColor, page: ThemeColor, accent: ThemeColor) {
            self.background = background
            self.page = page
            self.accent = accent
        }

        init(_ tokens: ThemeTokens) {
            self.init(
                background: ThemeColor(rgb: tokens.background), page: ThemeColor(rgb: tokens.surface),
                accent: ThemeColor(rgb: tokens.accentText)
            )
        }
    }

    let swatch: Colors
    @ScaledMetric(relativeTo: .body) private var size = 30.0

    var body: some View {
        RoundedRectangle(cornerRadius: size / 5)
            .fill(Color(uiColor: swatch.background.uiColor))
            .overlay(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: size / 10)
                    .fill(Color(uiColor: swatch.page.uiColor))
                    .frame(width: size * 0.6, height: size * 0.4)
                    .padding(size / 10)
            }
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color(uiColor: swatch.accent.uiColor)).frame(width: size / 3, height: size / 3).padding(size / 10)
            }
            .overlay { RoundedRectangle(cornerRadius: size / 5).strokeBorder(.separator, lineWidth: 1) }
            .frame(width: size, height: size)
    }
}
