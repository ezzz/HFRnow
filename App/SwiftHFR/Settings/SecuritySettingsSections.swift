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
            Group {
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
            }.themedListRow()
        } header: {
            Text("Comptes").themedSectionHeader()
        }
        Section {
            Group {
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
            }.themedListRow()
        } header: {
            Text("Sécurité").themedSectionHeader()
        }
    }
}
