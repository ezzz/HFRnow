import Observation
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (maintenanceSection, openSystemSettings) @ 87fe0d1c. Differences: the cache rows
// and the purge rule come with LOT-179; cache clearing is LOT-187 (GAP-152, LOT-120 spec).
/// Logic of Réglages > Maintenance (LOT-120): the shortcut to the system settings of the app. LOT-179 adds the cache sizes here.
@Observable @MainActor
final class MaintenanceModel {
    private let openSettings: @MainActor () -> Void

    /// A model whose shortcut runs `openSettings` (default: the app's page of the system Settings).
    init(openSettings: (@MainActor () -> Void)? = nil) {
        self.openSettings = openSettings ?? { Self.openSystemSettingsPage() }
    }

    /// "Ouvrir les réglages système".
    func openSystemSettings() {
        openSettings()
    }

    /// Opens the app's page in the system Settings (`UIApplication.openSettingsURLString`, legacy `:299-302`).
    private static func openSystemSettingsPage() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// The "Maintenance" section of Réglages. LOT-179 fills `cacheRows` (above the shortcut) and adds the footer; the shortcut
/// stays as it is.
struct MaintenanceSection: View {
    let model: MaintenanceModel

    var body: some View {
        Section("Maintenance") {
            cacheRows
            Button("Ouvrir les réglages système") { model.openSystemSettings() }
        }
    }

    /// Where LOT-179 puts "Caches de l'app" and "Pages HTML" (empty until then).
    @ViewBuilder private var cacheRows: some View {
        EmptyView()
    }
}
