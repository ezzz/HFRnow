import SwiftUI

/// Entry point of the SwiftHFR iOS app; the composition root for every screen.
@main
struct SwiftHFRApp: App {
    @State private var accounts = AccountsModel.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(accounts)
                // Restores the stored accounts and their sessions once per launch (LOT-081).
                .task { await accounts.restore() }
                // Back in the foreground: sessions the forum did not confirm are checked again, quietly (#300).
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await accounts.recheckUnconfirmedSessions() }
                }
        }
    }
}
