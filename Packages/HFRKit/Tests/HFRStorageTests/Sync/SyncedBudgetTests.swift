import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The worst case of ADR 0013's budget, measured as the stores encode it (LOT-172, ADR 0013 Amendment 2): five
/// accounts, 100 allowlist entries, per account 200 super-favourites, 100 smiley favourites and 200 positions, the
/// synced settings, the schema version and one MPStorage sync-state key per account.
@Suite struct SyncedBudgetTests {
    static let accounts = (1...5).map { "pseudo-numero-\($0)" }
    /// Fractional seconds, as `Date()` gives: the longest date encoding.
    static func date(_ index: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_000_000.123_456 + Double(index) * 37.000_123)
    }

    static func size(_ value: SyncedValue) -> Int {
        switch value {
        case .data(let data): data.count
        case .string(let text): text.utf8.count
        case .bool, .int, .double: 8
        }
    }

    @Test func theWorstCaseStaysUnderTheMeasuredBound() throws {
        var values: [String: Int] = [:]
        // Scalar settings: ADR 0013 allows each up to 100 bytes.
        for key in SettingKey.syncedKeys { values[key] = 100 }
        values[SyncedSettingsStore.schemaVersionKey] = 8
        for account in Self.accounts { values["mpstorage.\(account)"] = 64 }

        let allowlist = (1...100).map { PseudoListEntry(pseudo: "Membre-ami-\($0)-xx") }
        values[SyncedListsStore.allowlistKey] = Self.size(SyncedListEnvelope(items: allowlist).value)
        for account in Self.accounts {
            let superFavorites = (1...200).map {
                SuperFavorite(topic: TopicID(category: .forum(13), topic: 1_000_000 + $0), addedAt: Self.date($0))
            }
            let url = try #require(URL(string: "https://forum-images.hardware.fr/images/perso/3/smiley-avec-un-nom-long.gif"))
            let smileys = (1...100).map { AppSmileyFavorite(code: "[:smiley-avec-un-nom-long-\($0):3]", url: url, addedAt: Self.date($0)) }
            let positions = (1...200).map {
                ReadingPositionRecord(
                    topic: TopicID(category: .forum(13), topic: 1_000_000 + $0),
                    position: ReadingPosition(page: 900 + $0, messageNumber: 123_456_789, offset: 4_096, updatedAt: Self.date($0))
                )
            }
            values["superfavorites.\(account)"] = Self.size(SyncedListEnvelope(items: superFavorites).value)
            values["smileyfavorites.\(account)"] = Self.size(SyncedListEnvelope(items: smileys).value)
            values["positions.\(account)"] = Self.size(SyncedListEnvelope(items: positions).value)
        }

        let total = values.reduce(0) { $0 + $1.key.utf8.count + $1.value }
        #expect(values.count <= 60, "\(values.count) keys")
        #expect(total < 320 * 1024, "\(total) bytes")
        // Apple's limits, for the record: 1024 keys, 1 MB in all.
        #expect(total < 1024 * 1024)
    }
}
