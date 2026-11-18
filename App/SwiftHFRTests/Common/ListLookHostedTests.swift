import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The iPhone root with fixture data, as `RootTabsView` builds it, and what a test reads from it.
@MainActor
private struct HostedRoot {
    let window: UIWindow
    let model: RootModel
    let data: FakeDataSource
    let experimental: ExperimentalSettings
}

/// #1107: one look drives every list. Classic (« Lignes denses » off): the Favoris card, rows on a card inset from the screen
/// edge. Dense (on): no card, the rows from one side to the other on the screen's background. Measured on the real iPhone root:
/// Catégories, a category's topics, Favoris and Messages.
@MainActor
@Suite(.serialized)
struct ListLookHostedTests {
    nonisolated private static let topics: [TopicSummary] = [
        TopicSummary(topicID: TopicID(category: .forum(23), topic: 1), title: "Sujet un", path: "/t1", readState: .read),
        TopicSummary(topicID: TopicID(category: .forum(23), topic: 2), title: "Sujet deux", path: "/t2", readState: .read)
    ]

    private func host(dense: Bool, dark: Bool = false) async throws -> HostedRoot {
        let data = FakeDataSource()
        data.forumHandler = {
            ForumListPage(forums: [
                ForumCategory(categoryID: .forum(1), title: "Hardware", path: "/hfr/Hardware/liste_sujet-1.htm"),
                ForumCategory(categoryID: .forum(23), title: "Apple", path: "/hfr/apple/liste_sujet-1.htm")
            ], isLoggedIn: true)
        }
        data.topicHandler = { _, page in TopicListPage(topics: Self.topics, navigation: PageNavigation(current: page)) }
        data.favoritesHandler = { _ in
            FavoritesPage(sections: [
                FavoriteSection(forum: ForumLink(title: "Apple", path: "/a"), categoryID: .forum(23), topics: Self.topics)
            ])
        }
        let messages = FakePrivateMessages()
        messages.handler = { _ in
            PrivateMessageListPage(threads: [messageThread(12), messageThread(13)], navigation: PageNavigation(current: 1, isExact: true))
        }
        let store = InMemorySettingsStore()
        let forums = ForumListModel(dataSource: data)
        let model = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }),
            favorites: NavigationModel(
                dataSource: data, forums: forums, sessionIsLoggedIn: { true }, startupSource: .favorites,
                favorites: FavoritesOptionsModel(settings: InMemorySettingsStore())
            ),
            messages: MessageListModel(source: messages, isLoggedIn: { true }), store: store, initial: .tab(.categories)
        )
        let experimentalStore = InMemorySettingsStore()
        experimentalStore.set(dense, for: SettingKey.experimentalDenseRows)
        let experimental = ExperimentalSettings(store: experimentalStore)
        let root = RootTabsView(model: model, environment: AppEnvironment.make(session: HFRSession(), accountName: nil))
            .environment(makeModel(store: InMemoryCredentialStore()))
            .environment(experimental)
            .appTypography(.standard, density: .regular)
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        return HostedRoot(window: window, model: model, data: data, experimental: experimental)
    }

    private static func lists(_ view: UIView) -> [UICollectionView] {
        ((view as? UICollectionView).map { [$0] } ?? []) + view.subviews.flatMap(lists)
    }

    /// The on-screen cell whose accessibility tree has an element labelled `label` (or starting with it).
    private static func cell(_ label: String, in window: UIWindow) -> UICollectionViewCell? {
        for list in lists(window) where !list.isHidden && list.window != nil {
            for cell in list.visibleCells {
                let frame = cell.convert(cell.bounds, to: window)
                guard frame.minX >= -1, frame.maxX <= window.bounds.width + 1 else { continue }
                if HostedAccessibility.elements(under: cell).contains(where: { $0.accessibilityLabel?.hasPrefix(label) == true }) {
                    return cell
                }
            }
        }
        return nil
    }

    /// The frame of the cell of `label`, polled until it shows.
    private func frame(of label: String, in window: UIWindow) async throws -> CGRect {
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            if let cell = Self.cell(label, in: window) {
                try await Task.sleep(for: .milliseconds(200))
                window.layoutIfNeeded()
                return (Self.cell(label, in: window) ?? cell).convert(cell.bounds, to: window)
            }
        }
        throw HostedListLookError.noRow(label)
    }

    /// Taps the row of `label` as the list's delegate gets a tap.
    private func tap(_ label: String, in window: UIWindow) async throws {
        _ = try await frame(of: label, in: window)
        for list in Self.lists(window) {
            for cell in list.visibleCells where HostedAccessibility.elements(under: cell)
                .contains(where: { $0.accessibilityLabel?.hasPrefix(label) == true }) {
                guard let path = list.indexPath(for: cell) else { continue }
                list.selectItem(at: path, animated: false, scrollPosition: [])
                list.delegate?.collectionView?(list, didSelectItemAt: path)
                return
            }
        }
        throw HostedListLookError.noRow(label)
    }

    /// The colour of the window at `point`.
    private static func colour(of window: UIWindow, at point: CGPoint) -> [UInt8] {
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

    /// One list's row as measured: its frame, the colour inside it near its right end, and (classic only) the colour just left
    /// of it, the screen's background.
    private struct Measure {
        let frame: CGRect
        let inside: [UInt8]
        let beside: [UInt8]?
    }

    private func measure(_ label: String, in window: UIWindow) async throws -> Measure {
        let frame = try await frame(of: label, in: window)
        let inside = Self.colour(of: window, at: CGPoint(x: frame.maxX - 3, y: frame.midY))
        let beside = frame.minX >= 6 ? Self.colour(of: window, at: CGPoint(x: frame.minX - 4, y: frame.midY)) : nil
        return Measure(frame: frame, inside: inside, beside: beside)
    }

    /// The large-title row of the screen on show: the topmost cell of the list that shows « Hardware ».
    private func titleRow(in window: UIWindow) throws -> Measure {
        let row = try #require(Self.cell("Hardware", in: window), "no Catégories row")
        let list = try #require(Self.lists(window).first { $0.visibleCells.contains(row) }, "no list")
        let title = try #require(list.visibleCells.min { $0.frame.minY < $1.frame.minY }, "no title")
        let frame = title.convert(title.bounds, to: window)
        let inside = Self.colour(of: window, at: CGPoint(x: frame.maxX - 3, y: frame.midY))
        let beside = frame.minX >= 6 ? Self.colour(of: window, at: CGPoint(x: frame.minX - 4, y: frame.midY)) : nil
        return Measure(frame: frame, inside: inside, beside: beside)
    }

    /// The four lists of the root, each by a plain (untinted) row: Catégories, a category's topics, Favoris, Messages.
    private func measureEveryList(dense: Bool, dark: Bool = false) async throws -> [String: Measure] {
        let hosted = try await host(dense: dense, dark: dark)
        defer { hosted.window.isHidden = true }
        HostedAccessibility.beginAutomation()
        defer { HostedAccessibility.endAutomation() }
        var found: [String: Measure] = [:]
        found["Catégories"] = try await measure("Hardware", in: hosted.window)
        found["title"] = try titleRow(in: hosted.window)
        try await tap("Apple", in: hosted.window)
        found["topics"] = try await measure("Sujet deux", in: hosted.window)
        hosted.model.selectedDestination = .tab(.favorites)
        found["Favoris"] = try await measure("Sujet deux", in: hosted.window)
        hosted.model.selectedDestination = .tab(.messages)
        found["Messages"] = try await measure("Sujet 13", in: hosted.window)
        return found
    }

    @Test("Classic: every list draws its rows on a card inset from the screen edge, the Favoris look")
    func classicIsTheCardEverywhere() async throws {
        let found = try await measureEveryList(dense: false)
        let favoris = try #require(found["Favoris"])
        for (list, row) in found where list != "title" {
            #expect(row.frame.minX >= 16, "\(list): the card starts at \(row.frame.minX)")
            #expect(row.frame.minX == favoris.frame.minX && row.frame.width == favoris.frame.width, "\(list) \(row.frame)")
            #expect(row.beside != nil && row.beside != row.inside, "\(list): no card, \(row)")
        }
    }

    /// The plain list's background, the system background: white in light (the grouped list's is grey), black in dark (the
    /// card's is dark grey).
    nonisolated private static func plainBackground(dark: Bool) -> [UInt8] { dark ? [0, 0, 0] : [255, 255, 255] }

    /// Light tells the plain background from the grouped grey; dark tells a row with no card from a card (white in light).
    @Test(
        "Dense: every list draws its rows, its large title included, side to side on the plain background, with no card",
        arguments: [false, true]
    )
    func denseHasNoCard(dark: Bool) async throws {
        let dense = try await measureEveryList(dense: true, dark: dark)
        for (list, row) in dense {
            #expect(row.frame.minX == 0 && row.frame.width == 402, "\(list): \(row.frame)")
            #expect(row.inside == Self.plainBackground(dark: dark), "\(list), dark \(dark): the row is drawn on \(row.inside)")
        }
    }

    /// Comptes: the account rows and the « Ajouter un compte » section, a row that is not a `ForEach` row.
    private func accountsAddRow(dense: Bool, dark: Bool) async throws -> Measure {
        let store = InMemorySettingsStore()
        store.set(dense, for: SettingKey.experimentalDenseRows)
        let host = UIHostingController(rootView: AccountsView()
            .environment(makeModel(store: InMemoryCredentialStore()))
            .environment(ExperimentalSettings(store: store)))
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        HostedAccessibility.beginAutomation()
        defer { HostedAccessibility.endAutomation() }
        return try await measure("Ajouter un compte", in: window)
    }

    @Test("Dense: a row outside the list's ForEach (Comptes › « Ajouter un compte ») loses its card too", arguments: [false, true])
    func denseCoversEveryRowOfAList(dark: Bool) async throws {
        let classic = try await accountsAddRow(dense: false, dark: dark)
        let dense = try await accountsAddRow(dense: true, dark: dark)
        #expect(classic.frame.minX >= 16 && classic.beside != classic.inside, "classic \(classic)")
        #expect(dense.frame.minX == 0 && dense.inside == Self.plainBackground(dark: dark), "dense, dark \(dark): \(dense)")
    }

    @Test("Dense: a category row is shorter than in the classic look, its icon kept")
    func denseCategoriesAreShorter() async throws {
        let classic = try await measureEveryList(dense: false)
        let dense = try await measureEveryList(dense: true)
        let classicHeight = try #require(classic["Catégories"]?.frame.height)
        let denseHeight = try #require(dense["Catégories"]?.frame.height)
        #expect(denseHeight <= classicHeight - 8, "classic \(classicHeight), dense \(denseHeight)")
    }

    @Test("Switching « Lignes denses » redraws Favoris in the other look without reloading it")
    func switchingKeepsTheList() async throws {
        let hosted = try await host(dense: false)
        defer { hosted.window.isHidden = true }
        HostedAccessibility.beginAutomation()
        defer { HostedAccessibility.endAutomation() }
        hosted.model.selectedDestination = .tab(.favorites)
        let classic = try await measure("Sujet deux", in: hosted.window)
        try await Task.sleep(for: .milliseconds(500))
        let requests = hosted.data.requests.count
        hosted.experimental.set(.denseRows, isOn: true)
        var dense = classic
        for _ in 0..<40 where dense.frame.minX != 0 {
            dense = try await measure("Sujet deux", in: hosted.window)
        }
        #expect(classic.frame.minX >= 16 && dense.frame.minX == 0, "classic \(classic.frame), dense \(dense.frame)")
        #expect(hosted.data.requests.count == requests, "the switch reloaded: \(hosted.data.requests)")
    }
}

private enum HostedListLookError: Error {
    case noRow(String)
}
