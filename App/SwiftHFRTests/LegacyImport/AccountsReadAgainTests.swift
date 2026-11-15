import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-158: accounts the legacy import writes while the launch restore runs are listed once the store is read again.
@MainActor
struct AccountsReadAgainTests {
    @Test func anAccountWrittenDuringTheRestoreIsListedAfterReadingAgain() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let gate = CheckGate()
        let model = makeModel(store: store, checker: ScriptedChecker([:], gate: gate))
        let restoring = gate.run { await model.restore() }
        try #require(await gate.entered(), "the launch check never reached the gate")
        // The import writes an account after the restore read the store (the `onChange` of that restore's own publish).
        _ = try store.save(Fake.account("user2"), makeMain: false)
        let reading = Task { await model.readStoreAgain() }
        await gate.open()
        await restoring.value
        await reading.value
        #expect(model.rows.map(\.id) == ["user1", "user2"])
    }
}
