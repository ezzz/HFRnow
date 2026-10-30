import Testing
@testable import HFRStorage

/// The account key is frozen by ADR 0013 §7: these rows must never change.
@Suite struct AccountKeyTests {
    @Test(
        "U+200B removed, then lower-cased, nothing else",
        arguments: [
            ("User1", "user1"),
            ("user1", "user1"),
            ("Us\u{200B}er1\u{200B}", "user1"),
            ("\u{200B}", ""),
            ("", ""),
            (" User1 ", " user1 "),
            ("ÉTÉ", "été"),
            ("Us\u{200C}er1", "us\u{200C}er1"),
            ("Us\u{FEFF}er1", "us\u{FEFF}er1"),
            ("USER-2", "user-2")
        ]
    )
    func frozenForm(pseudo: String, key: String) {
        #expect(AccountKey.make(pseudo) == key)
    }

    @Test func aWriteRefusesAnEmptyKey() throws {
        #expect(throws: SmallStoreError.emptyAccount) { try AccountKey.forWriting("\u{200B}\u{200B}") }
        #expect(try AccountKey.forWriting("User1") == "user1")
    }
}
