import Foundation
@testable import HFRStorage

/// A cache rooted in a fresh temporary directory, removed by `cleanUp()`.
struct TemporaryCache {
    let cache: CacheDirectory
    let base: URL

    init() throws {
        base = URL.temporaryDirectory.appending(path: "Caches-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cache = CacheDirectory(root: base.appending(path: "cache", directoryHint: .isDirectory))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: base)
    }

    /// Writes a file of `size` bytes whose modification date is `age` seconds before `now`.
    @discardableResult
    func makeFile(_ name: String, in area: CacheArea, size: Int = 10, age: TimeInterval, now: Date) throws -> URL {
        let directory = try cache.prepare(area)
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        try Data(repeating: 0x41, count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path())
        return url
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
