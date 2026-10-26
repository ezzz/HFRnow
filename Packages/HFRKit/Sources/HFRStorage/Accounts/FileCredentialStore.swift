import Foundation
import HFRModels
import Synchronization
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// A store that keeps the envelope in one file, for Linux and tests. On a device use `KeychainCredentialStore`:
/// a file is only as private as its directory and its backups. The file is written atomically with owner-only
/// permissions (and, on Apple platforms, complete-until-first-authentication protection).
public final class FileCredentialStore: CredentialStore {
    /// The envelope file.
    public let fileURL: URL
    private let lock = Mutex(())

    /// Creates a store for `fileURL`; the directory is created on first write.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The stored accounts; empty when the file does not exist.
    public func load() throws -> AccountBook {
        try lock.withLock { _ in try read() }
    }

    /// Read-modify-write under this instance's lock; two instances on the same file are not serialized.
    public func update<Value>(_ body: (inout AccountBook) throws -> Value) throws -> Value {
        try lock.withLock { _ in
            var book = try read()
            let original = book
            let value = try body(&book)
            if book != original { try write(CredentialEnvelope.encode(book)) }
            return value
        }
    }

    /// Deletes the file and any temporary copy a crash left behind; no error when they do not exist.
    public func removeAll() throws {
        try lock.withLock { _ in
            try sweepTemporaries()
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                return
            }
        }
    }

    private func read() throws -> AccountBook {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // Apple platforms report the first code, swift-corelibs-foundation the second.
            return AccountBook()
        }
        return try CredentialEnvelope.decode(data)
    }

    /// Writes a sibling temporary file created owner-only, then renames it over the envelope.
    private func write(_ data: Data) throws {
        let directory = fileURL.deletingLastPathComponent()
        // Directories this store creates are owner-only; an existing directory keeps its permissions.
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try sweepTemporaries()
        let temporary = directory.appending(path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        let temporaryPath = temporary.path(percentEncoded: false)
        do {
            try writeOwnerOnly(data, to: temporaryPath)
            // rename(2) replaces atomically; swift-corelibs-foundation's replaceItemAt fails with ENOENT on Linux.
            guard rename(temporaryPath, fileURL.path(percentEncoded: false)) == 0 else { throw Self.posixError() }
        } catch {
            // Best-effort cleanup of the temporary copy: the failure above is the error to report.
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Removes `.<name>.<uuid>.tmp` siblings: a crash between writing and renaming leaves one, holding credentials.
    private func sweepTemporaries() throws {
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let names: [String]
        do {
            names = try manager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return
        }
        let prefix = ".\(fileURL.lastPathComponent).", suffix = ".tmp"
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(suffix) {
            // Only what `write` creates: a UUID in the middle and a regular file (never a directory, which
            // removeItem would delete recursively).
            let middle = name.dropFirst(prefix.count).dropLast(suffix.count)
            guard name.count > prefix.count + suffix.count, UUID(uuidString: String(middle)) != nil else { continue }
            let path = directory.appending(path: name)
            do {
                let type = try manager.attributesOfItem(atPath: path.path(percentEncoded: false))[.type] as? FileAttributeType
                guard type == .typeRegular else { continue }
                try manager.removeItem(at: path)
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                continue
            }
        }
    }

    /// Creates `path` exclusively with mode 0600 before any byte is written (FileManager.createFile writes the
    /// data first and applies the permissions afterwards), then writes and syncs the data.
    private func writeOwnerOnly(_ data: Data, to path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw Self.posixError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path
        )
        #endif
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
