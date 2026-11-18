import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1073, #648: in the regular-width iPad root, Favoris (the topic list) shows the rounded block of Catégories and Messages on
/// the same column background. Left on the automatic style, the topic list was a plain list there (white column, no block)
/// while the two others are inset-grouped (grey column, white block); on an iPhone the automatic style is that block already.
@MainActor
@Suite(.serialized)
struct RegularWidthListStyleTests {
    private func rootModel(favorites topics: [TopicSummary] = [topicSummary(1)]) -> RootModel {
        let data = FakeDataSource()
        data.forumHandler = {
            ForumListPage(forums: [ForumCategory(categoryID: .forum(13), title: "Discussions", path: "/hfr/Discussions/liste_sujet-1.htm")])
        }
        data.favoritesHandler = { _ in
            FavoritesPage(sections: [
                FavoriteSection(forum: ForumLink(title: "Discussions", path: "/d"), categoryID: .forum(13), topics: topics)
            ])
        }
        let forums = ForumListModel(dataSource: data)
        return RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }),
            favorites: NavigationModel(
                dataSource: data, forums: forums, sessionIsLoggedIn: { true }, startupSource: .favorites,
                favorites: FavoritesOptionsModel(settings: InMemorySettingsStore())
            ),
            messages: MessageListModel(source: FakePrivateMessages(), isLoggedIn: { true }),
            store: InMemorySettingsStore(), initial: .tab(.categories)
        )
    }

    /// The colour of the window at `point`, light appearance.
    private func colour(of window: UIWindow, at point: CGPoint) -> [UInt8] {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else { return [] }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: -point.x, y: point.y - CGFloat(cgImage.height) + 1,
                                             width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
            return true
        }
        return drawn ? Array(pixel.prefix(3)) : []
    }

    /// The content column's list: the widest one (the sidebar's is narrower).
    private func contentList(in view: UIView) -> UICollectionView? {
        func lists(_ view: UIView) -> [UICollectionView] {
            ((view as? UICollectionView).map { [$0] } ?? []) + view.subviews.flatMap(lists)
        }
        return lists(view).max { $0.bounds.width < $1.bounds.width }
    }

    /// For each list of the iPad root (Catégories, Favoris, Messages), the colours beside and inside its last row: the column
    /// 4 pt left of the row, and the row itself 3 pt above its bottom. An inset-grouped list puts its rows in a block on the
    /// grouped background, so the two differ; a plain list's rows span the column, so they are the same.
    private func lastRowColours() async throws -> [RootTab: (beside: [UInt8], inside: [UInt8])] {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let model = rootModel()
        let host = UIHostingController(rootView: RootSidebarView(
            model: model, environment: AppEnvironment.make(session: HFRSession(), accountName: nil)
        )
        .environment(makeModel(store: InMemoryCredentialStore())))
        host.overrideUserInterfaceStyle = .light
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var found: [RootTab: (beside: [UInt8], inside: [UInt8])] = [:]
        var previous: UICollectionView?
        for tab in [RootTab.categories, .favorites, .messages] {
            model.selectedDestination = .tab(tab)
            // Polls until this tab's list (not the previous one's) shows its title and a row (a cold simulator can take a while).
            var shown: UICollectionView?
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(50))
                window.layoutIfNeeded()
                if let list = contentList(in: window), list !== previous, list.visibleCells.count >= 2 {
                    shown = list
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(300))
            window.layoutIfNeeded()
            let list = try #require(shown, "no list with rows in \(tab)")
            previous = list
            let last = try #require(list.visibleCells.max { $0.frame.maxY < $1.frame.maxY }, "no row in \(tab)")
            let frame = last.convert(last.bounds, to: nil)
            found[tab] = (
                colour(of: window, at: CGPoint(x: frame.minX - 4, y: frame.midY)),
                colour(of: window, at: CGPoint(x: frame.midX, y: frame.maxY - 3))
            )
        }
        return found
    }

    @Test func favorisShowsTheBlockOfCategoriesAndMessages() async throws {
        let found = try await lastRowColours()
        let categories = try #require(found[.categories])
        #expect(categories.beside.count == 3 && categories.beside != categories.inside, "Catégories \(categories)")
        for tab in [RootTab.favorites, .messages] {
            let colours = try #require(found[tab])
            #expect(colours.beside == categories.beside, "\(tab) \(colours), Catégories \(categories)")
            #expect(colours.beside != colours.inside, "\(tab): no block, the row spans the column \(colours)")
        }
    }

    /// #1107: the dense look draws its rows on a clear background, which would hide the list's own selection in an iPad
    /// column; the selected topic keeps a highlight there.
    @Test func denseLookKeepsTheSelectedTopicHighlighted() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let model = rootModel(favorites: [topicSummary(1), topicSummary(2)])
        let experimentalStore = InMemorySettingsStore()
        experimentalStore.set(true, for: SettingKey.experimentalDenseRows)
        let host = UIHostingController(rootView: RootSidebarView(
            model: model, environment: AppEnvironment.make(session: HFRSession(), accountName: nil)
        )
        .environment(makeModel(store: InMemoryCredentialStore()))
        .environment(ExperimentalSettings(store: experimentalStore)))
        host.overrideUserInterfaceStyle = .light
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1376, height: 1032)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        model.selectedDestination = .tab(.favorites)
        var rows: [UICollectionViewCell] = []
        for _ in 0..<100 where rows.count < 3 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            rows = contentList(in: window)?.visibleCells.sorted { $0.frame.minY < $1.frame.minY } ?? []
        }
        model.favorites.selectedTopic = topicSummary(1)
        try await Task.sleep(for: .milliseconds(800))
        window.layoutIfNeeded()
        // The two topic rows are the list's last two cells (the large title and the section come first).
        let cells = try #require(contentList(in: window)?.visibleCells.sorted { $0.frame.minY < $1.frame.minY }, "no list")
        try #require(cells.count >= 2, "rows \(cells.count)")
        let selected = cells[cells.count - 2].convert(cells[cells.count - 2].bounds, to: nil)
        let other = cells[cells.count - 1].convert(cells[cells.count - 1].bounds, to: nil)
        let selectedColour = colour(of: window, at: CGPoint(x: selected.maxX - 3, y: selected.maxY - 3))
        let otherColour = colour(of: window, at: CGPoint(x: other.maxX - 3, y: other.maxY - 3))
        #expect(selectedColour.count == 3 && selectedColour != otherColour, "selected \(selectedColour), other \(otherColour)")
    }
}
