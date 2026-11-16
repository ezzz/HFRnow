import Foundation

/// The rendered topic pages the legacy app left in `Library/Caches/cache` (`Common.swift:2166-2180`,
/// `OfflineStorage.m:500-512`); at `2fe43da3` legacy only removed those older than seven days.
enum LegacyPageCache {
    /// What a clean-up did.
    struct Result: Equatable {
        var removed = 0
        var failed = 0
        /// No `cache` folder (or one that is a link): nothing to do.
        var folderMissing = false
    }

    /// Removes the regular files directly in `<caches>/cache` whose name starts with `topic-` and whose extension is
    /// `htm` in any case, the files legacy's own clean-up selected (`HTMLPageCacheManager.swift:103-130`). Never
    /// follows a link (the caches folder, `cache` and each entry are checked, LESSONS 29), never enters a folder
    /// (`avatars` and LOT-066's areas live there), never removes anything else.
    static func removePages(cachesDirectory: URL) -> Result {
        var result = Result()
        let folder = cachesDirectory.appending(path: "cache", directoryHint: .isDirectory)
        guard !isSymbolicLink(cachesDirectory), !isSymbolicLink(folder), isDirectory(folder),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: folder,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ) else {
            result.folderMissing = true
            return result
        }
        for entry in entries where isLegacyPage(entry.lastPathComponent) {
            guard let values = try? entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            do {
                try FileManager.default.removeItem(at: entry)
                result.removed += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }

    /// `topic-*.htm`, extension in any case.
    static func isLegacyPage(_ name: String) -> Bool {
        guard name.hasPrefix("topic-"), let dot = name.lastIndex(of: ".") else { return false }
        return name[name.index(after: dot)...].lowercased() == "htm"
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder) && isFolder.boolValue
    }
}
