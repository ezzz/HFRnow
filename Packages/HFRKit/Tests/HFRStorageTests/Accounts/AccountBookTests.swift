import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// Fake credentials only: these values are not real session cookies. The first cookie carries `cookie`,
/// `md_user` names the pseudo as HFR sets it.
func makeAccount(_ pseudo: String, cookie: String = "fake-cookie", hash: String? = nil, main: Bool = false) -> Account {
    Account(
        pseudo: pseudo,
        cookies: [
            StoredCookie(name: "session", value: cookie, domain: ".hardware.fr"),
            StoredCookie(name: "md_user", value: pseudo, domain: ".hardware.fr")
        ],
        hashCheck: hash,
        isMain: main
    )
}

@Suite struct AccountBookTests {
    @Test func theFirstAccountIsMain() throws {
        var book = AccountBook()
        try book.add(makeAccount("alice"), makeMain: false)
        #expect(book.main?.pseudo == "alice")
    }

    @Test func addingMakesMainByDefaultAndOnlyOneIsMain() throws {
        var book = AccountBook()
        try book.add(makeAccount("alice"))
        try book.add(makeAccount("bob"))
        #expect(book.main?.pseudo == "bob")
        #expect(book.accounts.filter(\.isMain).count == 1)
        try book.add(makeAccount("carol"), makeMain: false)
        #expect(book.main?.pseudo == "bob")
        #expect(book.accounts.map(\.pseudo) == ["alice", "bob", "carol"])
    }

    @Test func reAddingTheSamePseudoRefreshesCredentialsInPlace() throws {
        var book = AccountBook()
        try book.add(makeAccount("Alice", cookie: "old", hash: "h1"))
        try book.add(makeAccount("bob"))
        let stored = try book.add(makeAccount(" alice ", cookie: "new"), makeMain: false)

        #expect(book.accounts.count == 2)
        #expect(stored.pseudo == "Alice")
        #expect(stored.cookies.first?.value == "new")
        // A login that did not expose a token keeps the stored one.
        #expect(stored.hashCheck == "h1")
        #expect(book.main?.pseudo == "bob")
    }

    @Test(arguments: ["", "   ", "deleted", " DELETED ", "Deleted"])
    func invalidPseudosAreRefused(pseudo: String) {
        var book = AccountBook()
        #expect(throws: CredentialStoreError.invalidPseudo) { try book.add(makeAccount(pseudo)) }
        #expect(book.accounts.isEmpty)
    }

    @Test func deletingTheMainAccountPromotesTheFirstRemaining() throws {
        var book = AccountBook()
        for pseudo in ["alice", "bob", "carol"] { try book.add(makeAccount(pseudo)) }
        #expect(book.main?.pseudo == "carol")
        let removed = book.remove(pseudo: "CAROL")
        #expect(removed?.pseudo == "carol")
        #expect(book.main?.pseudo == "alice")
    }

    @Test func deletingAnotherAccountKeepsTheMainOne() throws {
        var book = AccountBook()
        for pseudo in ["alice", "bob", "carol"] { try book.add(makeAccount(pseudo)) }
        book.remove(pseudo: "alice")
        #expect(book.main?.pseudo == "carol")
        let missing = book.remove(pseudo: "nobody")
        #expect(missing == nil)
    }

    @Test func deletingTheLastAccountLeavesNoMain() throws {
        var book = AccountBook()
        try book.add(makeAccount("alice"))
        book.remove(pseudo: "alice")
        #expect(book.main == nil && book.accounts.isEmpty)
    }

    @Test func lookupIgnoresCaseAndFallsBackToTheDisplayName() throws {
        var book = AccountBook()
        try book.add(Account(pseudo: "jdupont", displayName: "JeanDupont"))
        #expect(book.account(matching: "JDUPONT")?.pseudo == "jdupont")
        #expect(book.account(matching: "jeandupont")?.pseudo == "jdupont")
        #expect(book.account(matching: "jdupönt") == nil)
        let byDisplayName = book.setMain(pseudo: "JeanDupont")
        let unknown = book.setMain(pseudo: "nobody")
        #expect(byDisplayName && !unknown)
    }

    @Test func diacriticsDistinguishAccounts() throws {
        var book = AccountBook()
        try book.add(makeAccount("Elodie"))
        try book.add(makeAccount("Élodie"))
        #expect(book.accounts.count == 2)
    }

    @Test func loadedBooksAreRepaired() {
        let twoMains = AccountBook(accounts: [makeAccount("a", main: true), makeAccount("b", main: true), makeAccount("A")])
        #expect(twoMains.accounts.map(\.pseudo) == ["a", "b"])
        #expect(twoMains.main?.pseudo == "a")
        let noMain = AccountBook(accounts: [makeAccount("a"), makeAccount("b")])
        #expect(noMain.main?.pseudo == "a")
    }

    @Test func replaceKeepsPseudoAndMainFlag() throws {
        var book = AccountBook()
        try book.add(makeAccount("alice"))
        var changed = makeAccount("ALICE", cookie: "rotated")
        changed.avatarData = Data([1, 2])
        let replaced = book.replace(changed)
        #expect(replaced)
        #expect(book.main?.pseudo == "alice")
        #expect(book.main?.cookies.first?.value == "rotated")
        let absent = book.replace(makeAccount("bob"))
        #expect(!absent)
    }

    @Test func formatCharactersAreStrippedFromPseudos() throws {
        var book = AccountBook()
        let stored = try book.add(makeAccount("\u{200B}alice\u{FEFF}"))
        #expect(stored.pseudo == "alice" && stored.displayName == "alice")
        try book.add(makeAccount("ali\u{200B}ce", cookie: "second"))
        #expect(book.accounts.count == 1)
        #expect(book.account(matching: "\u{FEFF}ALICE")?.cookies.first?.value == "second")
    }

    @Test func theSessionCookieMustNameThePseudo() throws {
        var book = AccountBook()
        var other = makeAccount("alice")
        other.cookies[1].value = "bob"
        #expect(throws: CredentialStoreError.pseudoMismatch) { try book.add(other) }

        var loggedOut = makeAccount("alice")
        loggedOut.cookies[1].value = "deleted"
        #expect(throws: CredentialStoreError.invalidPseudo) { try book.add(loggedOut) }

        var encoded = makeAccount("Jean Dupont")
        encoded.cookies[1].value = "jean%20dupont"
        try book.add(encoded)
        try book.add(Account(pseudo: "carol"))
        #expect(book.accounts.map(\.pseudo) == ["Jean Dupont", "carol"])
    }

    @Test func reLoggingInWithAnotherCaseKeepsTheDisplayName() throws {
        var book = AccountBook()
        try book.add(Account(pseudo: "Alice", displayName: "Alice"))
        let relogged = try book.add(Account(pseudo: "alice"))
        #expect(relogged.displayName == "Alice" && relogged.pseudo == "Alice")
        let renamed = try book.add(Account(pseudo: "alice", displayName: "Alice2"))
        #expect(renamed.displayName == "Alice2")
    }
}
