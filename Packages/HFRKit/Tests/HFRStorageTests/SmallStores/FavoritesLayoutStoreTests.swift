import Testing
@testable import HFRStorage

/// Collapsed favourites sections: legacy `CollapsedFavoriteSectionIDs` rules (`Favorites.swift:139-155`).
@Suite struct FavoritesLayoutStoreTests {
    @Test func collapseThenExpand() async throws {
        let persistence = InMemorySmallStorePersistence<FavoritesLayoutDocument>()
        let store = FavoritesLayoutStore(persistence: persistence)
        #expect(await !store.isCollapsed("13"))
        #expect(try await store.setCollapsed(true, section: "13"))
        #expect(await store.isCollapsed("13"))
        #expect(try await store.setCollapsed(false, section: "13"))
        #expect(await !store.isCollapsed("13"))
        #expect(persistence.document?.collapsedSections == [])
    }

    @Test func identifiersAreTrimmedAndSavedSortedOnce() async throws {
        let persistence = InMemorySmallStorePersistence<FavoritesLayoutDocument>()
        let store = FavoritesLayoutStore(persistence: persistence)
        for section in [" 5\n", "13", "1", "7", "40", "2", "10", "3"] {
            try await store.setCollapsed(true, section: section)
        }
        #expect(persistence.document?.collapsedSections == ["1", "10", "13", "2", "3", "40", "5", "7"])
        #expect(await store.isCollapsed("5"))
        #expect(await store.isCollapsed("  13 "))
        #expect(await store.collapsedSections() == ["1", "10", "13", "2", "3", "40", "5", "7"])
    }

    @Test func noChangeSavesNothing() async throws {
        let persistence = FailingSmallStorePersistence<FavoritesLayoutDocument>()
        let store = FavoritesLayoutStore(persistence: persistence)
        try await store.setCollapsed(true, section: "13")
        #expect(try await !store.setCollapsed(true, section: "13 "))
        #expect(try await !store.setCollapsed(false, section: "5"))
        #expect(persistence.saveCount == 1)
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func anEmptyIdentifierIsRefused(section: String) async throws {
        let persistence = FailingSmallStorePersistence<FavoritesLayoutDocument>()
        let store = FavoritesLayoutStore(persistence: persistence)
        await #expect(throws: SmallStoreError.invalidValue(reason: "empty section identifier")) {
            try await store.setCollapsed(true, section: section)
        }
        #expect(persistence.saveCount == 0)
    }

    @Test func identifiersStoredByAnotherWriterAreReadAsLegacyLoadedThem() async throws {
        let persistence = InMemorySmallStorePersistence(FavoritesLayoutDocument(collapsedSections: [" 13 ", "", "\n", "5", "5"]))
        let store = FavoritesLayoutStore(persistence: persistence)
        #expect(await store.collapsedSections() == ["13", "5"])
        #expect(await store.isCollapsed("13"))
        #expect(try await store.setCollapsed(false, section: "13"))
        #expect(persistence.document?.collapsedSections == ["5"])
    }
}
