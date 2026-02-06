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

struct RootTabView: View {
    var body: some View {
        TabView {
            /*Tab("Catégories", systemImage: "folder.fill") {
                CategoriesTableViewWrapper()
                    .navigationTitle("Catégories")
                    .toolbar {
                        ToolbarItem {
                            Button("Add", systemImage: "star.fill") {
                                print("Yes")
                            }
                        }
                    }
            }*/
            Tab("Favoris", systemImage: "star.fill") {
                //FeedView()
                FavoritesListView()
            }
            Tab("Messages", systemImage: "envelope") {
                MPListView()
            }
            Tab("Plus", systemImage: "ellipsis") {
                NavigationView {
                    PlusTableViewWrapper()
                        .navigationTitle("Plus")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}


#Preview {
    
}
