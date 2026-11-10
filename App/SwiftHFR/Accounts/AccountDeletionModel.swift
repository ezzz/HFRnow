import Foundation
import HFRStorage
import Observation

/// The deletion screen's state (LOT-157): HFR's procedure link, and the wipe of one account's data from this device.
///
/// One model for the app (`SwiftHFRApp`): erasing the current account rebuilds the root navigation, and the result must still
/// be on screen afterwards. What a wipe could not erase is read back from the stores (`leftovers`), so it survives a relaunch
/// and is offered again whatever removed the account (a wipe, "Retirer", erasing an unreadable account store).
@MainActor
@Observable
final class AccountDeletionModel {
    /// Where the last wipe stands.
    enum Phase: Equatable {
        /// Nothing done yet.
        case idle
        /// Erasing the data of `name`.
        case erasing(name: String)
        /// Everything of `name` was erased from this device.
        case erased(name: String)
        /// Some data of `name` could not be erased; `failures` are their French names.
        case partial(name: String, failures: [String])
        /// The account could not be removed (store message); nothing was erased.
        case refused(message: String)
    }

    /// HFR's own procedure: the forum has no deletion page, and the footer of every page links the GDPR page of
    /// hardware.fr (`R98a`, `R01`; HFR-PROTOCOL §6b "Account deletion"). Opened in the user's browser, never fetched.
    static let procedureURL = URL(string: "https://www.hardware.fr/html/donnees_personnelles/")

    private(set) var phase: Phase = .idle
    /// Account keys that still have data on this device but are no longer stored accounts, sorted; refreshed by
    /// `refreshLeftovers()` and after every wipe.
    private(set) var leftovers: [String] = []
    /// True when the last wipe could not delete the empty Keychain item; `retry()` deletes it.
    private(set) var keychainItemPending = false

    @ObservationIgnored private let accounts: AccountsModel
    @ObservationIgnored private let eraser: AccountDataEraser

    /// Creates the model over the app's accounts and the stores `eraser` empties.
    init(accounts: AccountsModel, eraser: AccountDataEraser) {
        self.accounts = accounts
        self.eraser = eraser
    }

    /// True while a wipe runs; the screen disables its buttons.
    var isErasing: Bool {
        if case .erasing = phase { return true }
        return false
    }

    /// Removes the account (Keychain entry, session), then erases its data from every per-account store. A refused
    /// removal erases nothing; a store that fails is reported and its account stays in `leftovers`.
    func erase(_ row: AccountRow) async {
        guard !isErasing else { return }
        phase = .erasing(name: row.displayName)
        do throws(AccountActionError) {
            try accounts.remove(row.id)
        } catch {
            phase = .refused(message: AccountMessages.message(for: error) ?? Self.genericFailure)
            return
        }
        // A row's id is the stored pseudo (`AccountsModel.publish`), the spelling the stores were written under.
        await run(account: row.id, name: row.displayName)
    }

    /// Erases the data of an account key in `leftovers`; a key that is a stored account again is left alone.
    func eraseLeftover(_ key: String) async {
        guard !isErasing, !isStored(key) else { return }
        phase = .erasing(name: key)
        await run(account: key, name: key)
    }

    /// Deletes the empty Keychain item the last wipe left.
    func retry() async {
        guard keychainItemPending, !isErasing else { return }
        phase = .erasing(name: Self.keychainTitle)
        let deleted = removeKeychainItemIfEmpty()
        phase = deleted ? .idle : .partial(name: Self.keychainTitle, failures: [Self.keychainTitle])
    }

    /// Reads which account keys still have data without a stored account. None while the account store cannot be read
    /// (device locked, newer version): its accounts may still exist, and their data is not offered for erasing.
    func refreshLeftovers() async {
        guard accounts.storeProblem == nil else {
            leftovers = []
            return
        }
        let keys = await eraser.accountKeys()
        guard accounts.storeProblem == nil else {
            leftovers = []
            return
        }
        leftovers = keys.filter { !isStored($0) }.sorted()
    }

    private func run(account: String, name: String) async {
        let keychainFailed = !removeKeychainItemIfEmpty()
        let failed = await eraser.erase(account: account)
        await refreshLeftovers()
        guard keychainFailed || !failed.isEmpty else {
            phase = .erased(name: name)
            return
        }
        phase = .partial(name: name, failures: (keychainFailed ? [Self.keychainTitle] : []) + failed.map(\.title))
    }

    /// Deletes the Keychain item when it holds no account; false (and `keychainItemPending`) when the Keychain refused.
    private func removeKeychainItemIfEmpty() -> Bool {
        do {
            try accounts.removeStoreItemIfEmpty()
            keychainItemPending = false
            return true
        } catch {
            keychainItemPending = true
            return false
        }
    }

    private func isStored(_ key: String) -> Bool {
        accounts.rows.contains { AccountKey.make($0.id) == key }
    }

    private static let keychainTitle = "l’élément du trousseau"
    private static let genericFailure = "Le compte n’a pas pu être retiré. Réessayez."
}
