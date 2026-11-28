import SwiftUI

/// What a forum's topic list needs to offer its sub-forum picker and its filter: the category it belongs to, the shared filter
/// choice and how to open another source.
struct ForumScope {
    /// Read when the bar draws, so the menu appears once the home page has loaded, whatever view built the scope.
    let section: () -> ForumSection?
    let filter: TopicFilterModel
    /// Runs on the main actor: it writes the navigation model, and the picker binding hands it to SwiftUI as a `@Sendable` setter.
    let select: @MainActor (TopicSource) -> Void
}

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsListView.body: the "Sous-forum" picker and the filter, `:662-710`) @ 87fe0d1c.
// Differences: a sub-forum's filter waits for its page to name the `subcat` (GAP-022, 023); the notes are the app's own.
/// The first rows of a forum's topic list: the sub-forum menu (when the category has some), the filter and, when the filter is
/// off, why.
struct ForumScopeBar: View {
    let model: TopicListModel
    let scope: ForumScope

    var body: some View {
        Group {
            if let section = scope.section(), section.subforumCount > 0 { subforumRow(section) }
            // Rows of the topic block, not a section of their own: legacy's picker and filter sit at the top of the same block (#803).
            TopicFlagFilterPicker(filter: scope.filter, canFilter: model.offersFilter).densityRowMargin()
            if let note = model.filterNote { noteRow(note).densityRowMargin() }
        }
        .themedListRow()
    }

    private func subforumRow(_ section: ForumSection) -> some View {
        SubforumPickerRow(section: section, selection: Binding(get: { model.source }, set: scope.select)).densityRowMargin()
    }
}

/// The « Sous-forum » menu of a category's list (legacy's picker, `MainWindow.swift:662-680` @ 87fe0d1c): label and menu side by side.
struct SubforumPickerRow: View {
    let section: ForumSection
    @Binding var selection: TopicSource
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // #1439: at these sizes a `.menu` picker in a list row is taller than the cell the list gives it (measured: 151.7 pt
                // of content in a 135.7 pt cell, centred, so the label sat 8 pt above the card's top edge), and at its ideal height
                // its own two-line title is cut. A menu whose label is plain text sizes like any text. The label goes above the
                // menu with the row's whole width (HIG: stack at accessibility sizes).
                VStack(alignment: .leading, spacing: 4) {
                    // The menu says « Sous-forum » to VoiceOver itself: the visible label is not read twice.
                    Text("Sous-forum").accessibilityHidden(true)
                    Menu {
                        options.pickerStyle(.inline)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(selectedTitle).multilineTextAlignment(.leading)
                            Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                        }
                        .foregroundStyle(.tint) // as the menu picker's value, not the row's secondary label colour
                    }
                    .accessibilityLabel("Sous-forum")
                    .accessibilityValue(selectedTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LabeledContent("Sous-forum") { options.pickerStyle(.menu) }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var options: some View {
        Picker("Sous-forum", selection: $selection) {
            Text(Self.allTitle).tag(section.source)
            ForEach(section.rows.dropFirst()) { Text($0.title).tag($0.source) }
        }
        .labelsHidden()
    }

    private static let allTitle = "Tous les sous-forums"

    /// The chosen entry's title, as the menu shows it.
    var selectedTitle: String {
        guard selection != section.source else { return Self.allTitle }
        return section.rows.first { $0.source == selection }?.title ?? Self.allTitle
    }
}

extension ForumScopeBar {
    /// Why Favoris, Suivis and Lus cannot be chosen (`TopicListModel.filterNote`): legacy's icon, bold title and subtitle when logged
    /// out (`MainWindow.swift:699-706` @ 87fe0d1c), or a list that names no `subcat`.
    @ViewBuilder
    private func noteRow(_ note: FilterNote) -> some View {
        if let subtitle = note.subtitle {
            VStack(alignment: .leading, spacing: 6) {
                Label(note.title, systemImage: note.systemImage).font(.footnote.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(note.title).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
