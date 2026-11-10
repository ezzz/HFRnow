import SwiftUI

/// Root screen: the root navigation (tab bar or sidebar), built on the current account's session (LOT-081, LOT-170).
///
/// Shown once the stored accounts are read, so the first load is not made logged out and then redone. The navigation is
/// rebuilt from scratch whenever the current session becomes another object (`currentSessionGeneration`): lists and
/// flags of the previous account never stay on screen.
struct RootView: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(LegacyImportModel.self) private var legacyImport
    @Environment(\.avatarRefresh) private var avatarRefresh
    @State private var built: (generation: Int, environment: AppEnvironment)?
    /// Where the user was: a new session generation rebuilds the navigation but keeps the tab or destination (legacy keeps it,
    /// `MainWindow.swift:1276-1278`). Nil until the first creation, which applies the start-screen setting.
    @State private var lastDestination: SidebarDestination?

    var body: some View {
        Group {
            if let built {
                RootNavigationView(environment: built.environment, lastDestination: $lastDestination)
                    .id(built.generation)
            } else if legacyImport.isRunning {
                // The launch import runs before the accounts are read (LOT-158).
                ProgressView("Import des données de HFR+…")
            } else {
                ProgressView()
            }
        }
        .onChange(of: buildKey, initial: true) { rebuild() }
        // What the legacy import took over, shown once it did something or failed (LOT-158).
        .sheet(item: Bindable(legacyImport).summary) { summary in
            LegacyImportSummaryView(opened: summary, model: legacyImport) {
                Task {
                    if await legacyImport.retry(currentAccount: accounts.current?.id) { await accounts.retryRestore() }
                }
            }
        }
    }

    /// Changes when the navigation must be built again.
    private var buildKey: [Int] {
        accounts.hasRestored ? [accounts.currentSessionGeneration] : []
    }

    private func rebuild() {
        guard accounts.hasRestored else { return }
        built = (accounts.currentSessionGeneration, AppEnvironment.current(of: accounts, avatarRefresh: avatarRefresh))
    }
}

#Preview {
    let accounts = AccountsModel.preview()
    RootView()
        .environment(accounts)
        .environment(LegacyImportModel.preview())
        // As `SwiftHFRApp`: the navigation appears once the (empty) preview store is read.
        .task { await accounts.restore() }
}
