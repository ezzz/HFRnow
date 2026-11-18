import SwiftUI

// Port of HFRswift/Swift/PlusTab.swift (PlusHomeView, PlusRow) @ 2440d79. Differences: the account button is top left, as
// `MainToolbar.swift:60-66` @ 87fe0d1c (#1057). #1107: the list look of every list (`listLook`).
/// The Plus tab: the legacy menu (`PlusTab.swift:11-60`), one row per entry in legacy order.
struct PlusView: View {
    let model: RootModel
    @State private var titleVisibility = TitleVisibility()

    var body: some View {
        // A row sets `model.plusEntry` and the tab's stack opens it (RootTabsView), so the open entry is the one selection
        // both layouts read; a `NavigationLink(value:)` would push onto the stack without updating it.
        List {
            // #1107: every row of the list takes its look, once for the whole content.
            Group {
                ScreenLargeTitle(title: "Plus", visibility: titleVisibility)
                ForEach(PlusEntry.allCases, id: \.self) { entry in
                    Button {
                        model.plusEntry = entry
                    } label: {
                        HStack {
                            Label(entry.title, systemImage: entry.symbol)
                                .foregroundStyle(entry.isDestructive ? AccessibleColors.errorText : Color.primary)
                            Spacer()
                            PlusBadgeCount(value: model.badge(for: entry))
                            Image(systemName: "chevron.forward")
                                .scaledFont(.footnote).fontWeight(.semibold)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .listLookRows()
        }
        .listLook()
        .screenTitle("Plus", style: .largeThenPill, visibility: titleVisibility)
        .accountMenuToolbarItem()
    }
}

/// The screen behind a Plus entry.
struct PlusEntryView: View {
    let entry: PlusEntry
    let model: RootModel
    let environment: AppEnvironment

    var body: some View {
        switch entry {
        case .search:
            ForumSearchView(model: model.search, forums: model.forums, reader: environment.reader, composer: environment.composer)
        case .settings:
            SettingsView(reader: environment.reader, mpStorage: model.mpStorage)
        // "Crédits" is the About screen (LOT-120, operator decision 2026-10-28).
        case .credits:
            AboutView(environment: environment)
        case .charter:
            StaticPageView(page: .charter)
        case .deleteAccount:
            AccountDeletionView()
        case .bookmarks:
            BookmarksView(mpStorage: model.mpStorage, selection: model.bookmarkSelection, environment: environment)
        case .qualityAlerts:
            QualityAlertsView(model: model.qualityAlerts, environment: environment)
        }
    }
}

/// The count a Plus row announces, as legacy's red tab badge does; nothing at 0.
private struct PlusBadgeCount: View {
    let value: Int

    var body: some View {
        if value > 0 {
            Text(value, format: .number)
                .scaledFont(.footnote).bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.red, in: .capsule)
                .accessibilityLabel("\(value) nouvelles")
        }
    }
}
