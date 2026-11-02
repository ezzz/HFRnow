#if canImport(Darwin)
import Foundation

/// The iCloud key-value store (`NSUbiquitousKeyValueStore.default`), Apple platforms only: the class is not in
/// swift-corelibs-foundation (ADR 0013 §9). Needs the app's key-value storage entitlement (LOT-160); without it, or
/// without an iCloud account, the system keeps the values on the device only.
public final class UbiquitousKeyValueStore: SyncedKeyValueStore, @unchecked Sendable {
    // NSUbiquitousKeyValueStore is documented as thread-safe; this wrapper holds no other state.
    private let store: NSUbiquitousKeyValueStore

    /// Creates a store over the app's default iCloud key-value store.
    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    public func value(forKey key: String) -> SyncedValue? {
        switch store.object(forKey: key) {
        case let text as String: return .string(text)
        case let data as Data: return .data(data)
        case let number as NSNumber:
            switch String(cString: number.objCType) {
            case "c", "B": return .bool(number.boolValue)
            case "d", "f": return .double(number.doubleValue)
            default: return .int(number.intValue)
            }
        default: return nil
        }
    }

    public func set(_ value: SyncedValue, forKey key: String) {
        switch value {
        case .bool(let flag): store.set(flag, forKey: key)
        case .int(let number): store.set(Int64(number), forKey: key)
        case .double(let number): store.set(number, forKey: key)
        case .string(let text): store.set(text, forKey: key)
        case .data(let data): store.set(data, forKey: key)
        }
    }

    public func removeValue(forKey key: String) {
        store.removeObject(forKey: key)
    }

    @discardableResult
    public func synchronize() -> Bool {
        store.synchronize()
    }

    /// The archived `ubiquityIdentityToken`, base64: Apple's way to remember the account across launches. Nil without an
    /// account, or when the token cannot be archived (then an account change is seen as a sign-out).
    public func accountIdentity() -> String? {
        FileManager.default.ubiquityIdentityToken.flatMap(Self.archive)?.base64EncodedString()
    }

    /// Compares the stored token with the current one with `isEqual(_:)`, as Apple asks, falling back to the archives'
    /// bytes when the stored one cannot be decoded.
    public func isCurrentAccount(_ identity: String?) -> Bool {
        let current = FileManager.default.ubiquityIdentityToken
        guard let identity, let data = Data(base64Encoded: identity) else { return identity == nil && current == nil }
        guard let current else { return false }
        if let stored = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSObject.self], from: data) as? NSObject {
            return stored.isEqual(current)
        }
        return Self.archive(current) == data
    }

    private static func archive(_ token: any NSCoding & NSCopying & NSObjectProtocol) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    public func changes() -> AsyncStream<SyncedStoreChange> {
        AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: nil
            ) { notification in
                continuation.yield(Self.change(from: notification.userInfo))
            }
            let token = ObserverToken(observer)
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(token.observer) }
        }
    }

    private static func change(from userInfo: [AnyHashable: Any]?) -> SyncedStoreChange {
        let keys = userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        let reason: SyncedStoreChange.Reason
        switch userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int {
        case NSUbiquitousKeyValueStoreInitialSyncChange: reason = .initialSync
        case NSUbiquitousKeyValueStoreQuotaViolationChange: reason = .quotaViolation
        case NSUbiquitousKeyValueStoreAccountChange: reason = .accountChange
        default: reason = .serverChange
        }
        return SyncedStoreChange(reason: reason, keys: keys)
    }

    /// Carries the observer token into the `@Sendable` termination handler.
    private final class ObserverToken: @unchecked Sendable {
        // Written once at init, only read afterwards.
        let observer: any NSObjectProtocol
        init(_ observer: any NSObjectProtocol) { self.observer = observer }
    }
}
#endif
