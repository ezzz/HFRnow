//
//  ContentView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import Combine

enum Tabs: Int {
    case add = 0
}

struct ContentView1: View {
    var body: some View {
        VStack {
            Image(systemName: "envelope")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Catégories")
        }
        .padding()
    }
}
struct ContentView2: View {
    var body: some View {
        VStack {
            Image(systemName: "envelope")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Favoris")
        }
        .padding()
    }
}
struct ContentView3: View {
    var body: some View {
        VStack {
            Image(systemName: "envelope")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Messages")
        }
        .padding()
    }
}
struct ContentView4: View {
    var body: some View {
        VStack {
            Image(systemName: "envelope")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Plus")
        }
        .padding()
    }
}


struct PlusTableViewWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PlusTableViewController {
        return PlusTableViewController()
    }

    func updateUIViewController(_ uiViewController: PlusTableViewController, context: Context) {
        // Pas besoin de mise à jour pour une vue statique
    }
}


struct CategoriesTableViewWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let forumsVC = ForumsTableViewController()
        let navController = UINavigationController(rootViewController: forumsVC)
        return navController

    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Rien à faire ici dans ton cas
    }
}

struct TopicModel: Identifiable {
    let id = UUID()
    let title: String

    init(from topic: Topic) {
        self.title = topic._aTitle ?? ""
        //self.content = message.content ?? ""
    }
}

final class TopicListViewModel: ObservableObject {
    @Published var topics: [TopicModel] = []

    // Crée une instance pour appeler la méthode d’instance
    private let favorites = FavoritesTableViewController()

    func loadTopics() {
        favorites.fetchContent { [weak self] objcTopics, error in
            guard let self = self else { return }
            if let error = error {
                print("Erreur fetch:", error)
                return
            }
            let swiftTopics = (objcTopics ?? []).map { TopicModel(from: $0) }
            DispatchQueue.main.async {
                self.topics = swiftTopics
            }
        }
    }
}


struct TopicRowView: View {
    let topic: TopicModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.title)
                .font(.headline)
            Text(topic.title)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

struct TopicListView: View {
    @StateObject private var viewModel = TopicListViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.topics) { topic in
                TopicRowView(topic: topic)
            }
            .navigationTitle("Favoris")
            .onAppear {
                viewModel.loadTopics()
            }
        }
    }
}

struct FeedView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(0..<50, id: \.self) { i in
                        Text("Post #\(i)")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Feed")
/*
            .toolbar(.visible, for: .tabBar) // iOS 16+, permet le minimize on scroll
            .toolbar {
                            ToolbarItemGroup(placement: .bottomBar) {
                                Spacer()
                                
                                Button(action: {
                                    print("Filtrer")
                                }) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                }

                                Button(action: {
                                    print("Ajouter un post")
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                }
                            }
                        }*/
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

struct RootTabView: View {
    var body: some View {
        TabView {
            /*NavigationView {
                CategoriesTableViewWrapper() // Ton controller Objective-C dans SwiftUI
                    .navigationTitle("Catégories")
            }
            .tabItem {
                Label("Catégories", systemImage: "folder.fill")
            }
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "list.bullet")
                }

            NavigationView {
                ContentView3() // Vue 100% SwiftUI si prête
            }
            .tabItem {
                Label("Messages", systemImage: "envelope")
            }

            NavigationView {
                PlusTableViewWrapper()
                    .navigationTitle("Plus d'infos")
            }
            .tabItem {
                Label("Plus", systemImage: "info.circle")
            }
            */
            Tab("Catégories", systemImage: "folder.fill") {
                CategoriesTableViewWrapper()
                    .navigationTitle("Catégories")
                    .toolbar {
                        ToolbarItem {
                            Button("Add", systemImage: "star.fill") {
                                print("Yes")
                            }
                        }
                    }
            }
            Tab("Favoris", systemImage: "star.fill") {
                //FeedView()
                TopicListView()
            }
            Tab("Messages", systemImage: "envelope") {
                NavigationView {
                    CategoriesTableViewWrapper() // Ton controller Objective-C dans SwiftUI
                        .navigationTitle("Catégories")
                }
            }
            Tab("Messages", systemImage: "envelope") {
                NavigationView {
                    PlusTableViewWrapper()
                        .navigationTitle("Plus")
                }
            }
        }
    }
}


#Preview {
    ContentView1()
}
