import HFRModels
import SwiftUI
import UIKit

// New in SwiftHFR (#842, operator decision of 2026-11-18, option B): a gallery theme recolours the native lists (rows, separators,
// selection, section headers, the large title) through these modifiers, the only place that rule lives; #836 later merges the list
// copies and their call sites, and the modifiers come along. Legacy applies none of them (pixel-identical, LOT-188).
/// The colours a native list draws under a gallery theme (THEMES.md §3): a row and its text on `surface`, the selected row on
/// `selection`, `separator`, and on `background` the section headers and the large title. Each is dynamic (light and dark).
struct ThemedListColors {
    /// A row or card (`surface`, THEMES.md §3 "rows and cards").
    let row: UIColor
    /// The selected row (`selection`).
    let selectedRow: UIColor
    /// Row and section separators (`separator`, one definition, #572).
    let separator: UIColor
    /// A row's text (`textPrimary`): the primary style of the row, so `.primary` text (an unread MP title, #651) reads it.
    let text: UIColor
    /// A row's secondary text (`textSecondary`): the secondary style, so `.secondary` text (a read MP title, #651) reads it.
    let secondaryText: UIColor
    /// Section headers and footers, drawn on `background` (`sectionHeader`).
    let sectionHeader: UIColor
    /// The large title, drawn on `background` (`title`).
    let title: UIColor
}

extension ThemeAppearance {
    /// The colours of a themed native list, or nil for Legacy: the system's, untouched (no modifier is applied at all).
    var listColors: ThemedListColors? {
        guard let row = themeColor(\.surface), let selectedRow = themeColor(\.selection), let separator = themeColor(\.separator),
              let text = themeColor(\.textPrimary), let secondaryText = themeColor(\.textSecondary),
              let sectionHeader = themeColor(\.sectionHeader), let title = themeColor(\.title) else { return nil }
        return ThemedListColors(
            row: row, selectedRow: selectedRow, separator: separator, text: text, secondaryText: secondaryText,
            sectionHeader: sectionHeader, title: title
        )
    }
}

extension View {
    /// A native list row (or every row of a `Section` or `ForEach` it wraps) under the theme (#842): background, separators, and
    /// the primary and secondary text styles. `isSelected` paints the theme's `selection` instead of the row colour: a row
    /// background replaces the system's own selection fill. Not for a row that sets its own background (a clear banner, the
    /// large title): which of two row backgrounds wins is not something to rely on. Legacy: nothing, or, with `legacySelection`,
    /// that colour behind a selected row, as the call site drew it before (Bookmarks).
    func themedListRow(isSelected: Bool = false, legacySelection: Color? = nil) -> some View {
        modifier(ThemedListRow(isSelected: isSelected, legacySelection: legacySelection))
    }

    /// A section header or footer under the theme (#842): its text in `sectionHeader`, which holds 4.5:1 on `background`.
    /// Legacy: nothing.
    func themedSectionHeader() -> some View { modifier(ThemedListText(role: .sectionHeader)) }

    /// A screen's large title under the theme (#842): `title`, which holds 4.5:1 on `background`. Legacy: nothing.
    func themedTitle() -> some View { modifier(ThemedListText(role: .title)) }
}

private struct ThemedListRow: ViewModifier {
    let isSelected: Bool
    let legacySelection: Color?
    @Environment(\.themeAppearance) private var appearance

    /// Legacy keeps `content` as is; only a change between Legacy and a theme changes the structure, which the user asked for
    /// (as `appScreenBackground()`), never a flip of appearance (the colours are dynamic).
    @ViewBuilder func body(content: Content) -> some View {
        if let colors = appearance.listColors {
            let separator = Color(uiColor: colors.separator)
            content
                .foregroundStyle(Color(uiColor: colors.text), Color(uiColor: colors.secondaryText))
                .listRowBackground(Color(uiColor: isSelected ? colors.selectedRow : colors.row))
                .listRowSeparatorTint(separator)
                .listSectionSeparatorTint(separator)
        } else if let legacySelection {
            content.listRowBackground(isSelected ? legacySelection : nil)
        } else {
            content
        }
    }
}

private struct ThemedListText: ViewModifier {
    enum Role { case sectionHeader, title }
    let role: Role
    @Environment(\.themeAppearance) private var appearance

    @ViewBuilder func body(content: Content) -> some View {
        if let colors = appearance.listColors {
            let color = Color(uiColor: role == .title ? colors.title : colors.sectionHeader)
            // Both levels: a header's own `.secondary` text (a count) must stay on the token, not fade below its contrast.
            content.foregroundStyle(color, color)
        } else {
            content
        }
    }
}

/// A list section with a text header, as `Section("…") { … }`, whose rows and header follow the theme (#842); Legacy draws what
/// `Section("…")` draws.
struct ThemedSection<Content: View>: View {
    private let title: Text
    private let content: Content

    /// A localized header, as `Section(_ titleKey:content:)`.
    init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        title = Text(titleKey)
        self.content = content()
    }

    /// A header read verbatim, as `Section(_ title:content:)` with a string value.
    init(verbatim title: some StringProtocol, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    var body: some View {
        Section {
            Group { content }.themedListRow()
        } header: {
            title.themedSectionHeader()
        }
    }
}
