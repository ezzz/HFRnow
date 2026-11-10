import Foundation
import Observation

/// The deletion screen's state (LOT-157): HFR's procedure link, and the wipe of one account's data from this device.
///
/// One model for the app (`SwiftHFRApp`): erasing the current account rebuilds the root navigation, and the result must still
/// be on screen afterwards.
@MainActor
@Observable
final class AccountDeletionModel {
    /// Where the wipe stands.
    enum Phase: Equatable {
        /// Nothing done yet.
        case idle
        /// Erasing the account named `name`.
        case erasing(name: String)
        /// Everything of `name` was erased from this device.
        case erased(name: String)
        /// `name` was removed but some of its data could not be erased; `failures` are their French names.
        case partial(name: String, failures: [String])
        /// The account could not be removed (store message); nothing was erased.
        case refused(message: String)
    }

    /// HFR's own procedure: the forum has no deletion page, and the footer of every page links the GDPR page of
    /// hardware.fr (`R98a`, `R01`; HFR-PROTOCOL §6b "Account deletion"). Opened in the user's browser, never fetched.
    static let procedureURL = URL(string: "https://www.hardware.fr/html/donnees_personnelles/")

    private(set) var phase: Phase = .idle

    @ObservationIgnored private let accounts: AccountsModel
    @ObservationIgnored private let eraser: AccountDataEraser
    /// What a retry erases again: the stores that failed, for the account they belong to.
    @ObservationIgnored private var pending: Pending?

    private struct Pending {
        let pseudo: String
        let name: String
        let kinds: [AccountDataKind]
        let keychainItem: Bool
    }

    /// Creates the model over the app's accounts and the stores `eraser` empties.
    init(accounts: AccountsModel, eraser: AccountDataEraser) {
        self.accounts = accounts
        self.eraser = eraser
    }

    /// True while an erase runs; the screen disables its buttons.
    var isErasing: Bool {
        if case .erasing = phase { return true }
        return false
    }

    /// True when `retry()` has something to erase again.
    var canRetry: Bool { pending != nil && !isErasing }

    /// Removes the account (Keychain entry, session), then erases its data from every per-account store. A refused
    /// removal erases nothing; a store that fails is reported and kept for `retry()`.
    func erase(_ row: AccountRow) async {
        guard !isErasing else { return }
        phase = .erasing(name: row.displayName)
        do throws(AccountActionError) {
            try accounts.remove(row.id)
        } catch {
            pending = nil
            phase = .refused(message: AccountMessages.message(for: error) ?? Self.genericFailure)
            return
        }
        // A row's id is the stored pseudo (`AccountsModel.publish`), the key the stores were written under.
        await run(Pending(pseudo: row.id, name: row.displayName, kinds: AccountDataKind.allCases, keychainItem: true))
    }

    /// Erases again what the last erase could not.
    func retry() async {
        guard let pending, !isErasing else { return }
        phase = .erasing(name: pending.name)
        await run(pending)
    }

    private func run(_ job: Pending) async {
        var keychainFailed = false
        if job.keychainItem {
            do {
                try accounts.removeStoreItemIfEmpty()
            } catch {
                keychainFailed = true
            }
        }
        let failed = await eraser.erase(account: job.pseudo, kinds: job.kinds)
        guard keychainFailed || !failed.isEmpty else {
            pending = nil
            phase = .erased(name: job.name)
            return
        }
        pending = Pending(pseudo: job.pseudo, name: job.name, kinds: failed, keychainItem: keychainFailed)
        phase = .partial(name: job.name, failures: (keychainFailed ? [Self.keychainTitle] : []) + failed.map(\.title))
    }

    private static let keychainTitle = "l’élément du trousseau"
    private static let genericFailure = "Le compte n’a pas pu être retiré. Réessayez."
}
