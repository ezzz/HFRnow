import SwiftUI

/// The Plus tab: the legacy menu (`PlusTab.swift:11-60`), one row per entry in legacy order.
struct PlusView: View {
    var body: some View {
        List(PlusEntry.allCases, id: \.self) { entry in
            NavigationLink(value: entry) {
                Label(entry.title, systemImage: entry.symbol)
                    .foregroundStyle(entry.isDestructive ? Color.red : Color.primary)
            }
        }
        .navigationTitle("Plus")
        .navigationDestination(for: PlusEntry.self) { PlusEntryView(entry: $0) }
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
