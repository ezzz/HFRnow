//
//  Favorites.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import SwiftUI
import Combine
import UIKit

struct TopicModel: Identifiable {
    let id = UUID()
    let title: String

    init(from topic: Topic) {
        self.title = topic._aTitle ?? ""
        //self.content = message.content ?? ""
    }
}

class FavoritesViewModel: ObservableObject {
    @Published var favorites: [Favorite] = []
    @Published var errorMessage: String? = nil
    @Published var isLoading = false

    private let favoritesLoader: FavoritesLoading

    init(
        favoritesLoader: FavoritesLoading = ObjCFavoritesLoader(),
        initialFavorites: [Favorite] = [],
        initialErrorMessage: String? = nil,
        initialIsLoading: Bool = false
    ) {
        self.favoritesLoader = favoritesLoader
        self.favorites = initialFavorites
        self.errorMessage = initialErrorMessage
        self.isLoading = initialIsLoading
    }

    func loadFavorites() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        favoritesLoader.fetchFavorites { [weak self] objcFavorites, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.favorites = []
                    return
                }
                self.favorites = objcFavorites ?? []
                // Light haptic feedback when favorites have loaded
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                #endif
            }
        }
    }
}

struct CategoryView: View {
    var body: some View {
        Text("Category View")
            .navigationTitle("Apple")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct FavoriteSectionView: View {
    let favorite: Favorite
    @Binding var visitedURLs: Set<String>

    // Cast centralisé
    private var topics: [Topic] { (favorite.topics as? [Topic]) ?? [] }

    @State private var isActive = false
    @State private var currentUrl: String?
    @State private var selectedTopic: Topic?

    private var headerTitle: String {
        if let name = favorite.forum?.aTitle { return name }
        if let n = favorite.order?.intValue { return "Favori \(n)" }
        return "Favori"
    }

    var body: some View {
        Section(header: NavigationLink(headerTitle) {
            CategoryView()
        }) {
            ForEach(topics) { topic in
                VStack(alignment: .leading, spacing: 8) {
                    TopicRowView(topic: topic, visitedURLs: $visitedURLs)
                }
                .contentShape(Rectangle())
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .contextMenu {
                /* TBD
                Button {
                    selectedTopic = topic
                    currentUrl = topic.aURL ?? ""
                    if let url = topic.aURL ?? topic.aURLOfLastPage {
                        visitedURLs.insert(url)
                    }
                    isActive = true
                } label: {
                    Label("Ouvrir", systemImage: "arrow.right.circle")
                }

                Button {
                    selectedTopic = topic
                    currentUrl = topic.aURLOfLastPage ?? ""
                    if let url = topic.aURLOfLastPage ?? topic.aURL {
                        visitedURLs.insert(url)
                    }
                    isActive = true
                } label: {
                    Label("Dernière page", systemImage: "arrow.uturn.right.circle")
                }

                Button {
                    if let url = topic.aURL {
                        UIPasteboard.general.string = url
                    }
                } label: {
                    Label("Copier l’URL", systemImage: "doc.on.doc")
                }*/
                
            }
        }
        // 🔑 Navigation centralisée : destination toujours un View
        //.background(navLinkHidden)
    }
}


@MainActor
struct FavoritesListView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @StateObject private var accountsStore: AccountsStore
    @State private var visitedURLs: Set<String> = []
    @State private var hasLoaded = false
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false

    @MainActor
    init(
        viewModel: FavoritesViewModel? = nil,
        accountsStore: AccountsStore? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? FavoritesViewModel())
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
                if !viewModel.isLoading && viewModel.favorites.isEmpty && viewModel.errorMessage == nil {
                    Text("Aucun favori")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.favorites) { favorite in
                    FavoriteSectionView(favorite: favorite, visitedURLs: $visitedURLs)
                }
            }
            .navigationTitle("Favoris")
            .onAppear {
                if !hasLoaded {
                    viewModel.loadFavorites()
                    hasLoaded = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kLoginChangedNotification"))) { _ in
                viewModel.loadFavorites()
            }
            .onReceive(NotificationCenter.default.publisher(for: .rootTabReselected)) { notification in
                guard
                    let rawTab = notification.userInfo?["tab"] as? Int,
                    rawTab == RootTabIdentifier.favorites.rawValue
                else {
                    return
                }
                viewModel.loadFavorites()
            }
            .toolbar {
                MainToolbarContent(
                    onRefresh: {
                        viewModel.loadFavorites()
                    },
                    onMore: {},
                    profileImage: accountsStore.currentAvatarImage,
                    profileImageURL: nil
                ) {
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
}



struct TopicRowView: View {
    var topic: Topic
    @Binding var visitedURLs: Set<String>
    
    private var isVisited: Bool {
        let url = topic.aURL ?? topic.aURLOfLastPage ?? ""
        return visitedURLs.contains(url)
    }
    
    var unreadCount: Int {
        let current = topic.curTopicPage
        let max = topic.maxTopicPage
        return Int(max - current)
    }

    private var pageLabel: String {
        "⚑ \(topic.curTopicPage) / \(topic.maxTopicPage)"
    }

    private var trailingLabel: String? {
        guard
            let author = topic.aAuthorOfLastPost,
            let when = topic.aDateOfLastPost
        else {
            return nil
        }
        return "\(author) - \(when)"
    }

    var body: some View {
        TopicListRowView(
            topic: topic,
            isVisited: isVisited,
            titleFont: .system(size: 13, weight: isVisited ? .regular : .semibold),
            showUnreadBadge: true,
            showUnreadBadgeWhenZero: false,
            leadingBottomText: pageLabel,
            trailingBottomText: trailingLabel
        ) { openedURL in
            let url = openedURL ?? topic.aURL ?? topic.aURLOfLastPage ?? ""
            if !url.isEmpty {
                visitedURLs.insert(url)
            }
        }
    }
}

struct TopicOptions: View {
    @Environment(\.tabViewBottomAccessoryPlacement)
    var placement
    
    var body: some View {
        if (placement == .inline) {
            Button("Add", systemImage: "star.fill") {
                print("Clic")
            }
            .padding()
        }
        else {
            Button("Add", systemImage: "envolope") {
                print("Clic")
            }
            .padding()
        }
    }
}

private enum FavoritesPreviewFactory {
    final class PreviewFavoritesLoader: FavoritesLoading {
        enum Result {
            case success([Favorite])
            case failure(Error)
        }

        private let result: Result
        private let delay: TimeInterval

        init(result: Result, delay: TimeInterval = 0) {
            self.result = result
            self.delay = delay
        }

        func fetchFavorites(completion: @escaping FavoritesLoadCompletion) {
            let work = {
                switch self.result {
                case .success(let favorites):
                    completion(favorites, nil)
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

    enum PreviewError: Error, LocalizedError {
        case network

        var errorDescription: String? {
            switch self {
            case .network:
                return "Réseau indisponible"
            }
        }
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

    static func favorite(title: String, topics: [Topic]) -> Favorite {
        let favorite = Favorite()
        let forum = Forum()
        forum.aTitle = title
        favorite.forum = forum
        favorite.topics = NSMutableArray(array: topics)
        return favorite
    }

    static let sampleFavorites: [Favorite] = [
        favorite(
            title: "Programmation",
            topics: [
                topic(title: "Migration SwiftUI", author: "alice", date: "il y a 1h"),
                topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10)
            ]
        )
    ]
}

#Preview("Topic row - mock data") {
    TopicRowView(
        topic: FavoritesPreviewFactory.topic(
            title: "SwiftUI migration topic",
            author: "bruno",
            date: "aujourd'hui"
        ),
        visitedURLs: .constant([])
    )
}

#Preview("Favorites list - happy path") {
    FavoritesListView(
        viewModel: FavoritesViewModel(
            favoritesLoader: FavoritesPreviewFactory.PreviewFavoritesLoader(result: .success(FavoritesPreviewFactory.sampleFavorites)),
            initialFavorites: FavoritesPreviewFactory.sampleFavorites
        )
    )
}

#Preview("Favorites list - loading") {
    FavoritesListView(
        viewModel: FavoritesViewModel(
            favoritesLoader: FavoritesPreviewFactory.PreviewFavoritesLoader(result: .success(FavoritesPreviewFactory.sampleFavorites), delay: 3),
            initialFavorites: [],
            initialIsLoading: true
        )
    )
}

#Preview("Favorites list - empty") {
    FavoritesListView(
        viewModel: FavoritesViewModel(
            favoritesLoader: FavoritesPreviewFactory.PreviewFavoritesLoader(result: .success([])),
            initialFavorites: []
        )
    )
}

#Preview("Favorites list - error") {
    FavoritesListView(
        viewModel: FavoritesViewModel(
            favoritesLoader: FavoritesPreviewFactory.PreviewFavoritesLoader(result: .failure(FavoritesPreviewFactory.PreviewError.network)),
            initialFavorites: [],
            initialErrorMessage: FavoritesPreviewFactory.PreviewError.network.localizedDescription
        )
    )
}
