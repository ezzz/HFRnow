import SwiftUI

// Port of HFRswift/Swift/PlusTab.swift (PlusHomeView, PlusRow) @ 2440d79. Differences: the account button is top left, as
// `MainToolbar.swift:60-66` @ 87fe0d1c (#1057). #1107: the list look of every list (`listLook`).
/// The Plus tab: the legacy menu (`PlusTab.swift:11-60`), one row per entry in legacy order.
struct PlusView: View {
    let model: RootModel
    @State private var titleVisibility = TitleVisibility()
    @Environment(\.themeAppearance) private var appearance

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
                                .foregroundStyle(entry.isDestructive ? AccessibleColors.errorText : primaryText)
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

    /// The labels' colour: the system's primary for Legacy, as before; a theme's `textPrimary` (#842).
    private var primaryText: Color { appearance.listColors.map { Color(uiColor: $0.text) } ?? Color.primary }
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
                .modifier(PlusStackReader(entry: entry, model: model, environment: environment))
        case .qualityAlerts:
            QualityAlertsView(model: model.qualityAlerts, environment: environment)
                .modifier(PlusStackReader(entry: entry, model: model, environment: environment))
        }
    }
}

// Port of HFRswift/Swift/MainWindow.swift (handleRootSwap, the Plus tab: `:2157-2172`, `:1836-1839`) and
// FoldHandoffDestination.swift (`:1-57`) @ 87fe0d1c. Differences: the reader is the entry's `RootModel.detailReaders` entry in
// both roots, so no pending push and no reading registered; the topic sits over the entry's list, not over the Plus menu, and the
// entry it came from shows it unfolded, whatever the sidebar showed before (legacy carries it towards the current sidebar
// destination only when that is Bookmarks or Alertes Qualitay). GAP-217, LOT-147.
/// The Plus tab of the tab bar: the topic a Bookmarks or Alertes Qualitay row opened, pushed over the list and read from
/// `RootModel.detailReaders`, the reader the split's detail column shows, so a fold pushes the topic open in the detail column
/// and an unfold shows the one open on the cover screen; back closes it, so an unfold does not bring it back. Inert where the
/// list already has a detail column (`openTopicInDetail` set by `PlusListColumn`).
struct PlusStackReader: ViewModifier {
    let entry: PlusEntry
    let model: RootModel
    let environment: AppEnvironment
    @Environment(\.openTopicInDetail) private var detailColumn

    func body(content: Content) -> some View {
        if detailColumn != nil {
            content
        } else {
            content
                .environment(
                    \.openTopicInDetail,
                    RootSidebarView.detailOpener(model: model, environment: environment, entry: entry, besideTheList: false)
                )
                .navigationDestination(isPresented: isPushing) {
                    if let reader = model.detailReaders[entry] {
                        TopicReaderView(model: reader, services: environment.reader, composer: environment.composer)
                    }
                }
        }
    }

    private var isPushing: Binding<Bool> {
        Binding(
            get: { model.detailReaders[entry] != nil },
            set: { if !$0 { model.closeDetail(for: entry) } }
        )
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
