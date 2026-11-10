import Foundation
import Synchronization

/// One secret blob in the Keychain (or a test double): read whole, written whole. LOT-173 uses two: the synchronizable
/// copy of the accounts and this device's sync state.
public protocol SecureDataItem: Sendable {
    /// The stored bytes; nil when the item does not exist.
    func read() throws -> Data?
    /// Replaces the stored bytes, creating the item when missing.
    func write(_ data: Data) throws
}

/// Who may read a Keychain item and whether iCloud Keychain carries it: the platform-independent half of an item's
/// attributes, so the choice is tested on every platform (`KeychainDataItem` maps it to `kSecAttr…`).
public struct KeychainItemDescriptor: Sendable, Hashable {
    /// The accessibility classes LOT-065 and LOT-173 use.
    public enum Accessibility: Sendable, Hashable {
        /// `kSecAttrAccessibleAfterFirstUnlock`: readable while locked after the first unlock; may sync.
        case afterFirstUnlock
        /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: same, never leaves the device (no sync, no backup restore
        /// to another device).
        case afterFirstUnlockThisDeviceOnly
    }

    /// `kSecAttrAccount`.
    public let accountName: String
    /// `kSecAttrAccessible`.
    public let accessibility: Accessibility
    /// `kSecAttrSynchronizable`.
    public let isSynchronizable: Bool

    /// The synchronizable copy of the accounts: `AfterFirstUnlock`, since a `ThisDeviceOnly` class cannot sync (ADR 0013 §6).
    public static let syncedAccounts = KeychainItemDescriptor(
        accountName: "hfr.accounts.sync.v1", accessibility: .afterFirstUnlock, isSynchronizable: true
    )
    /// This device's sync state: device only, like the accounts item of LOT-065.
    public static let syncState = KeychainItemDescriptor(
        accountName: "hfr.accounts.sync-state.v1", accessibility: .afterFirstUnlockThisDeviceOnly, isSynchronizable: false
    )
}

/// A `SecureDataItem` in memory, for tests and previews. Two simulated devices share one instance as their synchronizable
/// item; `beforeWrite` lets a test land another device's write between a read and a write.
public final class InMemorySecureDataItem: SecureDataItem {
    private let storage: Mutex<Data?>
    private let hook: Mutex<(@Sendable () -> Void)?> = Mutex(nil)
    private let readHook: Mutex<(@Sendable () -> Void)?> = Mutex(nil)
    private let writes = Mutex(0)

    /// Creates an item holding `data`, or nothing.
    public init(data: Data? = nil) {
        storage = Mutex(data)
    }

    /// The stored bytes; tests plant and inspect them.
    public var data: Data? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    /// How many writes reached the item.
    public var writeCount: Int { writes.withLock { $0 } }

    /// Runs once, before the next write, outside the item's lock.
    public func beforeNextWrite(_ body: @escaping @Sendable () -> Void) {
        hook.withLock { $0 = body }
    }

    /// Runs once, right after the next read returned, outside the item's lock.
    public func afterNextRead(_ body: @escaping @Sendable () -> Void) {
        readHook.withLock { $0 = body }
    }

    /// The stored bytes.
    public func read() throws -> Data? {
        let data = storage.withLock { $0 }
        let pending = readHook.withLock { hook in
            defer { hook = nil }
            return hook
        }
        pending?()
        return data
    }

    /// Replaces the stored bytes.
    public func write(_ data: Data) throws {
        let pending = hook.withLock { hook in
            defer { hook = nil }
            return hook
        }
        pending?()
        storage.withLock { $0 = data }
        writes.withLock { $0 += 1 }
    }
}
