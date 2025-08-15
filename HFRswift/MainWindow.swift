//
//  ContentView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI

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
    func makeUIViewController(context: Context) -> ForumsTableViewController {
        return ForumsTableViewController()
    }

    func updateUIViewController(_ uiViewController: ForumsTableViewController, context: Context) {
        // Pas besoin de mise à jour pour une vue statique
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
                    .toolbar {
                        ToolbarItem {
                            Button("Add", systemImage: "star.fill") {
                                print("Yes")
                            }
                        }
                    }
            }
            Tab("Favoris", systemImage: "star.fill") {
                FeedView()
            }
            Tab("Messages", systemImage: "envelope") {
                FeedView()
            }
            Tab("Messages", systemImage: "envelope") {
                FeedView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            //TopicOptions()
        }
        /*.tabViewBottomAccessory {
            HStack {
                Spacer()
                Button(action: {
                    print("Filter tapped")
                }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title2)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(.trailing, 16)
            }
        }*/
    }
}


#Preview {
    ContentView1()
}
