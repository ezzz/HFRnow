//
//  HTMLPageCacheManager.swift
//  HFRswift
//

import Foundation

struct AppCacheStorageSnapshot: Sendable {
    let totalBytes: Int64
    let htmlBytes: Int64
    let htmlFileCount: Int
}

struct HTMLPageCacheCleanupResult: Sendable {
    let removedFileCount: Int
    let removedBytes: Int64
}

@objcMembers
final class HFRHTMLPageCacheManager: NSObject {
    nonisolated static let maximumAge: TimeInterval = 7 * 24 * 60 * 60
    nonisolated static let maximumSize: Int64 = 50 * 1_000_000

    private struct CachedFile {
        let url: URL
        let modificationDate: Date
        let allocatedSize: Int64
    }

    nonisolated class func performAutomaticCleanup() {
        guard let directory = htmlCacheDirectory() else { return }
        _ = cleanup(
            directory: directory,
            maximumAge: maximumAge,
            maximumSize: maximumSize
        )
    }

    nonisolated static func storageSnapshot(fileManager: FileManager = .default) -> AppCacheStorageSnapshot {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return AppCacheStorageSnapshot(totalBytes: 0, htmlBytes: 0, htmlFileCount: 0)
        }

        let totalBytes = directoryAllocatedSize(at: cachesDirectory, fileManager: fileManager)
        let htmlFiles = cachedHTMLFiles(
            in: cachesDirectory.appendingPathComponent("cache", isDirectory: true),
            fileManager: fileManager
        )

        return AppCacheStorageSnapshot(
            totalBytes: totalBytes,
            htmlBytes: htmlFiles.reduce(0) { $0 + $1.allocatedSize },
            htmlFileCount: htmlFiles.count
        )
    }

    @discardableResult
    nonisolated static func cleanup(
        directory: URL,
        maximumAge: TimeInterval,
        maximumSize: Int64,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> HTMLPageCacheCleanupResult {
        let expirationDate = now.addingTimeInterval(-maximumAge)
        var remainingFiles: [CachedFile] = []
        var removedFileCount = 0
        var removedBytes: Int64 = 0

        for file in cachedHTMLFiles(in: directory, fileManager: fileManager) {
            if file.modificationDate < expirationDate,
               (try? fileManager.removeItem(at: file.url)) != nil {
                removedFileCount += 1
                removedBytes += file.allocatedSize
            } else {
                remainingFiles.append(file)
            }
        }

        var currentSize = remainingFiles.reduce(0) { $0 + $1.allocatedSize }
        guard maximumSize >= 0, currentSize > maximumSize else {
            return HTMLPageCacheCleanupResult(
                removedFileCount: removedFileCount,
                removedBytes: removedBytes
            )
        }

        for file in remainingFiles.sorted(by: { $0.modificationDate < $1.modificationDate }) {
            guard currentSize > maximumSize else { break }
            guard (try? fileManager.removeItem(at: file.url)) != nil else { continue }

            currentSize -= file.allocatedSize
            removedFileCount += 1
            removedBytes += file.allocatedSize
        }

        return HTMLPageCacheCleanupResult(
            removedFileCount: removedFileCount,
            removedBytes: removedBytes
        )
    }

    nonisolated private class func htmlCacheDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("cache", isDirectory: true)
    }

    nonisolated private static func cachedHTMLFiles(
        in directory: URL,
        fileManager: FileManager
    ) -> [CachedFile] {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let URLs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return URLs.compactMap { url in
            guard url.lastPathComponent.hasPrefix("topic-"),
                  url.pathExtension.lowercased() == "htm",
                  let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                return nil
            }

            return CachedFile(
                url: url,
                modificationDate: values.contentModificationDate ?? .distantPast,
                allocatedSize: Int64(
                    values.totalFileAllocatedSize
                        ?? values.fileAllocatedSize
                        ?? values.fileSize
                        ?? 0
                )
            )
        }
    }

    nonisolated private static func directoryAllocatedSize(at directory: URL, fileManager: FileManager) -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalBytes: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                continue
            }
            totalBytes += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
        }
        return totalBytes
    }
}
