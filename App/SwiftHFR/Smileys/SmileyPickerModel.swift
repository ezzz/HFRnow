import Foundation
import HFRModels
import HFRStorage
import Observation

/// The sections of the picker, in display order. "Mes smileys" (the member's own created smileys) is not here: its page is
/// not captured yet (#601, *pending capture*).
enum PickerSectionKind: String, CaseIterable, Sendable {
    /// The editor palette of the catalogue.
    case basic
    /// The favourites of the HFR account (`#dynamic_smilies`).
    case forum
    /// The favourites of the app (LOT-064).
    case appFavorites

    /// The header, in French.
    var title: String {
        switch self {
        case .basic: "Smileys de base"
        case .forum: "Smileys du forum"
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
// GAP-087); "Mes smileys" waits for the capture #601.
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
    /// The smiley whose detail is open.
    var presented: PickerSmiley?
    /// A short French message after a favourite change or a store failure; nil when nothing to say.
    private(set) var notice: String?
    /// The smiley the user chose to insert; the sheet reads it once and closes.
    private(set) var chosen: PickerSmiley?

    /// The forum search, history and wiki keywords (LOT-105); nil when there is no account to search with.
    let search: SmileySearchModel?

    private let store: AppSmileyFavoritesStore
    private let account: String
    private let forumLoader: (@Sendable () async -> [ForumSmiley]?)?

    /// A picker over `catalogue` for `account`; call `loadFavorites()` when the sheet opens.
    /// `forumLoader` reads the account's forum favourites (nil result: could not be read); nil without a form to read them from.
    init(
        catalogue: [CommonSmiley], store: AppSmileyFavoritesStore, account: String, search: SmileySearchModel? = nil,
        forumLoader: (@Sendable () async -> [ForumSmiley]?)? = nil
    ) {
        self.search = search
        self.forumLoader = forumLoader
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
        if await store.loadFailure() != nil {
            notice = "Les favoris sont illisibles pour le moment : ils ne seront pas enregistrés."
        }
    }

    /// The sections in display order, each with its smileys or its empty, loading or failed message.
    var sections: [PickerSection] {
        [
            basic.isEmpty
                ? PickerSection(kind: .basic, smileys: [], state: .failed("Catalogue de smileys indisponible."))
                : PickerSection(kind: .basic, smileys: basic, state: .smileys),
            forumSection,
            favorites.isEmpty
                ? PickerSection(kind: .appFavorites, smileys: [], state: .empty(Self.noFavoritesText))
                : PickerSection(kind: .appFavorites, smileys: favorites, state: .smileys)
        ]
    }

    /// How to add a favourite, shown while the list is empty (the context menu was not discoverable, #600).
    static let noFavoritesText = "Aucun favori dans l’app pour le moment. Maintenez le doigt sur un smiley, puis « Ajouter aux favoris »."

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
        // The detail goes away with the choice, so the panel never closes under a presented sheet.
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
