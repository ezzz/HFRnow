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
    @Published var isLoading = false

    private let topicsLoader: MPTopicsLoading

    init(
        topicsLoader: MPTopicsLoading = ObjCMPTopicsLoader(),
        initialTopics: [Topic] = [],
        initialErrorMessage: String? = nil,
        initialIsLoading: Bool = false
    ) {
        self.topicsLoader = topicsLoader
        self.topics = initialTopics
        self.errorMessage = initialErrorMessage
        self.isLoading = initialIsLoading
    }

    func load() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        topicsLoader.fetchTopics { [weak self] topics, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
            }
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

@MainActor
struct MPListView: View {
    @StateObject private var viewModel: MPListViewModel
    @StateObject private var accountsStore: AccountsStore
    @State private var hasLoaded = false
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false

    @MainActor
    init(
        viewModel: MPListViewModel? = nil,
        accountsStore: AccountsStore? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? MPListViewModel())
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
                        .foregroundColor(.red)
                }
                if !viewModel.isLoading && viewModel.topics.isEmpty && viewModel.errorMessage == nil {
                    Text("Aucun message")
                        .foregroundStyle(.secondary)
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

    private var interlocutorLabel: String? {
        guard let interlocutor = topic.aAuthorOrInter else {
            return nil
        }
        if interlocutor.contains("multiples") {
            return "Interlocuteurs multiples"
        }
        return interlocutor
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
            titleFont: .headline,
            showUnreadBadge: false,
            leadingBottomText: interlocutorLabel,
            trailingBottomText: trailingLabel,
            quickActions: TopicQuickActionsConfiguration(
                showOpenFirstPage: true,
                showOpenLastPage: true,
                showCopyLink: true
            )
        )
    }
}

private enum MPPreviewFactory {
    final class PreviewMPTopicsLoader: MPTopicsLoading {
        enum Result {
            case success([Topic])
            case failure(Error)
        }

        private let result: Result
        private let delay: TimeInterval

        init(result: Result, delay: TimeInterval = 0) {
            self.result = result
            self.delay = delay
        }

        func fetchTopics(completion: @escaping TopicsLoadCompletion) {
            let work = {
                switch self.result {
                case .success(let topics):
                    completion(topics, nil)
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
        case offline

        var errorDescription: String? {
            switch self {
            case .offline:
                return "Connexion indisponible"
            }
        }
    }

    static func topic(
        title: String,
        interlocutor: String,
        author: String,
        date: String
    ) -> Topic {
        let topic = Topic()
        topic._aTitle = title
        topic.aAuthorOrInter = interlocutor
        topic.aAuthorOfLastPost = author
        topic.aDateOfLastPost = date
        topic.curTopicPage = 1
        topic.maxTopicPage = 8
        topic.aURL = "https://forum.hardware.fr/forum2.php?page=1"
        topic.aURLOfLastPage = "https://forum.hardware.fr/forum2.php?page=8"
        return topic
    }

    static let sampleTopics: [Topic] = [
        topic(title: "Conversation test", interlocutor: "Alice", author: "Alice", date: "il y a 2 min"),
        topic(title: "Support HFRswift", interlocutor: "Bob", author: "Bob", date: "hier")
    ]
}

#Preview("MP row - mock data") {
    MPRowView(
        topic: MPPreviewFactory.topic(
            title: "Conversation test",
            interlocutor: "Alice",
            author: "Alice",
            date: "il y a 2 min"
        )
    )
}

#Preview("MP list - happy path") {
    MPListView(
        viewModel: MPListViewModel(
            topicsLoader: MPPreviewFactory.PreviewMPTopicsLoader(result: .success(MPPreviewFactory.sampleTopics)),
            initialTopics: MPPreviewFactory.sampleTopics
        )
    )
}

#Preview("MP list - loading") {
    MPListView(
        viewModel: MPListViewModel(
            topicsLoader: MPPreviewFactory.PreviewMPTopicsLoader(result: .success(MPPreviewFactory.sampleTopics), delay: 3),
            initialTopics: [],
            initialIsLoading: true
        )
    )
}

#Preview("MP list - empty") {
    MPListView(
        viewModel: MPListViewModel(
            topicsLoader: MPPreviewFactory.PreviewMPTopicsLoader(result: .success([])),
            initialTopics: []
        )
    )
}

#Preview("MP list - error") {
    MPListView(
        viewModel: MPListViewModel(
            topicsLoader: MPPreviewFactory.PreviewMPTopicsLoader(result: .failure(MPPreviewFactory.PreviewError.offline)),
            initialTopics: [],
            initialErrorMessage: MPPreviewFactory.PreviewError.offline.localizedDescription
        )
    )
}
