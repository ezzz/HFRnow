@testable import SwiftHFR
import Testing

@MainActor
struct MaintenanceModelTests {
    @Test func theShortcutOpensTheSystemSettingsOncePerTap() {
        var opened = 0
        let model = MaintenanceModel(openSettings: { opened += 1 })
        #expect(opened == 0)
        model.openSystemSettings()
        #expect(opened == 1)
        model.openSystemSettings()
        #expect(opened == 2)
    }

    @Test func creatingTheModelOpensNothing() {
        var opened = 0
        _ = MaintenanceModel(openSettings: { opened += 1 })
        #expect(opened == 0)
    }
}
