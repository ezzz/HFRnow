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

    /// What the root screen shows.
    enum Content: Equatable {
        case navigation
        /// The launch import runs before the accounts are read (LOT-158); the worker of #754.
        case importProgress
        case loading
    }

    static func content(hasNavigation: Bool, importIsRunning: Bool) -> Content {
        if hasNavigation { return .navigation }
        return importIsRunning ? .importProgress : .loading
    }

    var body: some View {
        Group {
            switch Self.content(hasNavigation: built != nil, importIsRunning: legacyImport.isRunning) {
            case .navigation:
                if let built {
                    RootNavigationView(environment: built.environment, lastDestination: $lastDestination)
                        .environment(\.memberAvatars, built.environment.memberAvatars)
                        .id(built.generation)
                }
            case .importProgress:
                LegacyImportProgressView()
            case .loading:
                ProgressView()
            }
        }
        .onChange(of: buildKey, initial: true) { rebuild() }
        // What the legacy import took over, shown once it did something or failed (LOT-158).
        .sheet(item: Bindable(legacyImport).summary) { summary in
            LegacyImportSummaryView(opened: summary, model: legacyImport) {
                Task {
                    if await legacyImport.retry(currentAccount: accounts.current?.id) { await accounts.readStoreAgain() }
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
        .environment(AccountDeletionModel(accounts: accounts, eraser: .inMemory()))
        .environment(LegacyImportModel.preview())
        .environment(AppLockModel.preview())
        // As `SwiftHFRApp`: the navigation appears once the (empty) preview store is read.
        .task { await accounts.restore() }
}
