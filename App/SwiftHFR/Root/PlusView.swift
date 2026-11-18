import SwiftUI

// Port of HFRswift/Swift/PlusTab.swift (PlusHomeView, PlusRow) @ 2440d79. Differences: an entry shows a placeholder until its lot lands;
// the account button is top left, as `MainToolbar.swift:60-66` @ 87fe0d1c (#1057).
/// The Plus tab: the legacy menu (`PlusTab.swift:11-60`), one row per entry in legacy order.
struct PlusView: View {
    let model: RootModel
    @State private var titleVisibility = TitleVisibility()
    @Environment(\.themeAppearance) private var appearance

    var body: some View {
        // A row sets `model.plusEntry` and the tab's stack opens it (RootTabsView), so the open entry is the one selection
        // both layouts read; a `NavigationLink(value:)` would push onto the stack without updating it.
        List {
            ScreenLargeTitle(title: "Plus", visibility: titleVisibility)
            ForEach(PlusEntry.allCases, id: \.self) { entry in
                Button {
                    model.plusEntry = entry
                } label: {
                    HStack {
                        Label(entry.title, systemImage: entry.symbol)
                            .foregroundStyle(entry.isDestructive ? AccessibleColors.errorText : primaryText)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .scaledFont(.footnote).fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .themedListRow()
            }
        }
        .screenTitle("Plus", style: .largeThenPill, visibility: titleVisibility)
        .accountMenuToolbarItem()
    }

    /// The labels' colour: the system's primary for Legacy, as before; a theme's `textPrimary` (#842).
    private var primaryText: Color { appearance.listColors.map { Color(uiColor: $0.text) } ?? Color.primary }
}

/// The screen behind a Plus entry: the built screen, or a placeholder until the owning lot (`PlusEntry.owningLot`) brings it.
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
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            entry.title, systemImage: entry.symbol,
            description: Text("Cet écran arrive dans une prochaine version.")
        )
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
