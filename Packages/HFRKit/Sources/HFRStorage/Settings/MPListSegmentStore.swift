import HFRModels

/// The last Messages switch position of each account (#899), one key per account in the app's settings store:
/// `mp_list_segment.<account key>` (`AccountKey`, as `MPStorageSyncStateStore` keys `mpstorage.<account key>`). Device-only
/// UI state, like `HFRswiftGlobalTopicListFlag`: never registered with `syncKeys(_:)`.
public struct MPListSegmentStore: Sendable {
    /// The prefix of every key.
    public static let keyPrefix = "mp_list_segment."

    private let settings: any SettingsStore

    /// Creates the store over `settings`.
    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    /// The key of `account`, nil for an empty account key.
    public static func key(for account: String) -> String? {
        let accountKey = AccountKey.make(account)
        return accountKey.isEmpty ? nil : keyPrefix + accountKey
    }

    /// The position to show for `account`: the stored one (an unknown value reads as Tous), else seeded from the retired
    /// `mp_list_display` (« Tout en un » is Tous, « Deux listes » is MP). Tous without an account (logged out).
    public func segment(for account: String?) -> MPSegment {
        guard let account, let key = Self.key(for: account) else { return .all }
        guard let raw = settings.rawValue(forKey: key) else {
            return settings.value(for: SettingKey.mpListDisplay) == .split ? .oneToOne : .all
        }
        return SettingCoercion.string(raw).flatMap(MPSegment.init(rawValue:)) ?? .all
    }

    /// Stores `segment` for `account`; nothing for an empty account key.
    public func set(_ segment: MPSegment, for account: String) {
        guard let key = Self.key(for: account) else { return }
        settings.setRawValue(.string(segment.rawValue), forKey: key)
    }
}
