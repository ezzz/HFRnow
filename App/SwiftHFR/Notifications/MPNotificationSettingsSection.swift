import HFRStorage
import SwiftUI
import UIKit

// Port of HFRswift/Swift/AppSettingsView.swift (AppSettingsView.notificationsSection, :527-531) @ 87fe0d1c. Differences: the
// interval picker, its footer, the last check and the button to iOS's settings (GAP-190); the « Notifications » switch and
// the alert when a switch disagrees with iOS's settings (operator, 2026-11-18, #1060). Legacy has the badge switch only.
/// Réglages › Notifications MP (LOT-140).
struct MPNotificationSettingsSection: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(\.openURL) private var openURL
    /// Owned by `SettingsView`, whose `Form` carries the checks against iOS (`mpNotificationPermissionChecks`).
    @Bindable var model: MPNotificationSettingsModel

    /// iOS's notification settings of the app.
    static let notificationSettingsURL = URL(string: UIApplication.openNotificationSettingsURLString)

    var body: some View {
        Section {
            Toggle("Notifications", isOn: $model.notificationsEnabled)
                .onChange(of: model.notificationsEnabled) { _, isOn in
                    if isOn { Task { await model.notificationsTurnedOn() } }
                }
            Toggle("Badge messages non lus", isOn: $model.badgeEnabled)
                .onChange(of: model.badgeEnabled) { _, isOn in
                    if isOn { Task { await model.badgeTurnedOn() } }
                }
            Picker("Vérifier les messages", selection: $model.interval) {
                ForEach(MPCheckInterval.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if let text = model.lastCheckText() {
                Text(text)
                    .scaledFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Réglages des notifications", systemImage: "bell.badge") {
                if let url = Self.notificationSettingsURL { openURL(url) }
            }
        } header: {
            Text("Notifications MP")
        } footer: {
            Text(model.interval.footer)
        }
        .task(id: accounts.current?.id) { await model.loadLastCheck(account: accounts.current?.id) }
    }
}
