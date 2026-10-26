import Foundation

/// Applies a `CacheEvictionPolicy` to a folder, recursively. It only removes regular files, never folders or symbolic links.
public enum CacheEvictor {
    private struct Item {
        let url: URL
        let modified: Date
        let size: Int
    }

    /// Evicts files of `directory` according to `policy`; `now` is injectable for tests.
    /// A missing directory is an empty cache. Files that cannot be removed are reported, not retried.
    @discardableResult
    public static func evict(directory: URL, policy: CacheEvictionPolicy, now: Date = .now) -> CacheEvictionReport {
        evict(directory: directory, policy: policy, now: now, removeFile: { try FileManager.default.removeItem(at: $0) })
    }

    /// The eviction pass with an injectable remover, so tests can make removals fail.
    static func evict(
        directory: URL,
        policy: CacheEvictionPolicy,
        now: Date,
        removeFile: (URL) throws -> Void
    ) -> CacheEvictionReport {
        var report = CacheEvictionReport()
        var items = list(directory, report: &report)
        // Bytes of expired files that could not be removed still occupy the cache, so the size bound counts them.
        var stuckBytes = 0

        if policy.removesEverything || policy.maximumAge != nil {
            let (expired, fresh) = items.partitioned(by: {
                policy.removesEverything || now.timeIntervalSince($0.modified) > (policy.maximumAge ?? .infinity)
            })
            items = fresh
            for item in expired where !remove(item, using: removeFile, report: &report) { stuckBytes += item.size }
        }

        if let maximumBytes = policy.maximumTotalBytes {
            var total = stuckBytes + items.reduce(0) { $0 + $1.size }
            // Oldest first; the path breaks ties so the outcome is deterministic.
            let oldestFirst = items.sorted { ($0.modified, $0.url.path()) < ($1.modified, $1.url.path()) }
            for item in oldestFirst where total > maximumBytes {
                if remove(item, using: removeFile, report: &report) { total -= item.size }
            }
        }

        var listingFailures = CacheEvictionReport()
        report.remainingBytes = list(directory, report: &listingFailures).reduce(0) { $0 + $1.size }
        return report
    }

    /// Total size in bytes of the regular files under `directory`.
    public static func totalBytes(in directory: URL) -> Int {
        var ignored = CacheEvictionReport()
        return list(directory, report: &ignored).reduce(0) { $0 + $1.size }
    }

    @discardableResult
    private static func remove(_ item: Item, using removeFile: (URL) throws -> Void, report: inout CacheEvictionReport) -> Bool {
        do {
            try removeFile(item.url)
            report.removedFileCount += 1
            report.removedBytes += item.size
            return true
        } catch {
            report.failures.append("\(item.url.lastPathComponent): \(error)")
            return false
        }
    }

    private static func list(_ directory: URL, report: inout CacheEvictionReport) -> [Item] {
        // A cache folder that is a link could lead outside the cache: Foundation platforms differ on following it.
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            report.failures.append("\(directory.lastPathComponent): is a symbolic link, ignored")
            return []
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        var pending = [directory]
        var items: [Item] = []
        while let current = pending.popLast() {
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: keys)
            } catch {
                if FileManager.default.fileExists(atPath: current.path(percentEncoded: false)) {
                    report.failures.append("\(current.lastPathComponent): \(error)")
                }
                continue
            }
            for child in children {
                guard let values = try? child.resourceValues(forKeys: Set(keys)) else {
                    report.failures.append("\(child.lastPathComponent): attributes unreadable")
                    continue
                }
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true {
                    pending.append(child)
                } else if values.isRegularFile == true {
                    items.append(Item(url: child, modified: values.contentModificationDate ?? .distantPast, size: values.fileSize ?? 0))
                }
            }
        }
        return items
    }
}

private extension Array {
    /// Splits the elements in one pass: those matching `predicate` first, the others second.
    func partitioned(by predicate: (Element) -> Bool) -> ([Element], [Element]) {
        var matching: [Element] = []
        var others: [Element] = []
        for element in self {
            if predicate(element) { matching.append(element) } else { others.append(element) }
        }
        return (matching, others)
    }
}
