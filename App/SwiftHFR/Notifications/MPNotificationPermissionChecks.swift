import SwiftUI

/// The checks of Réglages › Notifications MP against iOS's settings (#1060), hung on the whole Réglages screen: a row of the
/// lazy `Form` scrolled out of sight would lose its task, its scene-phase handler and its alert.
struct MPNotificationPermissionChecks: ViewModifier {
    let model: MPNotificationSettingsModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // One opening per appearance of the screen, like the cache measure of « Maintenance ».
            .task { await model.screenOpened() }
            // Back from iOS's settings (or anywhere else): what changed there is read again.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.checkPermission() } }
            }
            .alert(
                model.alert?.title ?? "",
                isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
                presenting: model.alert
            ) { _ in
                Button("Ouvrir les réglages") {
                    if let url = MPNotificationSettingsSection.notificationSettingsURL { openURL(url) }
                }
                Button("Annuler", role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
    }
}

extension View {
    /// Checks Réglages › Notifications MP against iOS's settings and shows the alert of `model` (#1060).
    func mpNotificationPermissionChecks(_ model: MPNotificationSettingsModel) -> some View {
        modifier(MPNotificationPermissionChecks(model: model))
    }
}
