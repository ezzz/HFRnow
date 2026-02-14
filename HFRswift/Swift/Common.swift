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

enum RootTabIdentifier: Int {
    case categories = 0
    case favorites = 1
    case messages = 2
    case more = 3
}

extension Notification.Name {
    static let rootTabReselected = Notification.Name("HFRswiftRootTabReselectedNotification")
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

enum MessageWebNavigationType {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other
    case unknown
}

enum MessageWebInitialScroll: Equatable {
    case top
    case bottom
}

enum MessageWebAction: Equatable {
    case allowNavigation
    case ignore
    case loadPage(Int, MessageWebInitialScroll)
    case refreshCurrentPage
    case openInternalTopic(URL)
    case openExternalURL(URL)
}

protocol MessageWebActionHandling {
    func action(
        for url: URL,
        navigationType: MessageWebNavigationType,
        currentPage: Int,
        maxPage: Int
    ) -> MessageWebAction
}

struct MessageWebActionHandler: MessageWebActionHandling {
    private enum Constants {
        static let autoScheme = "oijlkajsdoihjlkjasdoauto"
        static let touchScheme = "oijlkajsdoihjlkjasdotouch"
        static let preloadedScheme = "oijlkajsdoihjlkjasdopreloaded"
        static let loadedScheme = "oijlkajsdoihjlkjasdoloaded"
        static let refreshScheme = "oijlkajsdoihjlkjasdorefresh"
        static let popupAvatarScheme = "oijlkajsdoihjlkjasdopopupavatar"
        static let popupMessageScheme = "oijlkajsdoihjlkjasdopopupmessage"
        static let imageBrowserScheme = "oijlkajsdoihjlkjasdoimbrows"
        static let smileyScheme = "oijlkajsdoihjlkjasdosmiley"
    }

    func action(
        for url: URL,
        navigationType: MessageWebNavigationType,
        currentPage: Int,
        maxPage: Int
    ) -> MessageWebAction {
        let scheme = (url.scheme ?? "").lowercased()

        if navigationType == .other, url.fragment == "bas" {
            return .ignore
        }

        if scheme == Constants.autoScheme {
            guard let pageAction = autoPagingAction(for: url, currentPage: currentPage, maxPage: maxPage) else {
                return .ignore
            }
            return pageAction
        }

        if scheme == Constants.refreshScheme {
            return .refreshCurrentPage
        }

        if isIgnoredCustomScheme(scheme) {
            return .ignore
        }

        if navigationType == .linkActivated {
            if isForumTopicURL(url) || scheme == "file" {
                return .openInternalTopic(url)
            }
            if scheme == "http" || scheme == "https" {
                return .openExternalURL(url)
            }
        }

        return .allowNavigation
    }

    private func autoPagingAction(for url: URL, currentPage: Int, maxPage: Int) -> MessageWebAction? {
        let boundedMaxPage = max(maxPage, 1)
        let boundedCurrentPage = min(max(currentPage, 1), boundedMaxPage)
        let command = (url.host ?? url.lastPathComponent).lowercased()

        switch command {
        case "begin":
            guard boundedCurrentPage != 1 else { return nil }
            return .loadPage(1, .top)
        case "previous":
            guard boundedCurrentPage > 1 else { return nil }
            return .loadPage(boundedCurrentPage - 1, .bottom)
        case "next":
            guard boundedCurrentPage < boundedMaxPage else { return nil }
            return .loadPage(boundedCurrentPage + 1, .top)
        case "end":
            guard boundedCurrentPage != boundedMaxPage else { return nil }
            return .loadPage(boundedMaxPage, .bottom)
        default:
            return nil
        }
    }

    private func isIgnoredCustomScheme(_ scheme: String) -> Bool {
        scheme == Constants.touchScheme ||
            scheme == Constants.preloadedScheme ||
            scheme == Constants.loadedScheme ||
            scheme == Constants.popupAvatarScheme ||
            scheme == Constants.popupMessageScheme ||
            scheme == Constants.imageBrowserScheme ||
            scheme == Constants.smileyScheme
    }

    private func isForumTopicURL(_ url: URL) -> Bool {
        guard (url.host ?? "").lowercased() == "forum.hardware.fr" else {
            return false
        }
        let firstPathComponent = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        return firstPathComponent == "forum2.php" || firstPathComponent == "hfr"
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
    var showUnreadBadgeWhenZero = false
    var leadingBottomText: String?
    var trailingBottomText: String?
    var quickActions = TopicQuickActionsConfiguration()
    var onOpen: ((String?) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    @State private var navigateToCurrentPage = false
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

    private var unreadBadgeTextColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var unreadBadgeBackgroundColor: Color {
        if colorScheme == .dark {
            return isVisited ? .white.opacity(0.55) : .white.opacity(0.78)
        }
        return isVisited ? .secondary.opacity(0.5) : .secondary
    }

    @ViewBuilder
    private var currentPageDestination: some View {
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
    }

    var body: some View {
        Button {
            navigateToCurrentPage = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(titleText)
                            .font(titleFont)
                            .foregroundStyle(isVisited ? .secondary : .primary)
                        Spacer()
                        if showUnreadBadge && (showUnreadBadgeWhenZero || unreadCount > 0) {
                            Text("\(unreadCount)")
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .frame(minWidth: 20)
                                .background(Capsule().fill(unreadBadgeBackgroundColor))
                                .foregroundStyle(unreadBadgeTextColor)
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
        .buttonStyle(.plain)
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
                    isActive: $navigateToCurrentPage
                ) {
                    currentPageDestination
                }
                .hidden()
                .allowsHitTesting(false)

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
