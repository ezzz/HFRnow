import SwiftUI

// New in SwiftHFR: none @ 87fe0d1c (`HFRswift/Swift/AppSettingsView.swift` has neither row; GAP-168, GAP-169).
// Differences: the whole feature.
/// The two LOT-173 sections of the settings screen: the opt-in iCloud Keychain sync of the accounts and the app lock.
struct SecuritySettingsSections: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(AppLockModel.self) private var lock

    var body: some View {
        @Bindable var lock = lock
        Section {
            Toggle(AccountSyncMessages.title, isOn: Binding(
                get: { accounts.isAccountSyncOn },
                set: { accounts.setAccountSync($0) }
            ))
            if let notice = accounts.accountSyncNotice {
                Text(notice)
                    .scaledFont(.footnote)
            }
        } header: {
            Text("Comptes")
        } footer: {
            Text(AccountSyncMessages.explanation)
        }
        Section {
            Toggle("Verrouiller l’app (Face ID / code)", isOn: Binding(
                get: { lock.isEnabled },
                set: { lock.setEnabled($0) }
            ))
            if lock.isEnabled {
                Picker("Verrouiller", selection: $lock.grace) {
                    ForEach(AppLockGrace.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            if let message = lock.message, !lock.isLocked {
                Text(message)
                    .scaledFont(.footnote)
            }
        } header: {
            Text("Sécurité")
        } footer: {
            Text("L’app se verrouille au lancement et au retour après le délai choisi ; le code de l’appareil remplace Face ID.")
        }
    }
}
