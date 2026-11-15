import Foundation
import HFRModels
import OSLog

extension ThemeCatalog {
    /// The themes bundled with the app (LOT-188): every `<id>.theme.json` of `App/SwiftHFR/Themes/<id>/`. Xcode copies a
    /// folder-synchronized group's resources flat into the bundle (ADR 0012), so each file is named after its theme, never
    /// `theme.json`. Read once; a file that cannot be read or decoded is left out and logged (the HFRKit test fails on it first).
    static let bundled: ThemeCatalog = {
        let logger = Logger(subsystem: "SwiftHFR", category: "themes")
        let urls = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".theme.json") }
        var files: [(source: String, data: Data)] = []
        for url in urls {
            do {
                files.append((url.lastPathComponent, try Data(contentsOf: url)))
            } catch {
                let reason = String(describing: error)
                logger.error("Theme file unreadable: \(url.lastPathComponent, privacy: .public): \(reason, privacy: .public)")
            }
        }
        let catalog = ThemeCatalog(files: files)
        for rejection in catalog.rejections {
            logger.error("Theme left out: \(rejection.description, privacy: .public)")
        }
        return catalog
    }()
}
