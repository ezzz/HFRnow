import Observation
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (maintenanceSection, refreshCacheStorage, openSystemSettings) @ 87fe0d1c.
// Differences: the footer states SwiftHFR's own purge rule (1 jour, 20 Mo, LOT-066); "fichier" is singular below two;
// cache clearing is LOT-187 (GAP-152, LOT-120 and LOT-179 specs).
/// Logic of Réglages > Maintenance: the shortcut to the system settings of the app (LOT-120) and the cache sizes (LOT-179).
@Observable @MainActor
final class MaintenanceModel {
    /// The measured sizes; nil until the first measure ends (the section shows a spinner).
    private(set) var cacheStorage: CacheStorageSnapshot?

    private let openSettings: @MainActor () -> Void
    private let measureCaches: @Sendable () -> CacheStorageSnapshot
    private var latestMeasure = 0

    /// A model whose shortcut runs `openSettings` (default: the app's page of the system Settings) and whose sizes come from
    /// `measureCaches` (default: the app's caches).
    init(
        openSettings: (@MainActor () -> Void)? = nil,
        measureCaches: @escaping @Sendable () -> CacheStorageSnapshot = CacheStorageSnapshot.measureStandard
    ) {
        self.openSettings = openSettings ?? { Self.openSystemSettingsPage() }
        self.measureCaches = measureCaches
    }

    /// Measures the caches off the main actor. When two measures overlap, only the one started last is kept.
    func refreshCacheStorage() async {
        latestMeasure += 1
        let ticket = latestMeasure
        let measure = measureCaches
        let snapshot = await Task.detached(priority: .utility) { measure() }.value
        guard ticket == latestMeasure else { return }
        cacheStorage = snapshot
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

/// The "Maintenance" section of Réglages: the cache sizes (a spinner until measured), the shortcut and the purge rule.
struct MaintenanceSection: View {
    let model: MaintenanceModel

    var body: some View {
        Section {
            CacheRows(snapshot: model.cacheStorage)
            Button("Ouvrir les réglages système") { model.openSystemSettings() }
        } header: {
            Text("Maintenance")
        } footer: {
            Text(CacheStorageText.purgeRule())
        }
        .task { await model.refreshCacheStorage() }
    }
}

/// "Caches de l’app" and "Pages HTML" (with the file count), or a spinner while the sizes are measured.
private struct CacheRows: View {
    let snapshot: CacheStorageSnapshot?

    var body: some View {
        if let snapshot {
            LabeledContent("Caches de l’app", value: CacheStorageText.size(snapshot.totalBytes))
            LabeledContent {
                Text(CacheStorageText.size(snapshot.htmlBytes))
            } label: {
                VStack(alignment: .leading) {
                    Text("Pages HTML")
                    Text(CacheStorageText.fileCount(snapshot.htmlFileCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            LabeledContent("Caches de l’app") { ProgressView() }
        }
    }
}
