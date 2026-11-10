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

// Port of HFRswift/Swift/UserProfileView.swift (GAP-167: UserProfileViewModel, UserProfileQuickActions) @ 2440d79. Differences: the
// quick actions are hooks set by the lots that own them (LOT-128 MP, LOT-118 lists: "Liste noire" / "Love list", legacy
// `toggleProfileBlacklist` / `toggleProfileWhitelist`, `MessagesView.swift:3663-3694`); see the LOT-116 spec. The sheet stays open
// after a toggle (legacy dismissed it); the reader rebuilds its page when the sheet closes.
/// State of the profile screen (LOT-116): one member's profile, loaded once on appear, reloaded on demand; the profile on
/// screen stays while a reload runs or fails (`ContentLoader`).
@MainActor
@Observable
final class UserProfileModel: Identifiable {
    /// The member shown (`/hfr/profil-<id>.htm`).
    let memberID: Int
    /// Opens the MP composer to this pseudo; nil until LOT-128 wires it, and then the button is hidden.
    let onPrivateMessage: (@MainActor (String) -> Void)?

    /// The pseudo lists the "Liste noire" / "Love list" buttons edit; nil hides them (LOT-118).
    let lists: PseudoListManager?

    private let source: any UserProfileSource
    private let loader = ContentLoader<UserProfile>()

    /// Creates the model of member `memberID`'s profile.
    init(
        memberID: Int, source: any UserProfileSource, onPrivateMessage: (@MainActor (String) -> Void)? = nil,
        lists: PseudoListManager? = nil
    ) {
        self.lists = lists
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
    /// Counts finished loads; the profile's images load again when it changes, so a failed image is retried by a reload.
    private(set) var loadGeneration = 0
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

    /// Runs after a toggle that changed a list, once the snapshot is refreshed (set by the reader; weak captures only).
    var onListsChanged: (@MainActor () -> Void)?
    /// The sentence of the last list toggle, shown under the buttons.
    private(set) var listFeedback: String?
    /// Counts the toggles that set `listFeedback`, so a view tells two identical sentences apart (a failure repeated).
    private(set) var listFeedbackCount = 0
    /// Whether each list holds the member now, for the buttons' labels; false until read.
    private(set) var isBlocked = false
    private(set) var isAllowed = false

    /// The pseudo the list buttons act on: the member's, once the page named them; never the account's own
    /// (legacy `canToggleLists = !isOwnMessage`, `MessagesView.swift:3582-3590`).
    var listPseudo: String? {
        guard let lists, let pseudo = profile?.pseudo, !pseudo.isEmpty, !lists.isOwn(pseudo) else { return nil }
        return pseudo
    }

    /// Whether the button of `kind` is shown (the blocklist needs an account).
    func offers(_ kind: PseudoListKind) -> Bool { listPseudo != nil && (lists?.isAvailable(kind) ?? false) }

    /// Reads whether the member is in each list.
    func refreshListState() async {
        guard let lists, let pseudo = listPseudo else { return }
        isBlocked = lists.isAvailable(.blocklist) ? await lists.contains(pseudo, in: .blocklist) : false
        isAllowed = await lists.contains(pseudo, in: .allowlist)
    }

    /// Adds the member to the list, or removes them (legacy `toggleProfileBlacklist` / `toggleProfileWhitelist`).
    func toggle(_ kind: PseudoListKind) async {
        guard let lists, let pseudo = listPseudo, let result = await lists.toggle(pseudo, in: kind) else { return }
        listFeedback = result.message
        listFeedbackCount += 1
        await refreshListState()
        if result.changed { onListsChanged?() }
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
        await refreshListState()
        loadGeneration += 1
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

extension ReaderServices {
    /// The profile screen's model of member `memberID`, with the list buttons (LOT-118); the one place the reader builds it.
    /// `listsChanged` runs after each toggle that changed a list, once the snapshot is refreshed (the reader rebuilds its page).
    @MainActor
    func profileModel(memberID: Int, listsChanged: (@MainActor () -> Void)? = nil) -> UserProfileModel {
        let model = UserProfileModel(memberID: memberID, source: profiles, lists: pseudoLists)
        model.onListsChanged = listsChanged
        return model
    }
}
