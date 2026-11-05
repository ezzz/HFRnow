import Foundation
import HFRParsing
import Observation

/// Where a link of the profile screen opens. Never in the app with the session: action rows and member links go to a browser
/// (LESSONS 43, legacy `UserProfileView.openLink`).
enum ProfileLinkAction: Equatable, Sendable {
    /// In Safari's view inside the app.
    case inAppBrowser(URL)
    /// In the system's default browser ("Navigateur par défaut", LOT-119).
    case defaultBrowser(URL)
    /// Not an `http(s)` link: nothing happens.
    case ignored
}

// Port of HFRswift/Swift/UserProfileView.swift (UserProfileViewModel, UserProfileQuickActions) @ 2440d79. Differences: the
// quick actions are hooks set by the lots that own them (LOT-128 MP, LOT-118 lists); see the LOT-116 spec.
/// State of the profile screen (LOT-116): one member's profile, loaded once on appear, reloaded on demand; the profile on
/// screen stays while a reload runs or fails (`ContentLoader`).
@MainActor
@Observable
final class UserProfileModel: Identifiable {
    /// The member shown (`/hfr/profil-<id>.htm`).
    let memberID: Int
    /// Opens the MP composer to this pseudo; nil until LOT-128 wires it, and then the button is hidden.
    let onPrivateMessage: (@MainActor (String) -> Void)?

    private let source: any UserProfileSource
    private let loader = ContentLoader<UserProfile>()

    /// Creates the model of member `memberID`'s profile.
    init(memberID: Int, source: any UserProfileSource, onPrivateMessage: (@MainActor (String) -> Void)? = nil) {
        self.memberID = memberID
        self.source = source
        self.onPrivateMessage = onPrivateMessage
    }

    /// One sheet per member.
    nonisolated var id: Int { memberID }

    /// The profile last loaded; kept while reloading and after a failed reload.
    var profile: UserProfile? { loader.value }
    /// A load is running.
    var isLoading: Bool { loader.isLoading }
    /// Failure of the latest load; cleared by the next success.
    var error: ListLoadError? { loader.error }

    /// Title of the screen: the member's pseudo once known.
    var title: String {
        guard let pseudo = profile?.pseudo, !pseudo.isEmpty else { return "Profil" }
        return pseudo
    }

    /// The pseudo the "MP" button writes to: shown only when a composer is wired and the page named the member.
    var privateMessageRecipient: String? {
        guard onPrivateMessage != nil, let pseudo = profile?.pseudo, !pseudo.isEmpty else { return nil }
        return pseudo
    }

    /// First load, when nothing is on screen and nothing is loading.
    func onAppear() async {
        guard profile == nil, !isLoading else { return }
        await reload()
    }

    /// Loads the profile again (the "Actualiser" and "Réessayer" buttons).
    func reload() async {
        let source = self.source
        let memberID = self.memberID
        await loader.load { () async throws(ListLoadError) -> UserProfile in
            try await source.profile(memberID: memberID)
        }
    }

    /// Hands the member's pseudo to the MP composer.
    func writePrivateMessage() {
        guard let recipient = privateMessageRecipient else { return }
        onPrivateMessage?(recipient)
    }

    /// What tapping a field link or an action row does: a browser, never the reader with the session (LESSONS 43).
    func action(forLink url: URL, defaultBrowser: Bool) -> ProfileLinkAction {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return .ignored }
        return defaultBrowser ? .defaultBrowser(url) : .inAppBrowser(url)
    }
}
