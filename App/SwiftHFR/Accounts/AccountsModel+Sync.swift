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
        refreshAccountSyncState(sync)
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
        refreshAccountSyncState(sync)
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
        refreshAccountSyncState(sync)
    }

    /// The settings' « Réinitialiser », once the user confirmed it: the explicit switch-off that resets a damaged state
    /// (#1200 P3, option (b)). Never called on its own.
    func resetAccountSync() {
        setAccountSync(false)
    }

    /// Reads the switch and whether the state is damaged; another refusal (a later version's state, a locked Keychain)
    /// keeps what is shown.
    private func refreshAccountSyncState(_ sync: AccountSync) {
        do {
            isAccountSyncOn = try sync.state().isOn
            isAccountSyncDamaged = false
        } catch AccountSyncError.damagedState {
            // The switch reads off, so turning it off can never be a reset without the confirmation (#1214 round 1).
            isAccountSyncOn = false
            isAccountSyncDamaged = true
        } catch {
            isAccountSyncDamaged = false
        }
    }

    private func apply(_ report: AccountSyncReport) {
        if let reason = report.switchedOff { accountSyncNotice = AccountSyncMessages.switchedOff(reason) }
        adoptSyncReport(report)
    }
}

/// The French texts of the account sync. None names an account or quotes stored bytes.
enum AccountSyncMessages {
    /// The switch's title (ADR 0013 §6; renamed from « Synchroniser mes comptes via le trousseau iCloud », operator, #1065).
    static let title = "Synchro des comptes dans iCloud"

    /// The accessibility label of the (i) button that opens `explanation` in a bubble (#1065).
    static let infoLabel = "À propos de la synchro des comptes"

    /// What travels, where, and how to stop (#312); reviewed by the operator before merge. Shown in the info bubble of the row (#1065).
    static let explanation = """
        Vos comptes (cookies de session et jeton hash_check, jamais de mot de passe) sont copiés dans votre trousseau \
        iCloud, chiffré de bout en bout par Apple, et apparaissent sur vos autres appareils où l’option est activée. \
        Désactiver l’option retire la copie iCloud sur tous vos appareils ; chaque appareil garde les comptes qui y sont \
        connectés.
        """

    /// The reset's button and the confirmation it asks for (#1200 P3): what is lost, and what is not.
    static let resetButton = "Réinitialiser"
    static let resetTitle = "Réinitialiser la synchronisation des comptes ?"
    static let resetMessage = """
        Les réglages de synchronisation de cet appareil seront effacés : l’option restera désactivée, et cet appareil \
        n’importera plus de lui-même les comptes d’un autre appareil. La copie iCloud n’est pas supprimée : pour la \
        retirer de tous vos appareils, réactivez puis désactivez l’option. Vos comptes ne sont pas touchés.
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
        switch error as? AccountSyncError {
        case .itemChanged?:
            return "Un autre appareil modifie la copie iCloud en ce moment. Réessayez."
        case .stateFromLaterVersion?:
            // Never written over (#1200 P3): the later version can still read it.
            return "L’état de la synchronisation des comptes vient d’une version plus récente de l’app. Mettez l’app à jour."
        case .damagedState?:
            // Kept until the user resets it (#1200 P3, option (b)).
            return "L’état de la synchronisation des comptes de cet appareil est illisible. Réinitialisez-le pour pouvoir "
                + "réactiver l’option."
        case nil:
            break
        }
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
