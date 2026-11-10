import Foundation
import HFRStorage

// New in SwiftHFR: none @ 87fe0d1c (legacy never shared its accounts; GAP-168). Differences: the whole feature.
extension AccountsModel {
    /// Applies the sync rules to what iCloud Keychain delivered (LOT-173): at launch before the first restore, and at each
    /// foreground. An unreadable copy or a Keychain refusal is shown once and changes nothing.
    func reconcileAccountSync() {
        guard let sync else { return }
        do {
            apply(try sync.reconcile())
        } catch {
            accountSyncNotice = AccountSyncMessages.problem(error)
        }
        isAccountSyncOn = (try? sync.state())?.isOn ?? isAccountSyncOn
    }

    /// The settings switch. Switching off never removes the accounts entered on this device.
    func setAccountSync(_ isOn: Bool) {
        guard let sync else { return }
        do {
            accountSyncNotice = nil
            apply(try isOn ? sync.switchOn() : sync.switchOff())
        } catch {
            accountSyncNotice = AccountSyncMessages.problem(error)
        }
        isAccountSyncOn = (try? sync.state())?.isOn ?? isAccountSyncOn
    }

    /// Reports a change the store accepted, so the copy follows it while the switch is on (and the dates are kept for a
    /// later switch-on while it is off).
    func noteSyncChange(_ change: AccountSyncChange) {
        guard let sync else { return }
        do {
            apply(try sync.localChange(change))
        } catch {
            accountSyncNotice = AccountSyncMessages.problem(error)
        }
        isAccountSyncOn = (try? sync.state())?.isOn ?? isAccountSyncOn
    }

    private func apply(_ report: AccountSyncReport) {
        if let reason = report.switchedOff { accountSyncNotice = AccountSyncMessages.switchedOff(reason) }
        adoptSyncReport(report)
    }
}

/// The French texts of the account sync. None names an account or quotes stored bytes.
enum AccountSyncMessages {
    /// The switch's title (ADR 0013 §6).
    static let title = "Synchroniser mes comptes via le trousseau iCloud"

    /// What travels, where, and how to stop (#312); reviewed by the operator before merge.
    static let explanation = """
        Vos comptes (cookies de session et jeton hash_check, jamais de mot de passe) sont copiés dans votre trousseau \
        iCloud, chiffré de bout en bout par Apple, et apparaissent sur vos autres appareils où l’option est activée. \
        Désactiver l’option retire la copie iCloud sur tous vos appareils ; chaque appareil garde les comptes qui y sont \
        connectés.
        """

    /// Why the device switched itself off.
    static func switchedOff(_ reason: AccountSyncSwitchOff) -> String {
        switch reason {
        case .tombstone:
            "La synchronisation des comptes a été désactivée sur un autre appareil."
        case .laterSwitchOn:
            "La synchronisation des comptes a été réactivée sur un autre appareil. Réactivez-la ici pour la reprendre."
        }
    }

    /// What went wrong, and what to do.
    static func problem(_ error: any Error) -> String {
        if error is AccountSyncError { return "Un autre appareil modifie la copie iCloud en ce moment. Réessayez." }
        switch error as? CredentialStoreError {
        case .corrupted?:
            return "La copie iCloud des comptes est illisible. Désactivez puis réactivez l’option."
        case .unsupportedVersion?:
            return "La copie iCloud des comptes vient d’une version plus récente de l’app. Mettez l’app à jour."
        default:
            return "Le trousseau est indisponible pour le moment (appareil verrouillé ?). Réessayez."
        }
    }
}
