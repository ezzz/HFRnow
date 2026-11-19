import Foundation
import HFRModels
import HFRParsing
import HFRStorage
import Observation

/// The sections of the picker, in display order.
enum PickerSectionKind: String, CaseIterable, Sendable {
    /// The editor palette of the catalogue.
    case basic
    /// The favourites of the HFR account (`#dynamic_smilies`).
    case forum
    /// The smileys the member created, « Smilies persos » (#414; the page is `R601a`).
    case own
    /// The favourites of the app (LOT-064).
    case appFavorites

    /// The header, in French.
    var title: String {
        switch self {
        case .basic: "Smileys de base"
        case .forum: "Smileys du forum"
        case .own: "Mes smileys"
        case .appFavorites: "Favoris de l’app"
        }
    }
}

/// What a section shows besides its smileys.
enum PickerSectionState: Equatable, Sendable {
    /// The smileys are listed (never empty).
    case smileys
    /// Still being read (forum favourites).
    case loading
    /// The section is empty; the text says why and what to do.
    case empty(String)
    /// The section could not be read; the text tells why.
    case failed(String)
}

/// One section of the picker: its smileys, or the reason there are none.
struct PickerSection: Identifiable, Equatable, Sendable {
    let kind: PickerSectionKind
    let smileys: [PickerSmiley]
    let state: PickerSectionState
    var id: PickerSectionKind { kind }
    var title: String { kind.title }
}

/// One cell of the picker: the code to insert and the image to show.
struct PickerSmiley: Identifiable, Hashable, Sendable {
    let code: String
    let imageURL: URL
    var id: String { code }
}

// Port of HFRswift/Swift/AnswerView.swift (CombinedSmileyPickerView state, updateFavoriteSmiley) @ 2440d79. Differences: search in
// SmileySearchModel (LOT-105, GAP-088), favourites from LOT-064's store, the forum section is read from the composer's form (#600,
// GAP-087); "Mes smileys" (the member's own created smileys) is new (#414, GAP row pending).
/// State of the smiley picker (LOT-104): the editor's catalogue, the account's app favourites, and what the user chose.
///
/// Port of `CombinedSmileyPickerView` (`HFRswift/Swift/AnswerView.swift:1051-1470` @ 2440d79); the search is
/// `SmileySearchModel`. The basic palette inserts on tap; a forum or app favourite opens its detail, which inserts or removes
/// it; any smiley can be added to or removed from the app favourites from its context menu. Favourites are LOT-064's store
/// (legacy `SmileyCache` semantics); the forum favourites are the `#dynamic_smilies` of the composer's own form.
@MainActor
@Observable
final class SmileyPickerModel: Identifiable {
    /// Unique per sheet.
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// The legacy "Smileys basiques": catalogue entries flagged for the editor, in catalogue order.
    private(set) var basic: [PickerSmiley]
    /// The account's app favourites, oldest first.
    private(set) var favorites: [PickerSmiley] = []
    /// The favourites of the HFR account, read from the composer's form; `nil` until read, `[]` when it lists none.
    private(set) var forum: [PickerSmiley]?
    /// Whether reading the forum favourites failed (the section then says so and nothing is invented).
    private(set) var forumFailed = false
    /// The member's own created smileys, read from the profile edit page; `nil` until read, `[]` when there are none.
    private(set) var own: [PickerSmiley]?
    /// Whether reading the own smileys failed (the section then says so and nothing is invented).
    private(set) var ownFailed = false
    /// The smiley whose detail is open.
    var presented: PickerSmiley?
    /// A short French message after a favourite change or a store failure; nil when nothing to say.
    private(set) var notice: String?
    /// The favourites store cannot be read: its section says so and offers « Repartir de zéro » (#1182).
    private(set) var favoritesAreUnreadable = false
    /// The smiley the user chose to insert; the sheet reads it once and closes.
    private(set) var chosen: PickerSmiley?

    /// The forum search, history and wiki keywords (LOT-105); nil when there is no account to search with.
    let search: SmileySearchModel?

    private let store: AppSmileyFavoritesStore
    private let account: String
    private let forumLoader: (@Sendable () async -> [ForumSmiley]?)?
    private let ownLoader: (@Sendable () async -> [OwnSmiley]?)?

    /// A picker over `catalogue` for `account`; call `loadFavorites()` when the sheet opens.
    /// `forumLoader` reads the account's forum favourites (nil result: could not be read); nil without a form to read them from.
    init(
        catalogue: [CommonSmiley], store: AppSmileyFavoritesStore, account: String, search: SmileySearchModel? = nil,
        forumLoader: (@Sendable () async -> [ForumSmiley]?)? = nil, ownLoader: (@Sendable () async -> [OwnSmiley]?)? = nil
    ) {
        self.search = search
        self.forumLoader = forumLoader
        self.ownLoader = ownLoader
        basic = catalogue.filter(\.isEditorSmiley).map { PickerSmiley(code: $0.code, imageURL: $0.url) }
        self.store = store
        self.account = account
    }

    /// Reads the bundled catalogue; empty if the resource cannot be decoded (the panel then says it is unavailable).
    static func bundledCatalogue() -> [CommonSmiley] { bundled }

    private static let bundled: [CommonSmiley] = (try? CommonSmileyCatalog.bundled()) ?? []

    /// Reads the favourites of the account from the store.
    func loadFavorites() async {
        favorites = await store.favorites(for: account).map { PickerSmiley(code: $0.code, imageURL: $0.url) }
        favoritesAreUnreadable = await store.loadFailure() != nil
        if favoritesAreUnreadable {
            notice = "Les favoris sont illisibles pour le moment : ils ne seront pas enregistrés."
        }
    }

    /// « Repartir de zéro », after the member confirmed (#1182): the unreadable favourites file is set aside as `.corrupt`
    /// (never deleted) and the favourites start empty and writable.
    func discardUnreadableFavorites() async {
        do throws(SmallStoreError) {
            try await store.discardUnreadableData()
        } catch {
            notice = UnreadableDataRecovery.failure
            return
        }
        notice = nil
        await loadFavorites()
    }

    /// The sections in display order, each with its smileys or its empty, loading or failed message.
    var sections: [PickerSection] {
        [
            basic.isEmpty
                ? PickerSection(kind: .basic, smileys: [], state: .failed("Catalogue de smileys indisponible."))
                : PickerSection(kind: .basic, smileys: basic, state: .smileys),
            forumSection,
            ownSection,
            favoritesSection
        ]
    }

    /// How to add a favourite, shown while the list is empty (the context menu was not discoverable, #600).
    static let noFavoritesText = "Aucun favori dans l’app pour le moment. Maintenez le doigt sur un smiley, puis « Ajouter aux favoris »."

    private var favoritesSection: PickerSection {
        if favoritesAreUnreadable {
            return PickerSection(kind: .appFavorites, smileys: [], state: .failed(Self.unreadableFavoritesText))
        }
        return favorites.isEmpty
            ? PickerSection(kind: .appFavorites, smileys: [], state: .empty(Self.noFavoritesText))
            : PickerSection(kind: .appFavorites, smileys: favorites, state: .smileys)
    }

    /// The favourites section while the store cannot be read (#1182).
    static let unreadableFavoritesText = "Les favoris de l’app sont illisibles : ils ne sont pas modifiés."

    private var forumSection: PickerSection {
        if let forum, !forum.isEmpty { return PickerSection(kind: .forum, smileys: forum, state: .smileys) }
        if forum != nil {
            return PickerSection(kind: .forum, smileys: [], state: .empty("Aucun smiley favori sur votre compte HFR."))
        }
        if forumFailed {
            return PickerSection(kind: .forum, smileys: [], state: .failed("Smileys du forum indisponibles pour le moment."))
        }
        let state: PickerSectionState = forumLoader == nil ? .empty("Smileys du forum indisponibles ici.") : .loading
        return PickerSection(kind: .forum, smileys: [], state: state)
    }

    /// How to create one, shown while the list is empty.
    static let noOwnSmileysText = "Vous n’avez créé aucun smiley. Le forum permet d’en créer jusqu’à 11 (profil › Smilies persos)."

    private var ownSection: PickerSection {
        if let own, !own.isEmpty { return PickerSection(kind: .own, smileys: own, state: .smileys) }
        if own != nil { return PickerSection(kind: .own, smileys: [], state: .empty(Self.noOwnSmileysText)) }
        if ownFailed {
            return PickerSection(kind: .own, smileys: [], state: .failed("Vos smileys sont indisponibles pour le moment."))
        }
        let state: PickerSectionState = ownLoader == nil ? .empty("Vos smileys sont indisponibles ici.") : .loading
        return PickerSection(kind: .own, smileys: [], state: state)
    }

    /// Reads the member's own smileys from the forum; a failure is shown, never replaced by an empty list.
    func loadOwn() async {
        guard let ownLoader, own == nil else { return }
        if let loaded = await ownLoader() {
            own = loaded.map { PickerSmiley(code: $0.code, imageURL: $0.imageURL) }
            ownFailed = false
        } else {
            ownFailed = true
        }
    }

    /// Reads the own smileys again after a failure (the failed section's "Réessayer"); shows the loading state meanwhile.
    func retryOwn() async {
        guard ownFailed else { return }
        ownFailed = false
        await loadOwn()
    }

    /// A tap on one of the member's own smileys inserts it, like a basic one: it is theirs, no detail to read first.
    func tap(own smiley: PickerSmiley) {
        chosen = smiley
    }

    /// Reads the forum favourites from the composer's form; a failure is shown, never replaced by an empty list.
    func loadForum() async {
        guard let forumLoader, forum == nil else { return }
        if let loaded = await forumLoader() {
            forum = loaded.map { PickerSmiley(code: $0.code, imageURL: $0.url) }
            forumFailed = false
        } else {
            forumFailed = true
        }
    }

    /// Reads the forum favourites again after a failure (the failed section's "Réessayer"); shows the loading state meanwhile.
    func retryForum() async {
        guard forumFailed else { return }
        forumFailed = false
        await loadForum()
    }

    /// A tap on a forum favourite opens its detail, like an app favourite.
    func tap(forum smiley: PickerSmiley) {
        presented = smiley
    }

    /// The context menu's action: adds `smiley` to the app favourites, or removes it when it already is one.
    func toggleFavorite(_ smiley: PickerSmiley) async {
        await setFavorite(smiley, !isFavorite(smiley))
    }

    /// Whether `smiley` is one of the account's favourites (exact code, as legacy).
    func isFavorite(_ smiley: PickerSmiley) -> Bool {
        favorites.contains { $0.code == smiley.code }
    }

    /// A tap on a basic smiley inserts it (legacy `tapBehavior: .insertDirectly`).
    func tap(basic smiley: PickerSmiley) {
        chosen = smiley
    }

    /// A tap on a favourite opens its detail (legacy `tapBehavior: .showDetails`).
    func tap(favorite smiley: PickerSmiley) {
        presented = smiley
    }

    /// A tap on a search result opens its detail, like a favourite (legacy shows the same card for both).
    func tap(result smiley: PickerSmiley) {
        presented = smiley
    }

    /// A keyword of the detail was tapped: the detail closes and the keyword is searched (legacy `search(using:)`).
    func searchKeyword(_ keyword: String, requireAll: Bool) {
        presented = nil
        search?.submit(keyword, requireAll: requireAll)
    }

    /// The detail's "Insérer": the smiley goes to the composer.
    func insertPresented() {
        chosen = presented
        // The detail goes away with the choice, so the panel never closes over a pushed detail (#1177).
        presented = nil
    }

    /// Adds or removes `smiley` from the favourites, with legacy's messages (`AnswerView.swift:737-760`).
    func setFavorite(_ smiley: PickerSmiley, _ add: Bool) async {
        do throws(SmallStoreError) {
            if add {
                try await store.add(code: smiley.code, url: smiley.imageURL, account: account)
            } else {
                try await store.remove(code: smiley.code, account: account)
            }
        } catch {
            notice = "Erreur :/"
            return
        }
        favorites = await store.favorites(for: account).map { PickerSmiley(code: $0.code, imageURL: $0.url) }
        notice = add ? "Smiley ajouté aux favoris" : "Smiley retiré des favoris"
        // A removed favourite has no detail to show any more.
        if !add, presented?.code == smiley.code { presented = nil }
    }

    /// Clears the notice once shown.
    func clearNotice() {
        notice = nil
    }
}
