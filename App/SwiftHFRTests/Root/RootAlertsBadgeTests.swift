import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// GAP-005: legacy shows the new-AQ count on the Plus tab and on its "Alertes Qualitay" row, nowhere else (LOT-133).
@MainActor
struct RootAlertsBadgeTests {
    private func root(qualityAlerts: QualityAlertsModel? = nil) -> RootModel {
        let source = FakeDataSource()
        let forums = ForumListModel(dataSource: source)
        return RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: source, forums: forums, startupSource: RootModel.categoriesStartupSource),
            favorites: NavigationModel(dataSource: source, forums: forums, startupSource: TopicSource(mode: .flagsAndFavorites)),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), qualityAlerts: qualityAlerts
        )
    }

    @Test func theNewAlertsCountIsTheBadgeOfThePlusTabAndOfItsRowOnly() async throws {
        let alerts = QualityAlertsTestSupport.model(
            source: FakeQualityAlertsSource(items: try QualityAlertsTestSupport.capturedItems())
        )
        let root = root(qualityAlerts: alerts)
        #expect(root.plusBadge == 0)
        await root.qualityAlerts.checkAtLaunch(sleep: { _ in })
        #expect(root.plusBadge == 25)
        #expect(PlusEntry.allCases.map { root.badge(for: $0) } == [0, 0, 0, 25, 0, 0, 0])
        await root.qualityAlerts.load()
        #expect(root.plusBadge == 0)
    }

    @Test func aRootWithoutAnAQAddressHasNoBadge() async {
        let root = root()
        await root.qualityAlerts.checkAtLaunch(sleep: { _ in })
        #expect(root.plusBadge == 0)
    }
}
