//
//  ContentView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class CategoriesListViewModel: ObservableObject {
    @Published var forums: [Forum] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let forumsLoader: ForumsLoading

    init(forumsLoader: ForumsLoading? = nil) {
        self.forumsLoader = forumsLoader ?? ObjCForumsLoader()
    }

    func load() {
        isLoading = true
        errorMessage = nil
        forumsLoader.fetchForums { [weak self] forums, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.forums = []
                } else {
                    self.errorMessage = nil
                    self.forums = forums ?? []
                }
            }
        }
    }
}

@MainActor
final class ForumTopicsListViewModel: ObservableObject {
    @Published var topics: [Topic] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var selectedFlag: TopicListFlag = .all

    private let forum: Forum
    private let topicsLoader: ForumTopicsLoading
    private var loadRequestID = 0

    init(
        forum: Forum,
        topicsLoader: ForumTopicsLoading? = nil
    ) {
        self.forum = forum
        self.topicsLoader = topicsLoader ?? ObjCForumTopicsLoader()
    }

    func load() {
        loadRequestID += 1
        let requestID = loadRequestID
        isLoading = true
        errorMessage = nil
        topicsLoader.fetchTopics(for: forum, flag: selectedFlag) { [weak self] topics, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard requestID == self.loadRequestID else { return }
                self.isLoading = false
                if let error {
                    if Self.isCancellationError(error) {
                        // Ignore cancelled requests when a newer load supersedes an older one.
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.topics = []
                } else {
                    self.errorMessage = nil
                    self.topics = topics ?? []
                }
            }
        }
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        if nsError.domain == "ASIHTTPRequestErrorDomain" && nsError.code == 4 {
            return true
        }
        return nsError.localizedDescription.lowercased().contains("cancel")
    }
}

@MainActor
struct CategoriesListView: View {
    @StateObject private var viewModel: CategoriesListViewModel
    @StateObject private var accountsStore: AccountsStore
    @State private var hasLoaded = false
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false

    @MainActor
    init(
        viewModel: CategoriesListViewModel? = nil,
        accountsStore: AccountsStore? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? CategoriesListViewModel())
        _accountsStore = StateObject(wrappedValue: accountsStore ?? AccountsStore())
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Chargement...")
                        Spacer()
                    }
                }
                if let errorMessage = viewModel.errorMessage {
                    Text("Erreur : \(errorMessage)")
                        .foregroundStyle(.red)
                }
                if !viewModel.isLoading && viewModel.forums.isEmpty && viewModel.errorMessage == nil {
                    Text("Aucune categorie")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.forums) { forum in
                    NavigationLink {
                        ForumTopicsListView(
                            forum: forum,
                            accountsStore: accountsStore
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(forum.aTitle ?? "Forum")
                            if let subForums = forum.subCats as? [Forum], !subForums.isEmpty {
                                Text("\(subForums.count) sous-forums")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        accountMenuItems
                    } label: {
                        ToolbarProfileImage(image: accountsStore.currentAvatarImage, url: nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Actualiser", systemImage: "arrow.clockwise") {
                        viewModel.load()
                    }
                }
            }
            .onAppear {
                if !hasLoaded {
                    viewModel.load()
                    hasLoaded = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kLoginChangedNotification"))) { _ in
                viewModel.load()
            }
            .onReceive(NotificationCenter.default.publisher(for: .rootTabReselected)) { notification in
                guard
                    let rawTab = notification.userInfo?["tab"] as? Int,
                    rawTab == RootTabIdentifier.categories.rawValue
                else {
                    return
                }
                viewModel.load()
            }
            .sheet(isPresented: $showAddAccountSheet) {
                AddAccountView(accountsStore: accountsStore)
            }
            .alert("Déconnexion", isPresented: $showLogoutConfirm) {
                Button("Annuler", role: .cancel) {}
                Button("Déconnecter", role: .destructive) {
                    accountsStore.deleteCurrent()
                }
            } message: {
                Text("Supprimer le compte courant ?")
            }
        }
    }

    @ViewBuilder
    private var accountMenuItems: some View {
        if !accountsStore.accounts.isEmpty {
            ForEach(accountsStore.accounts) { account in
                Button {
                    accountsStore.setMain(account)
                } label: {
                    AccountMenuRow(account: account)
                }
            }
            Divider()
        }
        Button("Ajouter un pseudo") {
            showAddAccountSheet = true
        }
        Divider()
        Button("Déconnexion", role: .destructive) {
            showLogoutConfirm = true
        }
        .disabled(accountsStore.currentAccount == nil)
    }
}

@MainActor
struct ForumTopicsListView: View {
    let forum: Forum
    @StateObject private var viewModel: ForumTopicsListViewModel
    @ObservedObject private var accountsStore: AccountsStore
    @State private var hasLoaded = false
    @State private var visitedURLs: Set<String> = []
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false

    @MainActor
    init(
        forum: Forum,
        viewModel: ForumTopicsListViewModel? = nil,
        accountsStore: AccountsStore? = nil
    ) {
        self.forum = forum
        _viewModel = StateObject(wrappedValue: viewModel ?? ForumTopicsListViewModel(forum: forum))
        self._accountsStore = ObservedObject(wrappedValue: accountsStore ?? AccountsStore())
    }

    private func footerLeft(for topic: Topic) -> String {
        "⚑ \(topic.curTopicPage) / \(topic.maxTopicPage)"
    }

    private func footerRight(for topic: Topic) -> String? {
        guard
            let author = topic.aAuthorOfLastPost,
            let when = topic.aDateOfLastPost
        else {
            return nil
        }
        return "\(author) - \(when)"
    }

    var body: some View {
        List {
            Picker("Filtre", selection: $viewModel.selectedFlag) {
                Text("Tous").tag(TopicListFlag.all)
                Text("Favoris").tag(TopicListFlag.favorites)
                Text("Suivis").tag(TopicListFlag.tracked)
                Text("Lus").tag(TopicListFlag.read)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Chargement...")
                    Spacer()
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Text("Erreur : \(errorMessage)")
                    .foregroundStyle(.red)
            }
            if !viewModel.isLoading && viewModel.topics.isEmpty && viewModel.errorMessage == nil {
                Text("Aucun topic")
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.topics) { topic in
                TopicListRowView(
                    topic: topic,
                    isVisited: visitedURLs.contains(topic.aURL ?? topic.aURLOfLastPage ?? ""),
                    titleFont: .headline,
                    showUnreadBadge: true,
                    leadingBottomText: footerLeft(for: topic),
                    trailingBottomText: footerRight(for: topic)
                ) { openedURL in
                    if let openedURL, !openedURL.isEmpty {
                        visitedURLs.insert(openedURL)
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
        }
        .navigationTitle(forum.aTitle ?? "Topics")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    accountMenuItems
                } label: {
                    ToolbarProfileImage(image: accountsStore.currentAvatarImage, url: nil)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Actualiser", systemImage: "arrow.clockwise") {
                    viewModel.load()
                }
            }
        }
        .onAppear {
            if !hasLoaded {
                viewModel.load()
                hasLoaded = true
            }
        }
        .onChange(of: viewModel.selectedFlag) { _, _ in
            viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rootTabReselected)) { notification in
            guard
                let rawTab = notification.userInfo?["tab"] as? Int,
                rawTab == RootTabIdentifier.categories.rawValue
            else {
                return
            }
            viewModel.load()
        }
        .sheet(isPresented: $showAddAccountSheet) {
            AddAccountView(accountsStore: accountsStore)
        }
        .alert("Déconnexion", isPresented: $showLogoutConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Déconnecter", role: .destructive) {
                accountsStore.deleteCurrent()
            }
        } message: {
            Text("Supprimer le compte courant ?")
        }
    }

    @ViewBuilder
    private var accountMenuItems: some View {
        if !accountsStore.accounts.isEmpty {
            ForEach(accountsStore.accounts) { account in
                Button {
                    accountsStore.setMain(account)
                } label: {
                    AccountMenuRow(account: account)
                }
            }
            Divider()
        }
        Button("Ajouter un pseudo") {
            showAddAccountSheet = true
        }
        Divider()
        Button("Déconnexion", role: .destructive) {
            showLogoutConfirm = true
        }
        .disabled(accountsStore.currentAccount == nil)
    }
}

private enum CategoriesPreviewFactory {
    final class PreviewForumsLoader: ForumsLoading {
        enum Result {
            case success([Forum])
            case failure(Error)
        }

        private let result: Result
        private let delay: TimeInterval

        init(result: Result, delay: TimeInterval = 0) {
            self.result = result
            self.delay = delay
        }

        func fetchForums(completion: @escaping ForumsLoadCompletion) {
            let work = {
                switch self.result {
                case .success(let forums):
                    completion(forums, nil)
                case .failure(let error):
                    completion(nil, error)
                }
            }
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            } else {
                work()
            }
        }
    }

    final class PreviewForumTopicsLoader: ForumTopicsLoading {
        enum Result {
            case success([Topic])
            case failure(Error)
        }

        private let result: Result

        init(result: Result) {
            self.result = result
        }

        func fetchTopics(for forum: Forum, flag: TopicListFlag, completion: @escaping TopicsLoadCompletion) {
            switch result {
            case .success(let topics):
                completion(topics, nil)
            case .failure(let error):
                completion(nil, error)
            }
        }
    }

    enum PreviewError: Error, LocalizedError {
        case offline

        var errorDescription: String? { "Connexion indisponible" }
    }

    static func forum(title: String, url: String, subForumCount: Int = 0) -> Forum {
        let forum = Forum()
        forum.aTitle = title
        forum.aURL = url
        if subForumCount > 0 {
            let subForums = NSMutableArray()
            for index in 1...subForumCount {
                let sub = Forum()
                sub.aTitle = "\(title) - Sous-forum \(index)"
                sub.aURL = "\(url)?sub=\(index)"
                subForums.add(sub)
            }
            forum.subCats = subForums
        }
        return forum
    }

    static func topic(
        title: String,
        author: String,
        date: String,
        currentPage: Int = 1,
        maxPage: Int = 12
    ) -> Topic {
        let topic = Topic()
        topic._aTitle = title
        topic.aAuthorOfLastPost = author
        topic.aDateOfLastPost = date
        topic.curTopicPage = Int32(currentPage)
        topic.maxTopicPage = Int32(maxPage)
        topic.aURL = "https://forum.hardware.fr/forum2.php?cat=13&page=\(currentPage)"
        topic.aURLOfLastPage = "https://forum.hardware.fr/forum2.php?cat=13&page=\(maxPage)"
        return topic
    }

    static let sampleForums: [Forum] = [
        forum(title: "Programmation", url: "https://forum.hardware.fr/hfr/Programmation/liste_sujet-1.htm", subForumCount: 3),
        forum(title: "Hardware", url: "https://forum.hardware.fr/hfr/Hardware/liste_sujet-1.htm")
    ]

    static let sampleTopics: [Topic] = [
        topic(title: "Migration SwiftUI", author: "alice", date: "il y a 1h"),
        topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10)
    ]
}

struct RootTabView: View {
    @State private var selectedTab: RootTabIdentifier = .categories

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Catégories", systemImage: "folder.fill", value: .categories) {
                CategoriesListView()
            }
            Tab("Favoris", systemImage: "star.fill", value: .favorites) {
                //FeedView()
                FavoritesListView()
            }
            Tab("Messages", systemImage: "envelope", value: .messages) {
                MPListView()
            }
            Tab("Plus", systemImage: "ellipsis", value: .more) {
                NavigationStack {
                    PlusTableViewWrapper()
                        .navigationTitle("Plus")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink {
                                    AppSettingsView()
                                } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .background(
            TabBarReselectionObserver { selectedIndex in
                guard
                    let tab = RootTabIdentifier(rawValue: selectedIndex),
                    tab != .more
                else {
                    return
                }
                NotificationCenter.default.post(
                    name: .rootTabReselected,
                    object: nil,
                    userInfo: ["tab": tab.rawValue]
                )
            }
            .frame(width: 0, height: 0)
        )
    }
}

private struct TabBarReselectionObserver: UIViewControllerRepresentable {
    let onReselect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    func makeUIViewController(context: Context) -> ObserverViewController {
        let observer = ObserverViewController()
        observer.onHierarchyUpdate = { host in
            context.coordinator.attach(from: host)
        }
        return observer
    }

    func updateUIViewController(_ uiViewController: ObserverViewController, context: Context) {
        uiViewController.onHierarchyUpdate = { host in
            context.coordinator.attach(from: host)
        }
        context.coordinator.attach(from: uiViewController)
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private let onReselect: (Int) -> Void
        private weak var tabBarController: UITabBarController?

        init(onReselect: @escaping (Int) -> Void) {
            self.onReselect = onReselect
        }

        func attach(from host: UIViewController?) {
            if let tabBarController = host?.tabBarController ?? findTabBarController(in: host) {
                bind(to: tabBarController)
                return
            }
            if
                let root = host?.view.window?.rootViewController ?? Self.keyWindowRootViewController(),
                let tabBarController = findTabBarController(in: root)
            {
                bind(to: tabBarController)
            }
        }

        private func bind(to tabBarController: UITabBarController) {
            guard self.tabBarController !== tabBarController else { return }
            self.tabBarController = tabBarController
            tabBarController.delegate = self
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            if
                let viewControllers = tabBarController.viewControllers,
                let tappedIndex = viewControllers.firstIndex(where: { $0 === viewController }),
                tappedIndex == tabBarController.selectedIndex
            {
                onReselect(tappedIndex)
            }
            return true
        }

        private func findTabBarController(in root: UIViewController?) -> UITabBarController? {
            guard let root else { return nil }
            if let tabBarController = root as? UITabBarController {
                return tabBarController
            }
            for child in root.children {
                if let tabBarController = findTabBarController(in: child) {
                    return tabBarController
                }
            }
            return root.presentedViewController.flatMap { findTabBarController(in: $0) }
        }

        private static func keyWindowRootViewController() -> UIViewController? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        }
    }
}

private final class ObserverViewController: UIViewController {
    var onHierarchyUpdate: ((UIViewController) -> Void)?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        onHierarchyUpdate?(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onHierarchyUpdate?(self)
    }
}


#Preview {
    CategoriesListView(
        viewModel: CategoriesListViewModel(
            forumsLoader: CategoriesPreviewFactory.PreviewForumsLoader(result: .success(CategoriesPreviewFactory.sampleForums))
        )
    )
}

#Preview("Forum topics - happy path") {
    NavigationStack {
        ForumTopicsListView(
            forum: CategoriesPreviewFactory.sampleForums[0],
            viewModel: ForumTopicsListViewModel(
                forum: CategoriesPreviewFactory.sampleForums[0],
                topicsLoader: CategoriesPreviewFactory.PreviewForumTopicsLoader(result: .success(CategoriesPreviewFactory.sampleTopics))
            )
        )
    }
}

#Preview("Categories - error") {
    CategoriesListView(
        viewModel: CategoriesListViewModel(
            forumsLoader: CategoriesPreviewFactory.PreviewForumsLoader(result: .failure(CategoriesPreviewFactory.PreviewError.offline))
        )
    )
}
