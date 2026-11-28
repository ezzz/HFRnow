import Foundation
import HFRModels
import HFRStorage
import Observation

/// Where the favourites options keep what is not a setting: the folded sections (device) and the super-favourites (account).
///
/// One store per file for the whole process, as `ComposerServices.liveDrafts`: two actors over a file would write it at once.
struct FavoritesStores: Sendable {
    let layout: FavoritesLayoutStore
    let superFavorites: SuperFavoritesStore
    /// The current account's key (`md_user` value); super-favourites are per account (LOT-064).
    let account: String?
    /// The super-favourites the legacy import left without a category (LOT-158); nil in tests that do not need them.
    var pending: LegacyPendingStore?

    /// The process-wide stores, over `Application Support/Favorites/`.
    static let shared = (
        layout: FavoritesLayoutStore(persistence: FileSmallStorePersistence(fileURL: file("layout.json"))),
        superFavorites: SuperFavoritesStore(persistence: FileSmallStorePersistence(fileURL: file("super-favorites.json")))
    )

    /// The live stores for `account` (nil when logged out: nothing can be marked then).
    static func live(account: String?) -> FavoritesStores {
        FavoritesStores(
            layout: shared.layout, superFavorites: shared.superFavorites, account: account, pending: LegacyImportServices.livePending
        )
    }

    private static func file(_ name: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "Favorites/\(name)")
    }
}

// Port of HFRswift/Swift/Favorites.swift (FavoritesListView state, super-favourite and collapsed stores) @ 2440d79.
// Differences: GAP-030, GAP-031, GAP-032, GAP-033 (per-account super-favourites, UXD none).
/// The favourites options of the Favoris tab and of Réglages (LOT-124): the four legacy settings, the folded sections and
/// the super-favourites.
///
/// Port of `FavoritesListView`'s `@AppStorage` block and its `superFavoriteIDs` / `collapsedSectionIDs` state
/// (`Favorites.swift` @ 2440d79). Each setting reads its legacy key at creation and writes it back on every change.
/// Differences: super-favourites are per account and keyed by category and topic (LOT-064); a store failure is shown, never
/// ignored.
@MainActor
@Observable
final class FavoritesOptionsModel {
    /// Which server list the Favoris tab opens on (`vos_sujets`).
    var mode: FavoritesSource {
        didSet { if mode != oldValue { settings.set(mode, for: SettingKey.favoritesSource) } }
    }
    /// Sections by category, else one list by last post (`sujets_avec_cat`, default on).
    var groupedByCategory: Bool {
        didSet {
            guard groupedByCategory != oldValue else { return }
            settings.set(groupedByCategory, for: SettingKey.favoritesGroupedByCategory)
            // Legacy `.onChange(of: favoritesSortedByCategories)` (`Favorites.swift:796-798` @ 87fe0d1c).
            showsCategoriesOnDemand = false
        }
    }
    /// The temporary « categories for now » view of the flat sort: memory only, never a setting (legacy `showsCategoriesOnDemand`).
    private(set) var showsCategoriesOnDemand = false
    /// Refresh when the list shows again (`favorites_auto_refresh`, default off).
    var autoRefresh: Bool {
        didSet { if autoRefresh != oldValue { settings.set(autoRefresh, for: SettingKey.favoritesAutoRefresh) } }
    }
    /// Collapsed sections, and in "Drapeaux & Favoris" the empty ones, stay listed (`FavoritesShowCollapsedSections`).
    var showsCollapsedSections: Bool {
        didSet {
            if showsCollapsedSections != oldValue { settings.set(showsCollapsedSections, for: SettingKey.favoritesShowsCollapsedSections) }
        }
    }

    /// « Non lus » instead of « Tous » (`favorites_unread_only`, new in SwiftHFR, #1058; device-only, default « Tous »).
    var unreadOnly: Bool {
        didSet { if unreadOnly != oldValue { settings.set(unreadOnly, for: SettingKey.favoritesUnreadOnly) } }
    }

    /// Folded sections (device-wide).
    private(set) var collapsedSections: Set<String> = []
    /// Super-favourites of the current account.
    private(set) var superFavorites: Set<TopicID> = []
    /// What the last store read or write could not do, in French (shown by the list); nil when everything worked. A write
    /// problem is not cleared by a later read.
    var storeProblem: String? { layoutWriteProblem ?? superWriteProblem ?? readProblem }
    /// One per store: a write that works on one never hides the other's refusal.
    private var layoutWriteProblem: String?
    private var superWriteProblem: String?
    private var readProblem: String?
    /// Counts local writes, so a `reload()` that read the stores before a write landed does not undo it.
    @ObservationIgnored private var writeGeneration = 0

    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private let stores: FavoritesStores?
    @ObservationIgnored private let haptics: HapticFeedback

    /// Reads the four settings from `settings`. Without `stores` (Réglages), only the settings work.
    init(settings: any SettingsStore, stores: FavoritesStores? = nil, haptics: HapticFeedback = .live) {
        self.settings = settings
        self.haptics = haptics
        self.stores = stores
        mode = settings.value(for: SettingKey.favoritesSource)
        groupedByCategory = settings.value(for: SettingKey.favoritesGroupedByCategory)
        autoRefresh = settings.value(for: SettingKey.favoritesAutoRefresh)
        showsCollapsedSections = settings.value(for: SettingKey.favoritesShowsCollapsedSections)
        unreadOnly = settings.value(for: SettingKey.favoritesUnreadOnly)
    }

    /// Whether the account can mark super-favourites (logged in, stores available).
    var canMarkSuperFavorites: Bool { stores?.account != nil }

    /// Legacy `shouldShowEmptyFavoriteSections`: the toggle also reveals the empty categories, but only in "Drapeaux & Favoris".
    /// Whatever the sort, so the toggle works the same grouped or flat (a flat list has no section to reveal).
    var showsEmptySections: Bool { showsCollapsedSections && mode == .flagsAndFavorites }

    /// The layout the settings ask for.
    var layout: FavoritesLayoutOptions {
        FavoritesPresentation.effectiveLayout(
            of: FavoritesLayoutOptions(
                groupedByCategory: groupedByCategory, showsCollapsedSections: showsCollapsedSections,
                showsEmptySections: showsEmptySections, unreadOnly: unreadOnly
            ),
            categoriesOnDemand: showsCategoriesOnDemand, emptySectionsAllowed: mode == .flagsAndFavorites
        )
    }

    /// The toolbar button in the flat sort: shows the categories for the moment, or goes back to the flat list.
    func toggleCategoriesOnDemand() {
        haptics.impact(.light)
        showsCategoriesOnDemand.toggle()
    }

    /// The groups of `page` under the current options, folded sections and super-favourites.
    func groups(for page: FavoritesPage) -> [TopicGroup] {
        FavoritesPresentation.groups(of: page, options: layout, collapsed: collapsedSections, superFavorites: superFavorites)
    }

    /// Whether any section of `page` can be folded.
    func hasCollapsibleSections(in page: FavoritesPage) -> Bool {
        layout.groupedByCategory && !foldableSections(of: page).isEmpty
    }

    /// Whether "Tout replier" has something to fold: grouped, and a foldable section is not folded yet (legacy `isSubset(of:)`).
    func canCollapseMore(in page: FavoritesPage) -> Bool {
        layout.groupedByCategory && !foldableSections(of: page)
            .isSubset(of: collapsedSections)
    }

    /// The sections "Tout replier" folds: the ones the list shows with a row (under « Non lus », the ones with an unread row).
    private func foldableSections(of page: FavoritesPage) -> Set<String> {
        FavoritesPresentation.collapsibleSectionIDs(of: page, superFavorites: superFavorites, unreadOnly: unreadOnly)
    }

    /// The Favoris button: « Tous » becomes « Non lus » and back.
    func toggleUnreadOnly() { unreadOnly.toggle() }

    /// Reads the settings again (Réglages may have changed them).
    func reloadSettings() {
        mode = settings.value(for: SettingKey.favoritesSource)
        groupedByCategory = settings.value(for: SettingKey.favoritesGroupedByCategory)
        autoRefresh = settings.value(for: SettingKey.favoritesAutoRefresh)
        showsCollapsedSections = settings.value(for: SettingKey.favoritesShowsCollapsedSections)
        unreadOnly = settings.value(for: SettingKey.favoritesUnreadOnly)
    }

    /// A store could not be read: « Repartir de zéro » is offered (#1182).
    var canDiscardUnreadable: Bool { readProblem != nil }

    /// « Repartir de zéro », after the member confirmed (#1182): the unreadable stores are set aside as `.corrupt` (never
    /// deleted) and start empty; a store that reads fine is left as it is.
    func discardUnreadable() async {
        guard let stores else { return }
        do throws(SmallStoreError) {
            try await stores.layout.discardUnreadableData()
            try await stores.superFavorites.discardUnreadableData()
            // The writes refused while the stores were unreadable are not news any more: the stores take writes again.
            layoutWriteProblem = nil
            superWriteProblem = nil
        } catch {
            layoutWriteProblem = UnreadableDataRecovery.failure
        }
        await reload()
    }

    /// Reads the folded sections and the super-favourites again; the list calls it each time it shows (legacy `onAppear`).
    func reload() async {
        reloadSettings()
        guard let stores else { return }
        let generation = writeGeneration
        let collapsed = await stores.layout.collapsedSections()
        var problem = await stores.layout.loadFailure()
        var supers: Set<TopicID> = []
        if let account = stores.account {
            supers = Set(await stores.superFavorites.favorites(for: account).map(\.topic))
            if problem == nil { problem = await stores.superFavorites.loadFailure() }
        }
        readProblem = problem.map { _ in "Les préférences des favoris sont illisibles." }
        guard generation == writeGeneration else { return }
        if collapsed != collapsedSections { collapsedSections = collapsed }
        if supers != superFavorites { superFavorites = supers }
    }

    /// Folds or unfolds a section.
    func toggleCollapsed(_ section: String) async {
        await setCollapsed(!collapsedSections.contains(section), section: section)
    }

    /// Writes an explicit state, so "Tout replier" and "Tout déplier" never invert a section a tap just changed.
    private func setCollapsed(_ collapse: Bool, section: String) async {
        guard let stores, collapsedSections.contains(section) != collapse else { return }
        writeGeneration += 1
        do throws(SmallStoreError) {
            _ = try await stores.layout.setCollapsed(collapse, section: section)
            if collapse { collapsedSections.insert(section) } else { collapsedSections.remove(section) }
            layoutWriteProblem = nil
        } catch {
            layoutWriteProblem = "Impossible d’enregistrer les sections repliées."
        }
    }

    /// Folds every section of `page` that has a topic (legacy "Tout replier").
    func collapseAll(in page: FavoritesPage) async {
        for section in foldableSections(of: page).sorted() {
            await setCollapsed(true, section: section)
        }
    }

    /// The empty state's « Afficher les sections repliées »: a light impact, then the option (legacy `Favorites.swift:623-625`
    /// @ 87fe0d1c; the menu's toggle plays none).
    func showCollapsedSectionsFromEmptyState() {
        haptics.impact(.light)
        showsCollapsedSections = true
    }

    /// The empty state's « Tout déplier »: a light impact, then `expandAll()` (legacy `Favorites.swift:626-628` @ 87fe0d1c).
    func expandAllFromEmptyState() async {
        haptics.impact(.light)
        await expandAll()
    }

    /// Unfolds every section (legacy "Tout déplier").
    func expandAll() async {
        for section in collapsedSections.sorted() { await setCollapsed(false, section: section) }
    }

    /// Marks or unmarks `topic` as a super-favourite of the current account. No-op without account or topic identity.
    func toggleSuperFavorite(_ topic: TopicSummary) async {
        guard let stores, let account = stores.account, let id = topic.topicID else { return }
        let adding = !superFavorites.contains(id)
        writeGeneration += 1
        do throws(SmallStoreError) {
            if adding {
                _ = try await stores.superFavorites.add(id, account: account)
                superFavorites.insert(id)
            } else {
                _ = try await stores.superFavorites.remove(id, account: account)
                superFavorites.remove(id)
            }
            superWriteProblem = nil
        } catch {
            superWriteProblem = "Impossible d’enregistrer les super favoris."
        }
    }

    /// Places the legacy super-favourites the import left pending (LOT-067 D2): each number `page` lists becomes a
    /// super-favourite in every category where it is listed, as legacy matched the number alone (`Favorites.swift:132-157` @
    /// 87fe0d1c). The list calls it at each load. A failure changes nothing: the numbers stay pending, the next load tries
    /// again, and a super-favourites store that cannot be read is already shown by `reload()`.
    func placePendingSuperFavorites(from page: FavoritesPage) async {
        guard let stores, let account = stores.account, let pending = stores.pending else { return }
        let listed = page.sections.flatMap(\.topics).compactMap(\.topicID)
        guard !listed.isEmpty else { return }
        let placed: Int
        do {
            placed = try await pending.resolveSuperFavorites(listed: listed, account: account, into: stores.superFavorites)
        } catch {
            return
        }
        if placed > 0 { await reload() }
    }

    /// Drops the folded sections `page` no longer has (legacy `pruneCollapsedSections`); an empty page prunes nothing, so a
    /// failed or logged-out load never forgets the user's choices.
    func prune(to page: FavoritesPage) async {
        guard stores != nil, !page.sections.isEmpty else { return }
        let valid = Set(page.sections.map(\.id))
        for section in collapsedSections.subtracting(valid).sorted() {
            await setCollapsed(false, section: section)
        }
    }
}
