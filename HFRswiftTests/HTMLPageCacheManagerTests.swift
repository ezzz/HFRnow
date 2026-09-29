import XCTest
@testable import HFRswift

final class HTMLPageCacheManagerTests: XCTestCase {
    func testCleanupRemovesExpiredHTMLAndPreservesOtherFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        let expiredHTML = try makeFile(named: "topic-expired.htm", in: directory, age: 8 * 24 * 60 * 60, now: now)
        let recentHTML = try makeFile(named: "topic-recent.htm", in: directory, age: 60, now: now)
        let unrelatedFile = try makeFile(named: "style-liste.css", in: directory, age: 30 * 24 * 60 * 60, now: now)

        let result = HFRHTMLPageCacheManager.cleanup(
            directory: directory,
            maximumAge: 7 * 24 * 60 * 60,
            maximumSize: .max,
            now: now
        )

        XCTAssertEqual(result.removedFileCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredHTML.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentHTML.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedFile.path))
    }

    func testCleanupRemovesOldestHTMLWhenSizeLimitIsExceeded() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        let oldestHTML = try makeFile(named: "topic-oldest.htm", in: directory, age: 120, now: now, bytes: 8_192)
        let newestHTML = try makeFile(named: "topic-newest.htm", in: directory, age: 60, now: now, bytes: 8_192)
        let newestSize = try allocatedSize(of: newestHTML)

        let result = HFRHTMLPageCacheManager.cleanup(
            directory: directory,
            maximumAge: 100 * 365 * 24 * 60 * 60,
            maximumSize: newestSize,
            now: now
        )

        XCTAssertEqual(result.removedFileCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldestHTML.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newestHTML.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HTMLPageCacheManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @discardableResult
    private func makeFile(
        named name: String,
        in directory: URL,
        age: TimeInterval,
        now: Date,
        bytes: Int = 128
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-age)],
            ofItemAtPath: url.path
        )
        return url
    }

    private func allocatedSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ])
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}
