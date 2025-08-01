//
//  ContentView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI

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

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationView {
                CategoriesTableViewWrapper() // Ton controller Objective-C dans SwiftUI
                    .navigationTitle("Catégories")
            }
            .tabItem {
                Label("Catégories", systemImage: "folder.fill")
            }

            NavigationView {
                ContentView2() // Un autre wrapper
            }
            .tabItem {
                Label("Favoris", systemImage: "star")
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
        }
    }
}


#Preview {
    ContentView1()
}
