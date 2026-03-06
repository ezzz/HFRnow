//
//  Favorites.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import SwiftUI
import Combine
import UIKit

enum FavoritesTopicActionError: LocalizedError {
    case invalidTopicIdentifier
    case missingHash
    case invalidRequest
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidTopicIdentifier:
            return "Topic invalide."
        case .missingHash:
            return "Session invalide: hash manquant."
        case .invalidRequest:
            return "Requête invalide."
        case .serverError(let statusCode):
            return "Erreur serveur (\(statusCode))."
        }
    }
}

protocol FavoritesTopicActionServicing {
    func removeFavoriteFlag(postID: Int, categoryID: Int) async throws
}

final class ForumFavoritesTopicActionService: FavoritesTopicActionServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func removeFavoriteFlag(postID: Int, categoryID: Int) async throws {
        guard postID > 0, categoryID > 0 else {
            throw FavoritesTopicActionError.invalidTopicIdentifier
        }

        guard
            let hash = (HFRplusAppDelegate.shared() as? HFRplusAppDelegate)?
                .hash_check?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !hash.isEmpty
        else {
            throw FavoritesTopicActionError.missingHash
        }

        let baseURL = URL(string: k.forumURL()) ?? URL(string: "https://forum.hardware.fr")!
        var components = URLComponents(
            url: baseURL.appendingPathComponent("modo/manageaction.php"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "config", value: "hfr.inc"),
            URLQueryItem(name: "cat", value: "0"),
            URLQueryItem(name: "type_page", value: "forum1f"),
            URLQueryItem(name: "moderation", value: "0")
        ]
        guard let requestURL = components?.url else {
            throw FavoritesTopicActionError.invalidRequest
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded([
            "hash_check": hash,
            "topic1": "-1",
            "topic_statusno1": "-1",
            "action_reaction": "message_forum_delflags",
            "type_page": "forum1f",
            "topic0": "\(postID)",
            "valuecat0": "\(categoryID)",
            "valueforum0": "hardwarefr"
        ])
        .data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FavoritesTopicActionError.invalidRequest
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw FavoritesTopicActionError.serverError(httpResponse.statusCode)
        }
    }

    private func formURLEncoded(_ parameters: [String: String]) -> String {
        parameters
            .map { key, value in
                "\(escapeForm(key))=\(escapeForm(value))"
            }
            .joined(separator: "&")
    }

    private func escapeForm(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }
}

enum FavoritesSuperFavoriteStore {
    static let key = "SuperFavoritesIds"

    static func load() -> Set<Int> {
        let defaults = UserDefaults.standard
        let rawValues = defaults.array(forKey: key) ?? []
        let ids = rawValues.compactMap { rawValue -> Int? in
            if let number = rawValue as? NSNumber {
                return number.intValue
            }
            if let value = rawValue as? Int {
                return value
            }
            if let string = rawValue as? String {
                return Int(string)
            }
            return nil
        }
        return Set(ids.filter { $0 > 0 })
    }

    static func save(_ ids: Set<Int>) {
        let sortedIDs = ids.sorted()
        UserDefaults.standard.set(sortedIDs, forKey: key)
    }
}

enum FavoritesCollapsedSectionsStore {
    static let key = "CollapsedFavoriteSectionIDs"

    static func load() -> Set<String> {
        let defaults = UserDefaults.standard
        let rawValues = defaults.array(forKey: key) as? [String] ?? []
        return Set(
            rawValues
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func save(_ ids: Set<String>) {
        UserDefaults.standard.set(ids.sorted(), forKey: key)
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

class FavoritesViewModel: ObservableObject {
    @Published var favorites: [Favorite] = []
    @Published var errorMessage: String? = nil
    @Published var isLoading = false

    private let favoritesLoader: FavoritesLoading

    init(
        favoritesLoader: FavoritesLoading = ObjCFavoritesLoader(),
        initialFavorites: [Favorite] = [],
        initialErrorMessage: String? = nil,
        initialIsLoading: Bool = false
    ) {
        self.favoritesLoader = favoritesLoader
        self.favorites = initialFavorites
        self.errorMessage = initialErrorMessage
        self.isLoading = initialIsLoading
    }

    func loadFavorites() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        favoritesLoader.fetchFavorites { [weak self] objcFavorites, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.favorites = []
                    return
                }
                self.favorites = objcFavorites ?? []
                // Light haptic feedback when favorites have loaded
                #if canImport(UIKit)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                #endif
            }
        }
    }

    func clearForLoggedOut() {
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorMessage = nil
            self.favorites = []
        }
    }

    func removeTopic(withPostID postID: Int) {
        guard postID > 0 else { return }

        let updatedFavorites: [Favorite] = favorites.compactMap { favorite in
            let topics = ((favorite.topics as? [Topic]) ?? []).filter { $0.postID != postID }
            guard !topics.isEmpty else { return nil }
            favorite.topics = NSMutableArray(array: topics)
            return favorite
        }

        favorites = updatedFavorites
    }
}

struct FavoriteSectionView: View {
    let favorite: Favorite
    let sectionID: String
    let isCollapsed: Bool
    @Binding var visitedURLs: Set<String>
    @Binding var superFavoriteIDs: Set<Int>
    let removingTopicIDs: Set<Int>
    @ObservedObject var accountsStore: AccountsStore
    let onToggleCollapse: () -> Void
    let onMarkRead: (Topic) -> Void
    let onToggleSuperFavorite: (Topic) -> Void
    let onRemoveFavorite: (Topic) -> Void

    // Cast centralisé
    private var topics: [Topic] { (favorite.topics as? [Topic]) ?? [] }

    private var headerTitle: String {
        if let name = favorite.forum?.aTitle { return name }
        if let n = favorite.order?.intValue { return "Favori \(n)" }
        return "Favori"
    }

    @ViewBuilder
    private var headerTitleView: some View {
        if let forum = favorite.forum {
            NavigationLink {
                ForumTopicsListView(
                    forum: forum,
                    initialFlagOverride: .favorites,
                    accountsStore: accountsStore
                )
            } label: {
                Text(headerTitle)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ouvrir le forum")
        } else {
            Text(headerTitle)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var sectionHeader: some View {
        HStack(spacing: 10) {
            headerTitleView
            Spacer(minLength: 8)
            Text("\(topics.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 34)
        .overlay(alignment: .trailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    onToggleCollapse()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .frame(width: 38, height: 28, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorite-section-toggle-\(sectionID)")
            .accessibilityLabel(isCollapsed ? "Déplier \(headerTitle)" : "Plier \(headerTitle)")
        }
    }

    var body: some View {
        Section(header: sectionHeader) {
            if !isCollapsed {
                ForEach(topics) { topic in
                    let postID = Int(topic.postID)
                    TopicRowView(
                        topic: topic,
                        visitedURLs: $visitedURLs,
                        isSuperFavorite: superFavoriteIDs.contains(postID),
                        isRemovingFavorite: removingTopicIDs.contains(postID),
                        onMarkRead: { onMarkRead(topic) },
                        onToggleSuperFavorite: { onToggleSuperFavorite(topic) },
                        onRemoveFavorite: { onRemoveFavorite(topic) }
                    )
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
        }
    }
}


@MainActor
struct FavoritesListView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @StateObject private var accountsStore: AccountsStore
    @State private var visitedURLs: Set<String> = []
    @State private var hasLoaded = false
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false
    @State private var showSectionActions = false
    @State private var superFavoriteIDs: Set<Int>
    @State private var collapsedSectionIDs: Set<String>
    @State private var removingTopicIDs: Set<Int> = []
    @State private var topicActionErrorMessage: String?

    private let topicActionService: FavoritesTopicActionServicing

    private var isLoggedIn: Bool {
        accountsStore.currentAccount != nil
    }

    private func refreshContentForSessionState() {
        if isLoggedIn {
            viewModel.loadFavorites()
        } else {
            viewModel.clearForLoggedOut()
        }
    }

    @MainActor
    init(
        viewModel: FavoritesViewModel? = nil,
        accountsStore: AccountsStore? = nil,
        topicActionService: FavoritesTopicActionServicing = ForumFavoritesTopicActionService()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? FavoritesViewModel())
        _accountsStore = StateObject(wrappedValue: accountsStore ?? AccountsStore())
        _superFavoriteIDs = State(initialValue: FavoritesSuperFavoriteStore.load())
        _collapsedSectionIDs = State(initialValue: FavoritesCollapsedSectionsStore.load())
        self.topicActionService = topicActionService
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func sectionIdentifier(for favorite: Favorite) -> String {
        if let forumID = normalizedNonEmpty(favorite.forum?.aID) {
            return "forum-id:\(forumID)"
        }
        if let forumURL = normalizedNonEmpty(favorite.forum?.aURL) {
            return "forum-url:\(forumURL)"
        }
        if let forumTitle = normalizedNonEmpty(favorite.forum?.aTitle) {
            return "forum-title:\(forumTitle.lowercased())"
        }
        if let order = favorite.order?.intValue {
            return "favorite-order:\(order)"
        }
        if let firstPostID = ((favorite.topics as? [Topic])?.first.map({ Int($0.postID) })), firstPostID > 0 {
            return "favorite-first-post:\(firstPostID)"
        }
        return "favorite-unknown"
    }

    private func toggleSectionCollapse(sectionID: String) {
        if collapsedSectionIDs.contains(sectionID) {
            collapsedSectionIDs.remove(sectionID)
        } else {
            collapsedSectionIDs.insert(sectionID)
        }
        FavoritesCollapsedSectionsStore.save(collapsedSectionIDs)
    }

    private func pruneCollapsedSections() {
        let validIDs = Set(viewModel.favorites.map(sectionIdentifier(for:)))
        let filtered = collapsedSectionIDs.intersection(validIDs)
        if filtered != collapsedSectionIDs {
            collapsedSectionIDs = filtered
            FavoritesCollapsedSectionsStore.save(filtered)
        }
    }

    private func collapseAllSections() {
        let allSectionIDs = Set(viewModel.favorites.map(sectionIdentifier(for:)))
        collapsedSectionIDs = allSectionIDs
        FavoritesCollapsedSectionsStore.save(allSectionIDs)
    }

    private func expandAllSections() {
        collapsedSectionIDs = []
        FavoritesCollapsedSectionsStore.save(Set<String>())
    }

    var body: some View {
        NavigationStack {
            List {
                if !isLoggedIn {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Connectez-vous pour accéder aux favoris", systemImage: "star.slash")
                            .font(.headline)
                        Text("Ajoutez un pseudo pour charger vos favoris et vos drapeaux.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Ajouter un pseudo") {
                            showAddAccountSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8)
                } else {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Chargement...")
                            Spacer()
                        }
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Text("Erreur : \(errorMessage)")
                            .foregroundStyle(.red)
                    }
                    if !viewModel.isLoading && viewModel.favorites.isEmpty && viewModel.errorMessage == nil {
                        Text("Aucun favori")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.favorites) { favorite in
                        let sectionID = sectionIdentifier(for: favorite)
                        FavoriteSectionView(
                            favorite: favorite,
                            sectionID: sectionID,
                            isCollapsed: collapsedSectionIDs.contains(sectionID),
                            visitedURLs: $visitedURLs,
                            superFavoriteIDs: $superFavoriteIDs,
                            removingTopicIDs: removingTopicIDs,
                            accountsStore: accountsStore,
                            onToggleCollapse: {
                                toggleSectionCollapse(sectionID: sectionID)
                            },
                            onMarkRead: markTopicAsRead(_:),
                            onToggleSuperFavorite: toggleSuperFavorite(_:),
                            onRemoveFavorite: removeFavoriteFlag(_:)
                        )
                    }
                }
            }
            .navigationTitle("Favoris")
            .onAppear {
                superFavoriteIDs = FavoritesSuperFavoriteStore.load()
                collapsedSectionIDs = FavoritesCollapsedSectionsStore.load()
                if !hasLoaded {
                    refreshContentForSessionState()
                    hasLoaded = true
                }
                pruneCollapsedSections()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kLoginChangedNotification"))) { _ in
                refreshContentForSessionState()
            }
            .onReceive(viewModel.$favorites) { _ in
                pruneCollapsedSections()
            }
            .onReceive(NotificationCenter.default.publisher(for: .rootTabReselected)) { notification in
                guard
                    let rawTab = notification.userInfo?["tab"] as? Int,
                    rawTab == RootTabIdentifier.favorites.rawValue
                else {
                    return
                }
                refreshContentForSessionState()
            }
            .toolbar {
                MainToolbarContent(
                    onRefresh: {
                        viewModel.loadFavorites()
                    },
                    onMore: {
                        showSectionActions = true
                    },
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
            .confirmationDialog(
                "Sections Favoris",
                isPresented: $showSectionActions,
                titleVisibility: .visible
            ) {
                Button("Tout plier") {
                    collapseAllSections()
                }
                .disabled(viewModel.favorites.isEmpty || collapsedSectionIDs.count == viewModel.favorites.count)

                Button("Tout déplier") {
                    expandAllSections()
                }
                .disabled(viewModel.favorites.isEmpty || collapsedSectionIDs.isEmpty)

                Button("Annuler", role: .cancel) {}
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
            .alert(
                "Action impossible",
                isPresented: Binding(
                    get: { topicActionErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            topicActionErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(topicActionErrorMessage ?? "Erreur inconnue.")
            }
        }
    }

    private func markTopicAsRead(_ topic: Topic) {
        let url = topic.aURL ?? topic.aURLOfLastPage ?? ""
        if !url.isEmpty {
            visitedURLs.insert(url)
        }
        topic.isViewed = true
    }

    private func toggleSuperFavorite(_ topic: Topic) {
        let postID = Int(topic.postID)
        guard postID > 0 else { return }

        if superFavoriteIDs.contains(postID) {
            superFavoriteIDs.remove(postID)
            topic.isSuperFavorite = false
        } else {
            superFavoriteIDs.insert(postID)
            topic.isSuperFavorite = true
        }
        FavoritesSuperFavoriteStore.save(superFavoriteIDs)
    }

    private func removeFavoriteFlag(_ topic: Topic) {
        let postID = Int(topic.postID)
        let categoryID = Int(topic.catID)
        guard postID > 0, categoryID > 0 else {
            topicActionErrorMessage = FavoritesTopicActionError.invalidTopicIdentifier.localizedDescription
            return
        }
        guard !removingTopicIDs.contains(postID) else { return }

        removingTopicIDs.insert(postID)
        Task {
            do {
                try await topicActionService.removeFavoriteFlag(postID: postID, categoryID: categoryID)
                withAnimation(.easeOut(duration: 0.18)) {
                    viewModel.removeTopic(withPostID: postID)
                }
            } catch {
                topicActionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            removingTopicIDs.remove(postID)
        }
    }
}



struct TopicRowView: View {
    var topic: Topic
    @Binding var visitedURLs: Set<String>
    var isSuperFavorite = false
    var isRemovingFavorite = false
    var onMarkRead: (() -> Void)?
    var onToggleSuperFavorite: (() -> Void)?
    var onRemoveFavorite: (() -> Void)?
    @Environment(\.appThemePalette) private var themePalette
    
    private var isVisited: Bool {
        let url = topic.aURL ?? topic.aURLOfLastPage ?? ""
        return visitedURLs.contains(url)
    }
    
    var unreadCount: Int {
        let current = topic.curTopicPage
        let max = topic.maxTopicPage
        return Int(max - current)
    }

    private var pageLabel: String {
        let currentPage = Int(topic.curTopicPage)
        let maxPage = max(Int(topic.maxTopicPage), 1)
        let pollSuffix = topic.isPoll ? " \u{2263}" : ""

        if currentPage > 0 && currentPage <= maxPage {
            return "⚑\(pollSuffix) \(currentPage) / \(maxPage)"
        }
        return "\(maxPage)\(pollSuffix)"
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
            titleFont: .system(size: 13, weight: isVisited ? .regular : .semibold),
            showUnreadBadge: true,
            showUnreadBadgeWhenZero: false,
            leadingBottomText: pageLabel,
            trailingBottomText: trailingLabel,
            rowBackgroundTint: isSuperFavorite ? themePalette.superFavoriteBackgroundColor : nil,
            contentPadding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0),
            rowBackgroundOverflow: isSuperFavorite
                ? EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6)
                : EdgeInsets(),
            openContext: .favorites,
            extraContextMenu: {
                AnyView(
                    Group {
                        if let onMarkRead {
                            Button("Lu", systemImage: "checkmark") {
                                onMarkRead()
                            }
                        }
                        if let onToggleSuperFavorite {
                            Button(
                                isSuperFavorite ? "Retirer super favori" : "Super favori",
                                systemImage: isSuperFavorite ? "star.slash" : "star"
                            ) {
                                onToggleSuperFavorite()
                            }
                        }
                        if let onRemoveFavorite {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                onRemoveFavorite()
                            }
                            .disabled(isRemovingFavorite)
                        }
                    }
                )
            }
        ) { openedURL in
            let url = openedURL ?? topic.aURL ?? topic.aURLOfLastPage ?? ""
            if !url.isEmpty {
                visitedURLs.insert(url)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let onMarkRead {
                Button {
                    onMarkRead()
                } label: {
                    Label("Lu", systemImage: "checkmark")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onRemoveFavorite {
                Button(role: .destructive) {
                    onRemoveFavorite()
                } label: {
                    if isRemovingFavorite {
                        Label("Suppression...", systemImage: "hourglass")
                    } else {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
                .disabled(isRemovingFavorite)
            }
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

private enum FavoritesPreviewFactory {
    final class PreviewFavoritesLoader: FavoritesLoading {
        enum Result {
            case success([Favorite])
            case failure(Error)
        }

        private let result: Result
        private let delay: TimeInterval

        init(result: Result, delay: TimeInterval = 0) {
            self.result = result
            self.delay = delay
        }

        func fetchFavorites(completion: @escaping FavoritesLoadCompletion) {
            let work = {
                switch self.result {
                case .success(let favorites):
                    completion(favorites, nil)
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
        case network

        var errorDescription: String? {
            switch self {
            case .network:
                return "Réseau indisponible"
            }
        }
    }

    static func topic(
        title: String,
        author: String,
        date: String,
        currentPage: Int = 1,
        maxPage: Int = 12
    ) -> Topic {
        let topic = Topic()
        topic._aTitle = title
        topic.aAuthorOfLastPost = author
        topic.aDateOfLastPost = date
        topic.curTopicPage = Int32(currentPage)
        topic.maxTopicPage = Int32(maxPage)
        topic.aURL = "https://forum.hardware.fr/forum2.php?cat=13&page=\(currentPage)"
        topic.aURLOfLastPage = "https://forum.hardware.fr/forum2.php?cat=13&page=\(maxPage)"
        return topic
    }

    static func favorite(title: String, topics: [Topic]) -> Favorite {
        let favorite = Favorite()
        let forum = Forum()
        forum.aTitle = title
        favorite.forum = forum
        favorite.topics = NSMutableArray(array: topics)
        return favorite
    }

    static let sampleFavorites: [Favorite] = [
        favorite(
            title: "Programmation",
            topics: [
                topic(title: "Migration SwiftUI", author: "alice", date: "il y a 1h"),
                topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10)
            ]
        )
    ]
}

#Preview("Topic row - mock data") {
    TopicRowView(
        topic: FavoritesPreviewFactory.topic(
            title: "SwiftUI migration topic",
            author: "bruno",
            date: "aujourd'hui"
        ),
        visitedURLs: .constant([])
    )
}

#Preview("Favorites list - happy path") {
    FavoritesListView(
        viewModel: FavoritesViewModel(
            favoritesLoader: FavoritesPreviewFactory.PreviewFavoritesLoader(result: .success(FavoritesPreviewFactory.sampleFavorites)),
            initialFavorites: FavoritesPreviewFactory.sampleFavorites
        )
    )
}

#Preview("Favorites list - loading") {
    FavoritesListView(
        viewModel: FavoritesViewModel(
            favoritesLoader: FavoritesPreviewFactory.PreviewFavoritesLoader(result: .success(FavoritesPreviewFactory.sampleFavorites), delay: 3),
            initialFavorites: [],
            initialIsLoading: true
        )
    )
}

#Preview("Favorites list - empty") {
    FavoritesListView(
        viewModel: FavoritesViewModel(
            favoritesLoader: FavoritesPreviewFactory.PreviewFavoritesLoader(result: .success([])),
            initialFavorites: []
        )
    )
}

#Preview("Favorites list - error") {
    FavoritesListView(
        viewModel: FavoritesViewModel(
            favoritesLoader: FavoritesPreviewFactory.PreviewFavoritesLoader(result: .failure(FavoritesPreviewFactory.PreviewError.network)),
            initialFavorites: [],
            initialErrorMessage: FavoritesPreviewFactory.PreviewError.network.localizedDescription
        )
    )
}
