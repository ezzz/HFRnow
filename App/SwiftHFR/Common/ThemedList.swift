import HFRModels
import SwiftUI
import UIKit

// New in SwiftHFR (#842, operator decision of 2026-11-18, option B): a gallery theme recolours the native lists (rows, separators,
// selection, section headers, the large title) through these modifiers, the only place that rule lives; #836 later merges the list
// copies and their call sites, and the modifiers come along. Legacy applies none of them (pixel-identical, LOT-188).
/// The colours a native list draws under a gallery theme (THEMES.md §3): a row and its text on `surface`, the selected row on
/// `selection`, `separator`, and on `background` the screen of a sheet, the section headers and the large title. Each is
/// dynamic (light and dark).
struct ThemedListColors {
    /// The screen behind a list that no `appScreenBackground()` paints (a sheet on a plain stack): `background`.
    let screen: UIColor
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
        guard let screen = themeColor(\.background), let row = themeColor(\.surface), let selectedRow = themeColor(\.selection),
              let separator = themeColor(\.separator),
              let text = themeColor(\.textPrimary), let secondaryText = themeColor(\.textSecondary),
              let sectionHeader = themeColor(\.sectionHeader), let title = themeColor(\.title) else { return nil }
        return ThemedListColors(
            screen: screen, row: row, selectedRow: selectedRow, separator: separator, text: text, secondaryText: secondaryText,
            sectionHeader: sectionHeader, title: title
        )
    }
}

extension View {
    /// A native list row (or every row of a `Section`, `ForEach` or `Group` it wraps) under the theme (#842): background and
    /// separators. Its text is `themedRowText()`'s, applied where the row's content is drawn, so a `Button` row keeps its tint (the
    /// accent, `accentText`): a foreground style set on the row would replace it. The background follows the list look (#1107):
    /// `surface` in the classic look, none in the dense one (the rows on the theme's background), and `selection` for a selected
    /// row in both, since a row background replaces the system's own selection fill. A row's own `listRowBackground` set inside
    /// it wins (`listLookRows()`). `listLookRows()` and `listLookRow(isSelected:)` hand their rows to it under a theme. Legacy:
    /// nothing.
    /// `position` (a section's rows, `ThemedSection` or `ThemedRows`) lets a flat theme outline the group (#1456,
    /// `GroupOutline.swift`); a row with none draws no outline, so a list with no card (the iPad sidebar) is never boxed.
    func themedListRow(isSelected: Bool = false, position: GroupRowPosition? = nil) -> some View {
        modifier(ThemedListRow(isSelected: isSelected, position: position))
    }

    /// A row's text under the theme (#842): `textPrimary` as the primary style and `textSecondary` as the secondary one, so
    /// `.primary` and `.secondary` text follow. For a row's own content (a topic, a conversation, a forum, a field), never
    /// around a `Button` whose label should keep the tint. Native text elsewhere keeps the system label of the appearance the
    /// theme shows in, which its contrast test checks on `surface`. Legacy: nothing.
    func themedRowText() -> some View { modifier(ThemedListText(role: .rowText)) }

    /// A list or form shown in a sheet on a plain `NavigationStack` (no `appScreenBackground()`): the theme's `background`
    /// behind it, under its themed headers and rows (#842). Legacy: nothing.
    func themedListScreen() -> some View { modifier(ThemedListScreen()) }

    /// A section header or footer under the theme (#842): its text in `sectionHeader`, which holds 4.5:1 on `background`.
    /// Legacy: nothing.
    func themedSectionHeader() -> some View { modifier(ThemedListText(role: .sectionHeader)) }

    /// A destructive `Button` that is a row of a themed list (#1121): under a theme its label takes `AccessibleColors.errorText`
    /// (the system red measures 3.75:1 on some themes' `surface`). The system still dims it when disabled, explicit style
    /// included (CI render of #1350: errorText at about 0.5 over `surface`), so no opacity is added here. Never on a `.plain`
    /// button (the role's red does not reach its glyph), an alert, a dialog, a swipe action or a toolbar. Legacy: nothing.
    func themedDestructive() -> some View { modifier(ThemedDestructive()) }

    /// A screen's large title under the theme (#842): `title`, which holds 4.5:1 on `background`. Legacy: nothing.
    func themedTitle() -> some View { modifier(ThemedListText(role: .title)) }
}

private struct ThemedListRow: ViewModifier {
    let isSelected: Bool
    var position: GroupRowPosition?
    @Environment(\.themeAppearance) private var appearance
    @Environment(\.listLook) private var look

    /// Legacy keeps `content` as is; only a change between Legacy and a theme changes the structure, which the user asked for
    /// (as `appScreenBackground()`), never a flip of appearance (the colours are dynamic).
    @ViewBuilder func body(content: Content) -> some View {
        if let colors = appearance.listColors {
            let separator = Color(uiColor: colors.separator)
            content
                .listRowBackground(rowBackground(colors))
                .listRowSeparatorTint(separator)
                .listSectionSeparatorTint(separator)
        } else {
            content
        }
    }

    /// The row's fill, with the group outline (#1456) in the classic look, where a card exists to be outlined.
    @ViewBuilder private func rowBackground(_ colors: ThemedListColors) -> some View {
        let fill = Self.background(colors, isSelected: isSelected, look: look)
        if look == .classic, let position, let outline = appearance.groupOutlineColor {
            GroupOutlineRowBackground(fill: fill, outline: Color(uiColor: outline), position: position)
        } else {
            fill
        }
    }

    /// A themed row's background: `selection` when selected, else `surface` in the classic look and none in the dense one.
    static func background(_ colors: ThemedListColors, isSelected: Bool, look: ListLook) -> Color {
        if isSelected { return Color(uiColor: colors.selectedRow) }
        return look == .dense ? DenseListLook.rowBackground : Color(uiColor: colors.row)
    }
}

private struct ThemedListText: ViewModifier {
    enum Role { case rowText, sectionHeader, title }
    let role: Role
    @Environment(\.themeAppearance) private var appearance

    @ViewBuilder func body(content: Content) -> some View {
        if let colors = appearance.listColors {
            let (primary, secondary) = Self.colors(role, colors)
            content.foregroundStyle(Color(uiColor: primary), Color(uiColor: secondary))
        } else {
            content
        }
    }

    /// The primary and secondary style of `role`. A header and the title use their token at both levels: a header's own
    /// `.secondary` text (a count) must stay on the token, not fade below its contrast.
    static func colors(_ role: Role, _ colors: ThemedListColors) -> (UIColor, UIColor) {
        switch role {
        case .rowText: (colors.text, colors.secondaryText)
        case .sectionHeader: (colors.sectionHeader, colors.sectionHeader)
        case .title: (colors.title, colors.title)
        }
    }
}

private struct ThemedDestructive: ViewModifier {
    @Environment(\.themeAppearance) private var appearance

    @ViewBuilder func body(content: Content) -> some View {
        if appearance.listColors != nil {
            content.foregroundStyle(AccessibleColors.errorText)
        } else {
            content
        }
    }
}

private struct ThemedListScreen: ViewModifier {
    @Environment(\.themeAppearance) private var appearance

    @ViewBuilder func body(content: Content) -> some View {
        if let colors = appearance.listColors {
            content
                .scrollContentBackground(.hidden)
                .background { Color(uiColor: colors.screen).ignoresSafeArea() }
        } else {
            content
        }
    }
}

/// The rows of one section under the theme, as `Group { … }.themedListRow()` did, each told its place in the section so that a flat
/// theme outlines the group as one shape (#1456, `GroupOutline.swift`). Put it directly in the `Section`, around every row.
struct ThemedRows<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        Group(subviews: content) { rows in
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                row.themedListRow(position: GroupRowPosition(index: index, count: rows.count))
            }
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
            ThemedRows { content }
        } header: {
            title.themedSectionHeader()
        }
    }
}

/// Error text on a list row (#842): the system red for Legacy, as before; under a theme the app's `AccessibleColors.errorText`,
/// which the theme's contrast test checks on `surface` (`errorText`): the system red is under 4.5:1 on some themes' rows.
struct ThemedErrorStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.themeAppearance.listColors == nil ? AnyShapeStyle(Color.red) : AnyShapeStyle(AccessibleColors.errorText)
    }
}

extension ShapeStyle where Self == ThemedErrorStyle {
    /// `ThemedErrorStyle`: `.red` for Legacy, the accessible error colour under a theme.
    static var themedError: ThemedErrorStyle { ThemedErrorStyle() }
}
