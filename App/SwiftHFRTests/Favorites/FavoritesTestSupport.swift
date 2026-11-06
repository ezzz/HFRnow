import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR

/// A topic of category `category` numbered `number`, last posted `day` days after the reference date (nil: undated).
func favoriteTopic(_ number: Int, category: Int = 13, day: Int? = nil) -> TopicSummary {
    TopicSummary(
        topicID: TopicID(category: .forum(category), topic: number), title: "Sujet \(number)", path: "/t\(category)-\(number)",
        lastPost: day.map { LastPost(author: "a", path: "/p", date: Date(timeIntervalSinceReferenceDate: Double($0) * 86_400)) }
    )
}

/// A category section of the favourites page; its id is `cat:<category>`.
func favoriteSection(_ category: Int, _ topics: [TopicSummary]) -> FavoriteSection {
    FavoriteSection(forum: ForumLink(title: "Catégorie \(category)", path: "/c\(category)"), categoryID: .forum(category), topics: topics)
}

/// Options and stores over memory, for one account.
@MainActor
func favoritesOptions(
    settings: InMemorySettingsStore = InMemorySettingsStore(), account: String? = "user1",
    layout: InMemorySmallStorePersistence<FavoritesLayoutDocument> = InMemorySmallStorePersistence(),
    supers: InMemorySmallStorePersistence<SuperFavoritesDocument> = InMemorySmallStorePersistence()
) -> FavoritesOptionsModel {
    FavoritesOptionsModel(
        settings: settings,
        stores: FavoritesStores(
            layout: FavoritesLayoutStore(persistence: layout), superFavorites: SuperFavoritesStore(persistence: supers), account: account
        )
    )
}
