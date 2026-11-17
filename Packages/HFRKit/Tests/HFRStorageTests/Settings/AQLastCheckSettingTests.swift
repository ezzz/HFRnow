import Foundation
import Testing
@testable import HFRStorage

/// `last_check_aq` (LOT-133): the Alertes Qualitay "new since" instant.
@Suite struct AQLastCheckSettingTests {
    @Test func aqLastCheckKeepsTheLegacyKeyAndRoundTripsAnInstant() {
        let store = InMemorySettingsStore()
        #expect(SettingKey.aqLastCheck.key == "last_check_aq")
        #expect(store.value(for: SettingKey.aqLastCheck) == nil)
        let date = Date(timeIntervalSince1970: 1_761_000_000.25)
        store.set(date, for: SettingKey.aqLastCheck)
        #expect(store.value(for: SettingKey.aqLastCheck) == date)
        #expect(!SettingKey.syncedKeys.contains("last_check_aq"))
        // A non-finite or unusable stored value reads as "never checked", never as a date.
        for raw in [SettingRawValue.string("yesterday"), .double(.nan), .double(.infinity)] {
            let broken = InMemorySettingsStore(["last_check_aq": raw])
            #expect(broken.value(for: SettingKey.aqLastCheck) == nil)
        }
    }
}
