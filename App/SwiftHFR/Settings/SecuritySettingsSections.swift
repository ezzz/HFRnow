import SwiftUI

// New in SwiftHFR: none @ 87fe0d1c (`HFRswift/Swift/AppSettingsView.swift` has neither row; GAP-168, GAP-169).
// Differences: the whole feature.
/// The two LOT-173 sections of the settings screen: the opt-in iCloud Keychain sync of the accounts and the app lock.
struct SecuritySettingsSections: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(AppLockModel.self) private var lock
    /// The reset's confirmation is shown (#1200 P3).
    @State private var confirmsSyncReset = false

    var body: some View {
        @Bindable var lock = lock
        Section {
            ThemedRows {
                HStack {
                    Toggle(AccountSyncMessages.title, isOn: Binding(
                        get: { accounts.isAccountSyncOn },
                        set: { accounts.setAccountSync($0) }
                    ))
                    InfoBubbleButton(label: AccountSyncMessages.infoLabel) {
                        Text(AccountSyncMessages.explanation)
                            .padding()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let notice = accounts.accountSyncNotice {
                    Text(notice)
                        .scaledFont(.footnote)
                }
                if accounts.isAccountSyncDamaged {
                    // Only for damaged bytes, and only once confirmed: a reset is never silent (#1200 P3, option (b)).
                    Button(AccountSyncMessages.resetButton, role: .destructive) { confirmsSyncReset = true }
                        .confirmationDialog(
                            AccountSyncMessages.resetTitle, isPresented: $confirmsSyncReset, titleVisibility: .visible
                        ) {
                            Button(AccountSyncMessages.resetButton, role: .destructive) { accounts.resetAccountSync() }
                            Button("Annuler", role: .cancel) {}
                        } message: {
                            Text(AccountSyncMessages.resetMessage)
                        }
                }
            }
        } header: {
            Text("Comptes").themedSectionHeader()
        }
        Section {
            ThemedRows {
                Toggle(lock.switchTitle, isOn: Binding(
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
            }
        } header: {
            Text("Sécurité").themedSectionHeader()
        }
    }
}
