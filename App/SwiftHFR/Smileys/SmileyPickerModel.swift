import Foundation
import HFRModels
import HFRStorage
import Observation

/// One cell of the picker: the code to insert and the image to show.
struct PickerSmiley: Identifiable, Hashable, Sendable {
    let code: String
    let imageURL: URL
    var id: String { code }
}

// Port of HFRswift/Swift/AnswerView.swift (CombinedSmileyPickerView state, updateFavoriteSmiley) @ 2440d79. Differences: no
// forum-smiley section, search in SmileySearchModel (LOT-105, GAP-088), favourites from LOT-064's store.
/// State of the smiley picker (LOT-104): the editor's catalogue, the account's app favourites, and what the user chose.
///
/// Port of `CombinedSmileyPickerView` (`HFRswift/Swift/AnswerView.swift:1051-1470` @ 2440d79) without the forum-smiley
/// section (another lot, see the spec); the search is `SmileySearchModel`: the basic palette inserts on tap; an app favourite opens its
/// detail, which inserts or removes it. Favourites are LOT-064's store (legacy `SmileyCache` semantics).
@MainActor
@Observable
final class SmileyPickerModel: Identifiable {
    /// Unique per sheet.
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// The legacy "Smileys basiques": catalogue entries flagged for the editor, in catalogue order.
    private(set) var basic: [PickerSmiley]
    /// The account's app favourites, oldest first.
    private(set) var favorites: [PickerSmiley] = []
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

    /// A picker over `catalogue` for `account`; call `loadFavorites()` when the sheet opens.
    init(catalogue: [CommonSmiley], store: AppSmileyFavoritesStore, account: String, search: SmileySearchModel? = nil) {
        self.search = search
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
