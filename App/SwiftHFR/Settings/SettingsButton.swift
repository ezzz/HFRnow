import SwiftUI

/// Toolbar entry to the settings screen, shown as a sheet so it works the same in every column of the split view.
struct SettingsButton: View {
    @State private var showsSettings = false

    var body: some View {
        Button("Réglages", systemImage: "gearshape") { showsSettings = true }
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    SettingsView(rotationChanged: { OrientationPolicy.refresh() })
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("OK") { showsSettings = false }
                            }
                        }
                }
            }
    }
}
