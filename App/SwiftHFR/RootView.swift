import SwiftUI

/// Root screen: the root navigation (tab bar or sidebar), built on the current account's session (LOT-081, LOT-170).
///
/// Shown once the stored accounts are read, so the first load is not made logged out and then redone. The navigation is
/// rebuilt from scratch whenever the current session becomes another object (`currentSessionGeneration`): lists and
/// flags of the previous account never stay on screen.
struct RootView: View {
    @Environment(AccountsModel.self) private var accounts
    @State private var built: (generation: Int, environment: AppEnvironment)?

    var body: some View {
        Group {
            if let built {
                RootNavigationView(environment: built.environment)
                    .id(built.generation)
            } else {
                ProgressView()
            }
        }
        .onChange(of: buildKey, initial: true) { rebuild() }
    }

    /// Changes when the navigation must be built again.
    private var buildKey: [Int] {
        accounts.hasRestored ? [accounts.currentSessionGeneration] : []
    }

    private func rebuild() {
        guard accounts.hasRestored else { return }
        built = (accounts.currentSessionGeneration, AppEnvironment.current(of: accounts))
    }
}

#Preview {
    let accounts = AccountsModel.preview()
    RootView()
        .environment(accounts)
        // As `SwiftHFRApp`: the navigation appears once the (empty) preview store is read.
        .task { await accounts.restore() }
}
