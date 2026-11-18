import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The real regular-width iPad root (`RootSidebarView`) in an iPad-sized window, over fakes: what the detail column shows.
@MainActor
@Suite(.serialized)
struct SidebarDetailHostedTests: ReaderWebTesting {
    private struct Hosted {
        let window: UIWindow
        let root: RootModel
        let pages: FakeTopicPages
        let environment: AppEnvironment
    }

    /// Page `target.page` of the topic `target` names, titled "Sujet <topic> p<page>" so a stack shows which reader it holds.
    nonisolated private static func page(for target: ReaderTarget) -> ReaderPage {
        guard case .topic(let topic) = target.source else { return readerPage(page: target.page) }
        var page = readerPage(page: target.page, title: "Sujet \(topic.topic) p\(target.page)")
        page.topicID = topic
        return page
    }

    private func host(initial: SidebarDestination = .tab(.favorites)) throws -> Hosted {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, (1...3).map { favoriteTopic($0) })]) }
        let pages = FakeTopicPages { target in Self.page(for: target) }
        let forums = ForumListModel(dataSource: data)
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: data, forums: forums, topicPages: pages),
            favorites: NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }, topicPages: pages,
                                       startupSource: RootModel.favoritesStartupSource),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), initial: initial
        )
        let services = ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([])
        )
        let environment = AppEnvironment(
            session: HFRSession(), dataSource: data, visibility: ForumVisibility(), currentAccountName: nil, topicPages: pages,
            reader: services, privateMessages: FakePrivateMessages(), composer: nil, filteredPosts: .unavailable,
            favoriteStores: FavoritesStores(
                layout: FavoritesLayoutStore(persistence: InMemorySmallStorePersistence()),
                superFavorites: SuperFavoritesStore(persistence: InMemorySmallStorePersistence()), account: nil
            ),
            flagActions: nil, memberAvatars: nil,
            pseudoListsSnapshot: PseudoListsSnapshot(store: PseudoListStore(persistence: InMemoryPseudoListPersistence()), account: nil),
            blocklistChanges: nil, privateMessageCount: nil
        )
        let view = RootSidebarView(model: root, environment: environment)
            .environment(makeModel(store: InMemoryCredentialStore()))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1366, height: 1024)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        window.layoutIfNeeded()
        return Hosted(window: window, root: root, pages: pages, environment: environment)
    }

    /// The title stacks of the navigation controllers on screen, outermost first: a pushed reader is a second title.
    private func stacks(in window: UIWindow) -> [[String]] {
        var result: [[String]] = []
        var queue: [UIViewController] = window.rootViewController.map { [$0] } ?? []
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            if let navigation = controller as? UINavigationController, navigation.viewIfLoaded?.window != nil {
                result.append(navigation.viewControllers.map { $0.navigationItem.title ?? "" })
            }
            queue.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController { queue.append(presented) }
        }
        return result
    }

    /// The stack whose top shows `title`, nil when no stack on screen shows it on top.
    private func stack(topped title: String, in window: UIWindow) -> [String]? {
        stacks(in: window).first { $0.last == title }
    }

    private func settle(_ window: UIWindow, until condition: () -> Bool) async -> Bool {
        await until({
            window.layoutIfNeeded()
            return condition()
        }, timeout: .seconds(30))
    }

    /// #512 (legacy on iPad, video of 2026-11-07): after a link pushed a reader in the detail column and an edit was sent from it,
    /// tapping other Favoris rows left the pushed reader on screen while the rows turned read. On SwiftHFR the reader column's
    /// stack takes its identity from the selection, so the newly selected topic replaces the whole stack, pushed reader included.
    /// The edit is sent as the composer reports it to the reader (open, HFR's sentence, the reload at the message, closed); the
    /// row tap is the list's selection binding (`TopicListView` writes `selectedTopic`).
    @Test(arguments: [RootTab.favorites, .categories], [true, false])
    func aRowAfterAPushedReaderShowsTheNewTopic(tab: RootTab, sendsEdit: Bool) async throws {
        let hosted = try host(initial: .tab(tab))
        defer { hosted.window.isHidden = true }
        let (window, root, pages) = (hosted.window, hosted.root, hosted.pages)
        let navigation = tab == .favorites ? root.favorites : root.categories
        if tab == .categories {
            navigation.selectedSource = .forum(.forum(13), title: "Catégorie 13")
        }

        navigation.selectedTopic = favoriteTopic(1)
        let first = try #require(navigation.reader(for: favoriteTopic(1)))
        let opened = await settle(window) { first.page != nil && stack(topped: "Sujet 1 p1", in: window) != nil }
        #expect(opened, "\(stacks(in: window))")

        // A link of the post to another page of the topic: a reader pushed in the detail column (LOT-137).
        first.follow(ReaderTarget(source: .topic(try #require(favoriteTopic(1).topicID)), page: 4))
        let linked = try #require(first.linkedReader)
        let pushed = await settle(window) { linked.page != nil && stack(topped: "Sujet 1 p4", in: window)?.count == 2 }
        #expect(pushed, "\(stacks(in: window))")

        // An edit sent from the pushed reader.
        if sendsEdit {
            linked.composer(.edit, isOpen: true)
            linked.showConfirmation("Message édité avec succès")
            await linked.reloadPage(at: 400)
            linked.composer(.edit, isOpen: false)
            #expect(await settle(window) { stack(topped: "Sujet 1 p4", in: window)?.count == 2 })
        }
        let beforeTaps = pages.requests.count

        for number in [2, 3] {
            navigation.selectedTopic = favoriteTopic(number)
            let title = "Sujet \(number) p1"
            let shown = await settle(window) { stack(topped: title, in: window) == [title] }
            #expect(shown, "row \(number): \(stacks(in: window))")
            #expect(stack(topped: "Sujet 1 p4", in: window) == nil, "row \(number): the pushed reader is still on screen")
        }
        // Each row asked for its own topic once, and nothing asked for topic 1 again.
        let expected = try [2, 3].map { ReaderTarget.Source.topic(try #require(favoriteTopic($0).topicID)) }
        #expect(pages.requests.dropFirst(beforeTaps).map(\.source) == expected)
    }

    /// #512, the row menu (LOT-125): "Première page" of the topic on screen while a link's reader is pushed over it. The selection
    /// stays the same topic, only the reader generation changes, so the list's selection cannot reset the column.
    @Test(arguments: [RootTab.favorites, .categories])
    func aRowMenuPageOfTheTopicOnScreenDropsThePushedReader(tab: RootTab) async throws {
        let hosted = try host(initial: .tab(tab))
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        let navigation = tab == .favorites ? root.favorites : root.categories
        if tab == .categories {
            navigation.selectedSource = .forum(.forum(13), title: "Catégorie 13")
        }
        let topic = try #require(favoriteTopic(1).topicID)
        navigation.selectedTopic = favoriteTopic(1)
        let first = try #require(navigation.reader(for: favoriteTopic(1)))
        #expect(await settle(window) { first.page != nil && stack(topped: "Sujet 1 p1", in: window) != nil })
        first.follow(ReaderTarget(source: .topic(topic), page: 4))
        let linked = try #require(first.linkedReader)
        #expect(await settle(window) { linked.page != nil && stack(topped: "Sujet 1 p4", in: window)?.count == 2 })

        navigation.open(favoriteTopic(1), at: TopicOpening(target: ReaderTarget(source: .topic(topic), page: 2)))
        let shown = await settle(window) { stack(topped: "Sujet 1 p2", in: window) == ["Sujet 1 p2"] }
        #expect(shown, "\(stacks(in: window))")
        #expect(stack(topped: "Sujet 1 p4", in: window) == nil)
    }

    /// The split views on screen and their styles.
    private func splitStyles(in window: UIWindow) -> [UISplitViewController.Style] {
        var styles: [UISplitViewController.Style] = []
        var queue: [UIViewController] = window.rootViewController.map { [$0] } ?? []
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            if let split = controller as? UISplitViewController, split.viewIfLoaded?.window != nil { styles.append(split.style) }
            queue.append(contentsOf: controller.children)
        }
        return styles
    }

    /// #685: Bookmarks and Alertes Qualitay list their topics in the content column and open them in the detail column, as
    /// Favoris (legacy `IPadSidebarDestination.usesTopicList`, `MainWindow.swift:1326-1333`, `iPadSidebarRoot` `:1849-1873`
    /// @ 87fe0d1c); Réglages, Rechercher, Crédits, Charte and Supprimer mon compte keep two columns. Réglages, Rechercher and
    /// Supprimer mon compte are left out here: their screens need the app's environment objects; the model test covers every entry.
    @Test(arguments: [PlusEntry.bookmarks, .qualityAlerts, .credits, .charter])
    func aPlusEntryTakesThreeColumnsOnlyWhenItListsTopics(entry: PlusEntry) async throws {
        let hosted = try host(initial: .plus(entry))
        defer { hosted.window.isHidden = true }
        let expected: UISplitViewController.Style = entry == .bookmarks || entry == .qualityAlerts ? .tripleColumn : .doubleColumn
        let laidOut = await settle(hosted.window) { !splitStyles(in: hosted.window).isEmpty }
        #expect(laidOut)
        #expect(splitStyles(in: hosted.window) == [expected], "\(entry): \(stacks(in: hosted.window))")
    }

    /// #685: a row of Alertes Qualitay (or Bookmarks) opens its topic in the detail column and the list stays in the middle; a
    /// second row replaces the whole detail stack, a reader a link had pushed there included (the #512 case on these lists).
    @Test(arguments: [PlusEntry.qualityAlerts, .bookmarks], [false, true])
    func aRowOpensItsTopicInTheDetailColumnBesideTheList(entry: PlusEntry, waits: Bool) async throws {
        let hosted = try host(initial: .plus(entry))
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        let open = RootSidebarView.detailOpener(model: root, environment: hosted.environment, entry: entry)

        let topic = TopicID(category: .forum(13), topic: 5)
        open(ReaderTarget(source: .topic(topic)), title: "Sujet 5")
        let reader = try #require(root.detailReaders[entry])
        let opened = await settle(window) { reader.page != nil && stack(topped: "Sujet 5 p1", in: window) == ["Sujet 5 p1"] }
        #expect(opened, "\(stacks(in: window))")
        #expect(stack(topped: entry.title, in: window) != nil, "the list left the content column: \(stacks(in: window))")
        #expect(splitStyles(in: window) == [.tripleColumn])

        reader.follow(ReaderTarget(source: .topic(topic), page: 4))
        let linked = try #require(reader.linkedReader)
        let pushed = await settle(window) { linked.page != nil && stack(topped: "Sujet 5 p4", in: window)?.count == 2 }
        #expect(pushed, "\(stacks(in: window))")
        if waits { try await Task.sleep(for: .seconds(1)) }

        open(ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 6))), title: "Sujet 6")
        let replaced = await settle(window) { stack(topped: "Sujet 6 p1", in: window) == ["Sujet 6 p1"] }
        #expect(replaced, "\(stacks(in: window))")
        #expect(stack(topped: "Sujet 5 p4", in: window) == nil)
        #expect(stack(topped: entry.title, in: window) != nil)
    }
}
