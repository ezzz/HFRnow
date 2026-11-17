import SwiftUI

// New in SwiftHFR (#896, operator 2026-11-14): legacy's bar has four items (`RootTabIdentifier`, `Common.swift:25-30`). Off, the
// bar is legacy's; on, a Recherche item sits left of Plus. The search screen is the one of the Plus entry, with the same model.
/// The fifth tab of the iPhone bar, behind Réglages › Expérimental › « Recherche dans la barre » (#896).
struct SearchRootTab: View {
    let model: RootModel
    let environment: AppEnvironment

    var body: some View {
        ThemedNavigationStack {
            ForumSearchView(model: model.search, forums: model.forums, reader: environment.reader, composer: environment.composer)
                .appScreenBackground()
        }
        .environment(\.isSelectedRootTab, model.selectedTab == .search)
    }
}

/// The rules of the fifth tab that do not need a view.
enum SearchTabOption {
    /// Whether the bar has the Recherche item.
    static func isOn(_ experimental: ExperimentalSettings?) -> Bool {
        ExperimentalSettings.isOn(.searchTab, in: experimental)
    }

    /// The tab to show for `selected`: Recherche falls back to Plus while the option is off, so a selection restored from a
    /// session with the option on never points at a tab the bar does not have.
    static func visibleTab(_ selected: RootTab, isOn: Bool) -> RootTab {
        selected == .search && !isOn ? .more : selected
    }
}
