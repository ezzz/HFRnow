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
    
    private let favoritesController = FavoritesTableViewController()
    
    func loadFavorites() {
        favoritesController.fetchContent { [weak self] objcFavorites, error in
            guard let self = self, let objcFavorites = objcFavorites else { return }
            DispatchQueue.main.async {
                self.favorites = objcFavorites
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
                    TopicRowView(topic: topic)
                }
                .contentShape(Rectangle())
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


struct FavoritesListView: View {
    @StateObject private var viewModel = FavoritesViewModel()
    @State private var visitedURLs: Set<String> = []
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            List {
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
            .toolbar {
                MainToolbarContent(
                    onRefresh: {
                        viewModel.loadFavorites()
                    },
                    onMore: {},
                    profileImageURL: URL(string: "https://forum-images.hardware.fr/images/mesdiscussions-15867.png")
                ) {
                    Button("ezzz") {
                        // action ezzz
                    }
                    Divider()
                    Button("Ajouter un pseudo") {
                        // action ezzz
                    }
                    Divider()
                    Button("Déconnexion", role: .destructive) {
                        // action deconnexion
                    }
                }
            }
        }
    }
}


struct TopicRowView: View {
    var topic: Topic
    var isVisited: Bool = false
    
    var unreadCount: Int {
        let current = topic.curTopicPage
        let max = topic.maxTopicPage
        return Int(max - current)
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Invisible NavigationLink to keep row tappable without chevron
            NavigationLink("") {
                MessagesView(topic: topic, curPage: Int(topic.curTopicPage), maxPage: Int(topic.maxTopicPage), separatorNewMessages: true)
                    .toolbar(.hidden, for: .tabBar)
            }
            .opacity(0)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(topic._aTitle ?? "Sans titre")
                            .font(.headline)
                            .foregroundColor(isVisited ? .secondary : .primary)
                        Spacer()
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.caption)
                                .bold()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .frame(minWidth: 24)
                                .background(Capsule().fill(Color.secondary))
                                .foregroundColor(.white)
                        }
                    }
                    HStack {
                        Text("⚑ \(topic.curTopicPage) / \(topic.maxTopicPage)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                        Spacer()
                        if let author = topic.aAuthorOfLastPost,
                           let when = topic.aDateOfLastPost {
                            Text("\(author) - \(when)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 0)
            .contentShape(Rectangle())
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
