import Foundation
import HFRModels
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// A topic list of one forum on a filter, hosted as a window.
struct HostedFilteredList {
    let window: UIWindow
    let model: TopicListModel
    let page: TopicListPage
}

/// What each filter shows comes from a captured page (anonymized fixtures of `HFRParsingTests`), parsed by the engine's parser.
enum FilterCapture: CaseIterable {
    case all, favorites, tracked, read

    var flag: TopicListFlag {
        switch self {
        case .all: .all
        case .favorites: .favorites
        case .tracked: .tracked
        case .read: .read
        }
    }

    /// The capture of the forum's list on this filter. Only "Lus" (`owntopic=2`) has a logged-in capture with rows: Suivis and
    /// Favoris were captured empty (R08-1, R08-3), so they show the list's empty state, not a hand-built page (LESSONS 36).
    var capture: String {
        switch self {
        case .all: "R04-list-cat13-p1-anon"
        case .favorites: "R08-3-list-cat13-owntopic3-empty"
        case .tracked: "R08-1-list-cat13-owntopic1-empty"
        case .read: "R08-2-list-cat13-owntopic2"
        }
    }

    var pageURL: String {
        "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=" + (flag == .all ? "" : "&owntopic=\(flag.filter.rawValue)")
    }

    func page(file: String = #filePath) throws -> TopicListPage {
        var root = URL(filePath: file)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let url = root.appending(path: "Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/\(capture).html")
        return try TopicListParser.parse(String(decoding: Data(contentsOf: url), as: UTF8.self), pageURL: pageURL)
    }
}

/// #870: the four filters of a forum's list (Tous, Favoris, Suivis, Lus) draw through one list and one row component; they differ
/// only by what legacy's `topicHasFlag` gates.
@MainActor
@Suite(.serialized)
struct TopicFilterListHostedTests {
    static func host(
        _ filter: FilterCapture, width: CGFloat = 402, style: UIUserInterfaceStyle = .light
    ) async throws -> HostedFilteredList {
        let page = try filter.page()
        let data = FakeDataSource()
        data.topicHandler = { _, _ in page }
        let store = InMemorySettingsStore()
        let topicFilter = TopicFilterModel(settings: store)
        topicFilter.flag = filter.flag
        let model = TopicListModel(
            source: .forum(.forum(13), title: "Discussions"), dataSource: data, isLoggedIn: { true }, topicFilter: topicFilter
        )
        let scope = ForumScope(section: { nil }, filter: topicFilter, select: { _ in })
        var selection: TopicSummary?
        let root = NavigationStack {
            TopicListView(model: model, selection: Binding(get: { selection }, set: { selection = $0 }), scope: scope)
        }
        .environment(ExperimentalSettings(store: InMemorySettingsStore()))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 874)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        await model.loadIfNeeded()
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }
        return HostedFilteredList(window: window, model: model, page: page)
    }

    @Test("Every filter draws its topics through the shared list and row, once each (#870)", arguments: FilterCapture.allCases)
    func everyFilterUsesTheSharedListAndRows(filter: FilterCapture) async throws {
        let hosted = try await Self.host(filter)
        defer { hosted.window.isHidden = true }
        #expect(hosted.model.loadedFilter == filter.flag.filter)
        let builds = TopicListView.renders[ObjectIdentifier(hosted.model)] ?? [:]
        #expect((builds[.body] ?? 0) > 0)
        // One `TopicRowView` build site: every loaded row reached it, on every filter.
        for topic in hosted.page.topics { #expect((builds[.row(topic.id)] ?? 0) > 0, "no row build for \(topic.id)") }
        if filter == .read { #expect(!hosted.page.topics.isEmpty) }
        // The Tous / Favoris / Suivis / Lus control is the one `TopicFlagFilterPicker` of `ForumScopeBar`.
        let labels = HostedAccessibility.elements(under: hosted.window).compactMap(\.accessibilityLabel)
        for title in ["Tous", "Favoris", "Suivis", "Lus"] { #expect(labels.contains(title), "\(title) not in \(labels)") }
    }
}
