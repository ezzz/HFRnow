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

    /// The process-wide stores, over `Application Support/Favorites/`.
    static let shared = (
        layout: FavoritesLayoutStore(persistence: FileSmallStorePersistence(fileURL: file("layout.json"))),
        superFavorites: SuperFavoritesStore(persistence: FileSmallStorePersistence(fileURL: file("super-favorites.json")))
    )

    /// The live stores for `account` (nil when logged out: nothing can be marked then).
    static func live(account: String?) -> FavoritesStores {
        FavoritesStores(layout: shared.layout, superFavorites: shared.superFavorites, account: account)
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
        didSet { if groupedByCategory != oldValue { settings.set(groupedByCategory, for: SettingKey.favoritesGroupedByCategory) } }
    }
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

    /// Folded sections (device-wide).
    private(set) var collapsedSections: Set<String> = []
    /// Super-favourites of the current account.
    private(set) var superFavorites: Set<TopicID> = []
    /// What the last store write or read could not do, in French; nil when everything worked.
    private(set) var storeProblem: String?

    @ObservationIgnored private let settings: any SettingsStore
    @ObservationIgnored private let stores: FavoritesStores?

    /// Reads the four settings from `settings`. Without `stores` (Réglages), only the settings work.
    init(settings: any SettingsStore, stores: FavoritesStores? = nil) {
        self.settings = settings
        self.stores = stores
        mode = settings.value(for: SettingKey.favoritesSource)
        groupedByCategory = settings.value(for: SettingKey.favoritesGroupedByCategory)
        autoRefresh = settings.value(for: SettingKey.favoritesAutoRefresh)
        showsCollapsedSections = settings.value(for: SettingKey.favoritesShowsCollapsedSections)
    }

    /// Whether the account can mark super-favourites (logged in, stores available).
    var canMarkSuperFavorites: Bool { stores?.account != nil }

    /// Legacy `shouldShowEmptyFavoriteSections`: the toggle also reveals the empty categories, but only in "Drapeaux & Favoris".
    /// Whatever the sort, so the toggle works the same grouped or flat (a flat list has no section to reveal).
    var showsEmptySections: Bool { showsCollapsedSections && mode == .flagsAndFavorites }

    /// The layout the settings ask for.
    var layout: FavoritesLayoutOptions {
        FavoritesLayoutOptions(
            groupedByCategory: groupedByCategory, showsCollapsedSections: showsCollapsedSections, showsEmptySections: showsEmptySections
        )
    }

    /// The groups of `page` under the current options, folded sections and super-favourites.
    func groups(for page: FavoritesPage) -> [TopicGroup] {
        FavoritesPresentation.groups(of: page, options: layout, collapsed: collapsedSections, superFavorites: superFavorites)
    }

    /// Whether any section of `page` can be folded.
    func hasCollapsibleSections(in page: FavoritesPage) -> Bool {
        groupedByCategory && !FavoritesPresentation.collapsibleSectionIDs(of: page, superFavorites: superFavorites).isEmpty
    }

    /// Reads the settings again (Réglages may have changed them).
    func reloadSettings() {
        mode = settings.value(for: SettingKey.favoritesSource)
        groupedByCategory = settings.value(for: SettingKey.favoritesGroupedByCategory)
        autoRefresh = settings.value(for: SettingKey.favoritesAutoRefresh)
        showsCollapsedSections = settings.value(for: SettingKey.favoritesShowsCollapsedSections)
    }

    /// Reads the folded sections and the super-favourites again; the list calls it each time it shows (legacy `onAppear`).
    func reload() async {
        reloadSettings()
        guard let stores else { return }
        let collapsed = await stores.layout.collapsedSections()
        var problem = await stores.layout.loadFailure()
        var supers: Set<TopicID> = []
        if let account = stores.account {
            supers = Set(await stores.superFavorites.favorites(for: account).map(\.topic))
            if problem == nil { problem = await stores.superFavorites.loadFailure() }
        }
        if collapsed != collapsedSections { collapsedSections = collapsed }
        if supers != superFavorites { superFavorites = supers }
        storeProblem = problem.map { _ in "Les préférences des favoris sont illisibles." }
    }

    /// Folds or unfolds a section.
    func toggleCollapsed(_ section: String) async {
        guard let stores else { return }
        let collapse = !collapsedSections.contains(section)
        do throws(SmallStoreError) {
            _ = try await stores.layout.setCollapsed(collapse, section: section)
            if collapse { collapsedSections.insert(section) } else { collapsedSections.remove(section) }
        } catch {
            storeProblem = "Impossible d’enregistrer les sections repliées."
        }
    }

    /// Folds every section of `page` that has a topic (legacy "Tout replier").
    func collapseAll(in page: FavoritesPage) async {
        for section in FavoritesPresentation.collapsibleSectionIDs(of: page, superFavorites: superFavorites).sorted()
        where !collapsedSections.contains(section) {
            await toggleCollapsed(section)
        }
    }

    /// Unfolds every section (legacy "Tout déplier").
    func expandAll() async {
        for section in collapsedSections.sorted() { await toggleCollapsed(section) }
    }

    /// Marks or unmarks `topic` as a super-favourite of the current account. No-op without account or topic identity.
    func toggleSuperFavorite(_ topic: TopicSummary) async {
        guard let stores, let account = stores.account, let id = topic.topicID else { return }
        let adding = !superFavorites.contains(id)
        do throws(SmallStoreError) {
            if adding {
                _ = try await stores.superFavorites.add(id, account: account)
                superFavorites.insert(id)
            } else {
                _ = try await stores.superFavorites.remove(id, account: account)
                superFavorites.remove(id)
            }
        } catch {
            storeProblem = "Impossible d’enregistrer les super favoris."
        }
    }

    /// Drops the folded sections `page` no longer has (legacy `pruneCollapsedSections`); an empty page prunes nothing, so a
    /// failed or logged-out load never forgets the user's choices.
    func prune(to page: FavoritesPage) async {
        guard let stores, !page.sections.isEmpty else { return }
        let valid = Set(page.sections.map(\.id))
        for section in collapsedSections.subtracting(valid).sorted() {
            do throws(SmallStoreError) {
                _ = try await stores.layout.setCollapsed(false, section: section)
                collapsedSections.remove(section)
            } catch {
                storeProblem = "Impossible d’enregistrer les sections repliées."
            }
        }
    }
}
