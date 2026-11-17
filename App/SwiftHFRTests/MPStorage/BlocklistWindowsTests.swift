import HFRNetwork
@testable import SwiftHFR
import Testing

/// The app's wiring of LOT-131 across windows (LOT-146): each window builds its own `AppEnvironment`, and the held blocklist
/// changes must be the account's, not the window's.
struct BlocklistWindowsTests {
    @Test func twoWindowsOfOneAccountShareTheirHeldChanges() throws {
        let first = AppEnvironment.make(session: HFRSession(), accountName: "WindowsWiringTest")
        let second = AppEnvironment.make(session: HFRSession(), accountName: "windowswiringtest")
        let other = AppEnvironment.make(session: HFRSession(), accountName: "OtherWindowsWiringTest")
        let change = BlocklistChange(pseudo: "Alpha", added: false)
        let log = try #require(first.blocklistChanges)
        log.hold(change)
        defer { log.withdraw([change]) }
        #expect(second.blocklistChanges?.pending == [change])
        #expect(other.blocklistChanges?.pending == [])
    }

    @Test func loggedOutThereIsNoLog() {
        #expect(AppEnvironment.make(session: HFRSession(), accountName: nil).blocklistChanges == nil)
    }
}
