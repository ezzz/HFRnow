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
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: MPNotificationSettingsModel

    init(store: any SettingsStore = UserDefaultsSettingsStore()) {
        _model = State(initialValue: MPNotificationSettingsModel(store: store))
    }

    var body: some View {
        @Bindable var model = model
        Section {
            // The checks against iOS's settings hang on this one row: on the `Section`, they apply to each of its rows.
            Toggle("Notifications", isOn: $model.notificationsEnabled)
                .task { await model.checkPermission() }
                // Back from iOS's settings (or anywhere else): what changed there is read again.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.checkPermission() } }
                }
                .onChange(of: model.notificationsEnabled) { _, isOn in
                    if isOn { Task { await model.notificationsTurnedOn() } }
                }
                .onChange(of: model.badgeEnabled) { _, isOn in
                    if isOn { Task { await model.badgeTurnedOn() } }
                }
                .alert(
                    model.alert?.title ?? "",
                    isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                    presenting: model.alert
                ) { _ in
                    Button("Ouvrir les réglages", action: openNotificationSettings)
                    Button("Annuler", role: .cancel) {}
                } message: { alert in
                    Text(alert.message)
                }
            Toggle("Badge messages non lus", isOn: $model.badgeEnabled)
            Picker("Vérifier les messages", selection: $model.interval) {
                ForEach(MPCheckInterval.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if let text = model.lastCheckText() {
                Text(text)
                    .scaledFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Réglages des notifications", systemImage: "bell.badge", action: openNotificationSettings)
        } header: {
            Text("Notifications MP")
        } footer: {
            Text(model.interval.footer)
        }
        .task(id: accounts.current?.id) { await model.loadLastCheck(account: accounts.current?.id) }
    }

    /// iOS's notification settings of the app.
    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}
