import Foundation
import Testing
@testable import HFRStorage

/// LOT-140: the "Vérifier les messages" choice (operator, 2026-11-07 on #230).
@Suite("MP check interval")
struct MPCheckIntervalTests {
    @Test("The choices are 15 min, 30 min, 1 h, 2 h, 4 h and Jamais, stored in minutes, 0 for Jamais")
    func choices() {
        #expect(MPCheckInterval.allCases.map(\.rawValue) == [15, 30, 60, 120, 240, 0])
        #expect(MPCheckInterval.allCases.map(\.seconds) == [900, 1800, 3600, 7200, 14_400, nil])
    }

    @Test("Absent, 30 minutes; a stored choice reads back; an unknown or unreadable value reads as 30 minutes")
    func storage() {
        let store = InMemorySettingsStore()
        #expect(SettingKey.mpCheckInterval.key == "mp_check_interval")
        #expect(store.value(for: SettingKey.mpCheckInterval) == .thirtyMinutes)
        store.set(.never, for: SettingKey.mpCheckInterval)
        #expect(store.rawValue(forKey: "mp_check_interval") == .int(0))
        #expect(store.value(for: SettingKey.mpCheckInterval) == .never)
        store.setRawValue(.int(45), forKey: "mp_check_interval")
        #expect(store.value(for: SettingKey.mpCheckInterval) == .thirtyMinutes)
        store.setRawValue(.string("souvent"), forKey: "mp_check_interval")
        #expect(store.value(for: SettingKey.mpCheckInterval) == .thirtyMinutes)
    }
}
