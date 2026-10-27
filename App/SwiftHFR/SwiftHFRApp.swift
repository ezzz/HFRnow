import SwiftUI

/// Entry point of the SwiftHFR iOS app; the composition root for every screen.
@main
struct SwiftHFRApp: App {
    @State private var accounts = AccountsModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(accounts)
                // Restores the stored accounts and their sessions once per launch (LOT-081).
                .task { await accounts.restore() }
        }
    }
}
