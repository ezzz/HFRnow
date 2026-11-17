import HFRStorage
import SwiftUI
import UIKit

// Port of HFRswift/Swift/AppSettingsView.swift (AppSettingsView.notificationsSection, :527-531) @ 87fe0d1c. Differences: the
// interval picker, its footer, the last check and the button to iOS's settings (GAP-190).
/// Réglages › Notifications MP (LOT-140).
struct MPNotificationSettingsSection: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(\.openURL) private var openURL
    @State private var model: MPNotificationSettingsModel

    init(store: any SettingsStore = UserDefaultsSettingsStore()) {
        _model = State(initialValue: MPNotificationSettingsModel(store: store))
    }

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle("Badge messages non lus", isOn: $model.badgeEnabled)
            Picker("Vérifier les messages", selection: $model.interval) {
                ForEach(MPCheckInterval.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if let text = model.lastCheckText() {
                Text(text)
                    .scaledFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Réglages des notifications", systemImage: "bell.badge") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
        } header: {
            Text("Notifications MP")
        } footer: {
            Text(model.interval.footer)
        }
        .task(id: accounts.current?.id) { await model.loadLastCheck(account: accounts.current?.id) }
    }
}
