import SwiftUI

/// The Plus tab: the legacy menu (`PlusTab.swift:11-60`), one row per entry in legacy order.
struct PlusView: View {
    let model: RootModel

    var body: some View {
        // A row sets `model.plusEntry` and the tab's stack opens it (RootTabsView), so the open entry is the one selection
        // both layouts read; a `NavigationLink(value:)` would push onto the stack without updating it.
        List(PlusEntry.allCases, id: \.self) { entry in
            Button {
                model.plusEntry = entry
            } label: {
                HStack {
                    Label(entry.title, systemImage: entry.symbol)
                        .foregroundStyle(entry.isDestructive ? Color.red : Color.primary)
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .navigationTitle("Plus")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { AccountMenuButton() }
        }
    }
}

/// The screen behind a Plus entry: the built screen, or a placeholder until the owning lot (`PlusEntry.owningLot`) brings it.
struct PlusEntryView: View {
    let entry: PlusEntry

    var body: some View {
        if entry.isBuilt {
            SettingsView(rotationChanged: { OrientationPolicy.refresh() })
        } else {
            ContentUnavailableView(
                entry.title, systemImage: entry.symbol,
                description: Text("Cet écran arrive dans une prochaine version.")
            )
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
