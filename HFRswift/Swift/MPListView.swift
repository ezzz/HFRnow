//
//  MPListView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import Combine

final class MPListViewModel: ObservableObject {
    @Published var topics: [Topic] = []
    @Published var errorMessage: String? = nil

    private let mpController: HFRMPViewController? = HFRMPViewController()

    func load() {
        guard let mpController else {
            errorMessage = "MP controller unavailable"
            topics = []
            return
        }
        mpController.loadViewIfNeeded()
        mpController.fetchContent { [weak self] topics, error in
            guard let self else { return }
            if let error {
                self.errorMessage = error.localizedDescription
                self.topics = []
            } else {
                self.errorMessage = nil
                self.topics = topics ?? []
            }
        }
    }
}

struct MPListView: View {
    @StateObject private var viewModel = MPListViewModel()
    @StateObject private var accountsStore = AccountsStore()
    @State private var hasLoaded = false
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = viewModel.errorMessage {
                    Text("Erreur : \(errorMessage)")
                        .foregroundColor(.red)
                }
                ForEach(viewModel.topics) { topic in
                    MPRowView(topic: topic)
                }
            }
            .navigationTitle("Messages")
            .onAppear {
                if !hasLoaded {
                    viewModel.load()
                    hasLoaded = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kLoginChangedNotification"))) { _ in
                viewModel.load()
            }
            .toolbar {
                MainToolbarContent(
                    onRefresh: {
                        viewModel.load()
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

struct MPRowView: View {
    var topic: Topic
    var isVisited: Bool = false

    var unreadCount: Int {
        let current = topic.curTopicPage
        let max = topic.maxTopicPage
        return Int(max - current)
    }

    var body: some View {
        ZStack(alignment: .leading) {
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
                        /*
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.caption)
                                .bold()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .frame(minWidth: 24)
                                .background(Capsule().fill(Color.secondary))
                                .foregroundColor(.white)
                        }*/
                    }
                    HStack {
                        if let interlocuteur = topic.aAuthorOrInter {
                            if interlocuteur.contains("multiples") {
                                Text("Interlocuteurs multiples")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                            }
                            else {
                                Text(interlocuteur)
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                            }
                        }

                        Spacer()


                        if let authorLastPost = topic.aAuthorOfLastPost,
                           let when = topic.aDateOfLastPost {
                            Text("\(authorLastPost) - \(when)")
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
