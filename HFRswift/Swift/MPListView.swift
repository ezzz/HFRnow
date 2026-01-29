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
    @State private var hasLoaded = false

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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
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
                        Text("p \(topic.curTopicPage) / \(topic.maxTopicPage)")
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
