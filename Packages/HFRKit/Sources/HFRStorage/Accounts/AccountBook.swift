import Foundation
import HFRModels

/// The stored accounts and the rules legacy `MultisManager.m:49-153` applied to them: identity by pseudo,
/// exactly one main account whenever there is any, promotion of the first remaining account when the main one
/// is deleted. Pure value; stores persist it as a `CredentialEnvelope`.
public struct AccountBook: Sendable, Hashable {
    /// Accounts in insertion order.
    public private(set) var accounts: [Account]

    /// The main account (whose cookies the shared jar carries); nil only when there is no account.
    public var main: Account? { accounts.first { $0.isMain } }

    /// Creates a book, repairing the main flag: the first account flagged main wins, else the first account.
    /// Two accounts with the same pseudo (ignoring case) keep the first one.
    public init(accounts: [Account] = []) {
        var unique: [Account] = []
        for account in accounts where !unique.contains(where: { Self.samePseudo($0.pseudo, account.pseudo) }) {
            unique.append(account)
        }
        self.accounts = unique
        normalizeMain(preferring: unique.firstIndex { $0.isMain })
    }

    /// The account whose pseudo matches, ignoring case and surrounding spaces; then by display name.
    public func account(matching pseudo: String) -> Account? {
        index(matching: pseudo).map { accounts[$0] }
    }

    /// Adds an account, or refreshes the stored one with the same pseudo (ignoring case; the stored spelling
    /// stays): new cookies replace the old ones, a nil `hashCheck` or `avatarData` keeps the stored value, and a
    /// display name that only differs by case (a re-login typed in lower case) keeps the stored one. With
    /// `makeMain` (legacy `AccountSessionService.swift:68-75`) it becomes the main account; the first account
    /// always does. Pseudos lose surrounding spaces and invisible format characters (U+200B, U+FEFF, ...).
    /// When the cookies hold `md_user`, it must name the same pseudo (legacy takes the pseudo from it,
    /// `MultisManager.m:55-60`): else `pseudoMismatch`; `md_user=deleted` is a logged-out session, `invalidPseudo`.
    /// Returns the stored account.
    @discardableResult
    public mutating func add(_ account: Account, makeMain: Bool = true) throws -> Account {
        let pseudo = Self.normalized(account.pseudo)
        guard !pseudo.isEmpty, pseudo.lowercased() != Self.loggedOutMarker else { throw CredentialStoreError.invalidPseudo }
        try Self.checkSessionCookie(of: account, against: pseudo)
        var incoming = account
        incoming.pseudo = pseudo
        let display = Self.normalized(account.displayName)
        incoming.displayName = display.isEmpty ? pseudo : display

        let position: Int
        if let existing = accounts.firstIndex(where: { Self.samePseudo($0.pseudo, pseudo) }) {
            let stored = accounts[existing]
            incoming.pseudo = stored.pseudo
            if Self.samePseudo(incoming.displayName, stored.displayName) || Self.samePseudo(incoming.displayName, stored.pseudo) {
                incoming.displayName = stored.displayName
            }
            incoming.hashCheck = incoming.hashCheck ?? stored.hashCheck
            incoming.avatarData = incoming.avatarData ?? stored.avatarData
            incoming.isMain = stored.isMain
            accounts[existing] = incoming
            position = existing
        } else {
            incoming.isMain = false
            accounts.append(incoming)
            position = accounts.count - 1
        }
        normalizeMain(preferring: makeMain ? position : accounts.firstIndex { $0.isMain })
        return accounts[position]
    }

    /// Makes the matching account the main one; false when no account matches.
    @discardableResult
    public mutating func setMain(pseudo: String) -> Bool {
        guard let position = index(matching: pseudo) else { return false }
        normalizeMain(preferring: position)
        return true
    }

    /// Deletes the matching account and returns it; when it was the main one, the first remaining account
    /// becomes main (legacy `MultisManager.m:125-153`). Nil when no account matches.
    @discardableResult
    public mutating func remove(pseudo: String) -> Account? {
        guard let position = index(matching: pseudo) else { return nil }
        let removed = accounts.remove(at: position)
        normalizeMain(preferring: accounts.firstIndex { $0.isMain })
        return removed
    }

    /// Replaces the stored account that has the same pseudo, keeping the main flag; false when absent.
    @discardableResult
    public mutating func replace(_ account: Account) -> Bool {
        guard let position = accounts.firstIndex(where: { Self.samePseudo($0.pseudo, account.pseudo) }) else { return false }
        var updated = account
        updated.pseudo = accounts[position].pseudo
        updated.isMain = accounts[position].isMain
        accounts[position] = updated
        return true
    }

    /// Exactly one main account when there is any: `preferred`, else the first one.
    private mutating func normalizeMain(preferring preferred: Int?) {
        guard !accounts.isEmpty else { return }
        let mainIndex = preferred ?? 0
        for position in accounts.indices {
            accounts[position].isMain = position == mainIndex
        }
    }

    private func index(matching identifier: String) -> Int? {
        let wanted = Self.normalized(identifier)
        guard !wanted.isEmpty else { return nil }
        return accounts.firstIndex { $0.pseudo == wanted }
            ?? accounts.firstIndex { Self.samePseudo($0.pseudo, wanted) }
            ?? accounts.firstIndex { Self.samePseudo($0.displayName, wanted) }
    }

    /// Case-insensitive comparison of normalized pseudos. Diacritics are significant: `Élodie` and `Elodie` can
    /// be two accounts.
    private static func samePseudo(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs).lowercased() == normalized(rhs).lowercased()
    }

    /// The `md_user` value of a logged-out session (A §4.1).
    private static let loggedOutMarker = "deleted"

    /// Without surrounding whitespace and without Unicode format characters (category Cf: U+200B, U+FEFF, ...),
    /// which copy-paste and some keyboards insert and which make two spellings of one pseudo look distinct.
    static func normalized(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { $0.properties.generalCategory != .format })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The `md_user` cookie, when present, must be this pseudo (compared raw and percent-decoded).
    private static func checkSessionCookie(of account: Account, against pseudo: String) throws {
        guard let cookie = account.cookies.first(where: { $0.name == "md_user" }) else { return }
        let value = cookie.value
        guard value.lowercased() != loggedOutMarker else { throw CredentialStoreError.invalidPseudo }
        let decoded = value.replacing("+", with: " ").removingPercentEncoding ?? value
        guard samePseudo(value, pseudo) || samePseudo(decoded, pseudo) else { throw CredentialStoreError.pseudoMismatch }
    }
}
