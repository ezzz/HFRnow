//
//  Common.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import Foundation
import SwiftUI
import UIKit

extension Favorite: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension Topic: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension Forum: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

typealias FavoritesLoadCompletion = ([Favorite]?, Error?) -> Void
typealias TopicsLoadCompletion = ([Topic]?, Error?) -> Void
typealias ForumsLoadCompletion = ([Forum]?, Error?) -> Void

protocol FavoritesLoading {
    func fetchFavorites(completion: @escaping FavoritesLoadCompletion)
}

final class ObjCFavoritesLoader: FavoritesLoading {
    private let controller: FavoritesTableViewController

    init(controller: FavoritesTableViewController = FavoritesTableViewController()) {
        self.controller = controller
    }

    func fetchFavorites(completion: @escaping FavoritesLoadCompletion) {
        controller.fetchContent { favorites, error in
            completion(favorites, error)
        }
    }
}

protocol MPTopicsLoading {
    func fetchTopics(completion: @escaping TopicsLoadCompletion)
}

final class ObjCMPTopicsLoader: MPTopicsLoading {
    private let controller: HFRMPViewController

    init(controller: HFRMPViewController = HFRMPViewController()) {
        self.controller = controller
    }

    func fetchTopics(completion: @escaping TopicsLoadCompletion) {
        controller.loadViewIfNeeded()
        controller.fetchContent { topics, error in
            completion(topics, error)
        }
    }
}

protocol ForumsLoading {
    func fetchForums(completion: @escaping ForumsLoadCompletion)
}

final class ObjCForumsLoader: ForumsLoading {
    private let controller: ForumsTableViewController

    init(controller: ForumsTableViewController = ForumsTableViewController()) {
        self.controller = controller
    }

    func fetchForums(completion: @escaping ForumsLoadCompletion) {
        controller.fetchContent { forums, error in
            completion(forums, error)
        }
    }
}

enum TopicListFlag: Int {
    case all = 0
    case favorites = 1
    case tracked = 2
    case read = 3
}

protocol ForumTopicsLoading {
    func fetchTopics(for forum: Forum, flag: TopicListFlag, completion: @escaping TopicsLoadCompletion)
}

final class ObjCForumTopicsLoader: ForumTopicsLoading {
    private let controller: TopicsTableViewController

    init(controller: TopicsTableViewController = TopicsTableViewController()) {
        self.controller = controller
    }

    func fetchTopics(for forum: Forum, flag: TopicListFlag, completion: @escaping TopicsLoadCompletion) {
        controller.fetchContent(for: forum, flagIndex: flag.rawValue) { topics, error in
            completion(topics, error)
        }
    }
}

struct TopicPageContent {
    let html: String
    let topicAnswerURL: URL?
}

enum TopicPageLoadingError: LocalizedError {
    case missingHTML

    var errorDescription: String? {
        switch self {
        case .missingHTML:
            return "No HTML returned for topic page"
        }
    }
}

protocol TopicPageLoading {
    func fetchTopicPage(url: String, anchor: String?, completion: @escaping (Result<TopicPageContent, Error>) -> Void)
}

final class ObjCTopicPageLoader: TopicPageLoading {
    private let controller: MessagesTableViewController

    init(controller: MessagesTableViewController = MessagesTableViewController()) {
        self.controller = controller
    }

    func fetchTopicPage(url: String, anchor: String?, completion: @escaping (Result<TopicPageContent, Error>) -> Void) {
        controller.fetchContent(forTopicURL: url, anchor: anchor) { html, topicAnswerURL, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let html else {
                completion(.failure(TopicPageLoadingError.missingHTML))
                return
            }
            let answerURL = topicAnswerURL.flatMap(URL.init(string:))
            completion(.success(TopicPageContent(html: html, topicAnswerURL: answerURL)))
        }
    }
}

struct TopicPageRenderOutput {
    let fileURL: URL?
    let readAccessURL: URL?
}

enum TopicPageRenderingError: LocalizedError {
    case offlineStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .offlineStorageUnavailable:
            return "OfflineStorage is unavailable"
        }
    }
}

protocol TopicPageRendering {
    func render(html: String) throws -> TopicPageRenderOutput
}

struct OfflineStorageTopicPageRenderer: TopicPageRendering {
    func render(html: String) throws -> TopicPageRenderOutput {
        guard let offlineStorage = OfflineStorage.shared() else {
            throw TopicPageRenderingError.offlineStorageUnavailable
        }
        guard let cacheDirectoryURL = offlineStorage.cacheURL() else {
            throw TopicPageRenderingError.offlineStorageUnavailable
        }
        let fileURL = cacheDirectoryURL
            .appendingPathComponent("topic-\(UUID().uuidString)")
            .appendingPathExtension("htm")
        try html.write(to: fileURL, atomically: false, encoding: .utf8)
        return TopicPageRenderOutput(fileURL: fileURL, readAccessURL: cacheDirectoryURL)
    }
}

struct TopicQuickActionsConfiguration {
    var showOpenFirstPage = true
    var showOpenLastPage = true
    var showCopyLink = true
}

struct TopicQuickActionsMenu: View {
    let configuration: TopicQuickActionsConfiguration
    var onOpenFirstPage: (() -> Void)?
    var onOpenLastPage: (() -> Void)?
    var onCopyLink: (() -> Void)?

    var body: some View {
        if configuration.showOpenFirstPage, let onOpenFirstPage {
            Button("Premiere page", systemImage: "arrow.up.to.line") {
                onOpenFirstPage()
            }
        }
        if configuration.showOpenLastPage, let onOpenLastPage {
            Button("Derniere page", systemImage: "arrow.down.to.line") {
                onOpenLastPage()
            }
        }
        if configuration.showCopyLink, let onCopyLink {
            Button("Copier l'URL", systemImage: "doc.on.doc") {
                onCopyLink()
            }
        }
    }
}

struct TopicListRowView: View {
    let topic: Topic
    let isVisited: Bool
    var titleFont: Font = .headline
    var showUnreadBadge = false
    var leadingBottomText: String?
    var trailingBottomText: String?
    var quickActions = TopicQuickActionsConfiguration()
    var onOpen: ((String?) -> Void)?

    @State private var navigateToFirstPage = false
    @State private var navigateToLastPage = false

    private var unreadCount: Int {
        max(Int(topic.maxTopicPage - topic.curTopicPage), 0)
    }

    private var titleText: String {
        topic._aTitle ?? "Sans titre"
    }

    private var currentURL: String? {
        topic.aURL ?? topic.aURLOfLastPost ?? topic.aURLOfLastPage
    }

    private var firstPageURL: String? {
        topic.aURL
    }

    private var lastPageURL: String? {
        topic.aURLOfLastPage ?? topic.aURL
    }

    private var copyURL: String? {
        topic.aURL ?? topic.aURLOfLastPage ?? topic.aURLOfLastPost
    }

    var body: some View {
        NavigationLink {
            MessagesView(
                topic: topic,
                curPage: Int(topic.curTopicPage),
                maxPage: Int(topic.maxTopicPage),
                separatorNewMessages: true
            )
            .onAppear {
                onOpen?(currentURL)
            }
            .toolbar(.hidden, for: .tabBar)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(titleText)
                            .font(titleFont)
                            .foregroundStyle(isVisited ? .secondary : .primary)
                        Spacer()
                        if showUnreadBadge && unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .frame(minWidth: 20)
                                .background(Capsule().fill(.secondary).opacity(isVisited ? 0.5 : 1.0))
                                .foregroundStyle(.white)
                        }
                    }

                    if leadingBottomText != nil || trailingBottomText != nil {
                        HStack {
                            if let leadingBottomText {
                                Text(leadingBottomText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let trailingBottomText {
                                Text(trailingBottomText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 0)
            .contentShape(Rectangle())
        }
        .contextMenu {
            TopicQuickActionsMenu(
                configuration: quickActions,
                onOpenFirstPage: firstPageURL == nil ? nil : {
                    navigateToLastPage = false
                    navigateToFirstPage = true
                },
                onOpenLastPage: lastPageURL == nil ? nil : {
                    navigateToFirstPage = false
                    navigateToLastPage = true
                },
                onCopyLink: copyURL == nil ? nil : {
                    UIPasteboard.general.string = copyURL
                }
            )
        }
        .background {
            ZStack {
                NavigationLink(
                    "",
                    isActive: $navigateToFirstPage
                ) {
                    MessagesView(
                        topic: topic,
                        curPage: 1,
                        maxPage: max(Int(topic.maxTopicPage), 1),
                        separatorNewMessages: true
                    )
                    .onAppear {
                        onOpen?(firstPageURL)
                    }
                    .toolbar(.hidden, for: .tabBar)
                }
                .hidden()
                .allowsHitTesting(false)

                NavigationLink(
                    "",
                    isActive: $navigateToLastPage
                ) {
                    MessagesView(
                        topic: topic,
                        curPage: max(Int(topic.maxTopicPage), 1),
                        maxPage: max(Int(topic.maxTopicPage), 1),
                        separatorNewMessages: true
                    )
                    .onAppear {
                        onOpen?(lastPageURL)
                    }
                    .toolbar(.hidden, for: .tabBar)
                }
                .hidden()
                .allowsHitTesting(false)
            }
        }
    }
}
