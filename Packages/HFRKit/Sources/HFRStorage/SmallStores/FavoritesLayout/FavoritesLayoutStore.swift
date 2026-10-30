import Foundation

/// Which favourites sections are collapsed, on this device (LOT-064).
///
/// Legacy kept the ids in `UserDefaults` (`CollapsedFavoriteSectionIDs`, `Favorites.swift:139-155`): trimmed, empty ids
/// dropped, saved sorted. The visible and hidden category order of the Objective-C screen
/// (`arrayCategoriesVisibleOrder`, `arrayCategoriesHiddenOrder`) is not ported: ADR 0013 §8 drops it.
public actor FavoritesLayoutStore {
    private var state: SmallStoreState<FavoritesLayoutDocument>

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<FavoritesLayoutDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    /// The collapsed sections; empty (all expanded) while the stored data is unreadable.
    public func collapsedSections() -> Set<String> {
        Set(state.document()?.collapsedSections ?? [])
    }

    /// Whether `section` is collapsed. The identifier is compared trimmed.
    public func isCollapsed(_ section: String) -> Bool {
        collapsedSections().contains(Self.trimmed(section))
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    /// Collapses or expands `section`. Returns false when it already was in that state.
    @discardableResult
    public func setCollapsed(_ collapsed: Bool, section: String) throws(SmallStoreError) -> Bool {
        let identifier = Self.trimmed(section)
        guard !identifier.isEmpty else { throw .invalidValue(reason: "empty section identifier") }
        return try state.mutate { document in
            var sections = Set(document.collapsedSections)
            let changed = collapsed ? sections.insert(identifier).inserted : sections.remove(identifier) != nil
            document.collapsedSections = sections.sorted()
            return changed
        }
    }

    /// Reads the stored data again, for example after the user restored a file. Returns the failure if any.
    @discardableResult
    public func reload() -> SmallStoreError? {
        state.reload()
    }

    /// Sets the unreadable data aside (a `.corrupt` copy for files, never a deletion) and starts with every section
    /// expanded. Only call it after the user agreed: this is the single way out of a failed load.
    public func discardUnreadableData() throws(SmallStoreError) {
        try state.discardUnreadableData()
    }

    private static func trimmed(_ section: String) -> String {
        section.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
