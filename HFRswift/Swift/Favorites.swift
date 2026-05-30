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

enum FavoritesTopicListOrdering {
    static func flattenedTopics(from favorites: [Favorite]) -> [Topic] {
        let flattenedTopics = favorites.flatMap { favorite in
            (favorite.topics as? [Topic]) ?? []
        }
        let sortDescriptor = NSSortDescriptor(key: "dDateOfLastPost", ascending: false)
        let sortedTopics = (flattenedTopics as NSArray).sortedArray(using: [sortDescriptor])
        return sortedTopics.compactMap { $0 as? Topic }
    }
}

struct FavoritesListDensity {
    let sectionSpacing: CGFloat
    let sectionHeaderTopPadding: CGFloat
    let sectionHeaderBottomPadding: CGFloat
    let collapsedHeaderTopPadding: CGFloat
    let collapsedHeaderBottomPadding: CGFloat
    let rowInsets: EdgeInsets

    static func value(isCompactModeEnabled: Bool) -> FavoritesListDensity {
        if isCompactModeEnabled {
            return FavoritesListDensity(
                sectionSpacing: 6,
                sectionHeaderTopPadding: -4,
                sectionHeaderBottomPadding: -5,
                collapsedHeaderTopPadding: -1,
                collapsedHeaderBottomPadding: -2,
                rowInsets: EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
            )
        }

        return FavoritesListDensity(
            sectionSpacing: 12,
            sectionHeaderTopPadding: -2,
            sectionHeaderBottomPadding: -2,
            collapsedHeaderTopPadding: 1,
            collapsedHeaderBottomPadding: 1,
            rowInsets: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        )
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
    @Published private(set) var hasLoadedOnce: Bool

    private let favoritesLoader: FavoritesLoading
    private var pendingForcedReload = false

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
        self.hasLoadedOnce = initialIsLoading || !initialFavorites.isEmpty || initialErrorMessage != nil
    }

    func loadFavorites(force: Bool = false, shouldTriggerHaptic: Bool = false) {
        guard !isLoading else {
            if force {
                pendingForcedReload = true
            }
            return
        }
        isLoading = true
        errorMessage = nil
        favoritesLoader.fetchFavorites { [weak self] objcFavorites, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                self.hasLoadedOnce = true
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.favorites = []
                    if self.pendingForcedReload {
                        self.pendingForcedReload = false
                        self.loadFavorites(force: true, shouldTriggerHaptic: shouldTriggerHaptic)
                    }
                    return
                }
                self.favorites = objcFavorites ?? []
                if shouldTriggerHaptic {
                    AppHaptics.refreshCompleted()
                }
                if self.pendingForcedReload {
                    self.pendingForcedReload = false
                    self.loadFavorites(force: true, shouldTriggerHaptic: shouldTriggerHaptic)
                }
            }
        }
    }

    func ensureLoaded() {
        guard !isLoading else { return }
        guard !hasLoadedOnce || errorMessage != nil else { return }
        loadFavorites()
    }

    func clearForLoggedOut() {
        isLoading = false
        pendingForcedReload = false
        errorMessage = nil
        favorites = []
        hasLoadedOnce = false
    }

    func removeTopic(withPostID postID: Int) {
        guard postID > 0 else { return }

        let updatedFavorites: [Favorite] = favorites.map { favorite in
            let topics = ((favorite.topics as? [Topic]) ?? []).filter { $0.postID != postID }
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
    let density: FavoritesListDensity
    @Binding var visitedURLs: Set<String>
    @Binding var superFavoriteIDs: Set<Int>
    let removingTopicIDs: Set<Int>
    @ObservedObject var accountsStore: AccountsStore
    let onToggleCollapse: () -> Void
    let onMarkRead: (Topic) -> Void
    let onToggleSuperFavorite: (Topic) -> Void
    let onRemoveFavorite: (Topic) -> Void
    let onFilterPosts: (Topic) -> Void
    let openContextProvider: (Topic) -> TopicOpenContext

    // Cast centralisé
    private var topics: [Topic] { (favorite.topics as? [Topic]) ?? [] }
    private var canCollapse: Bool { !topics.isEmpty }

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
        .padding(.top, isCollapsed ? density.collapsedHeaderTopPadding : density.sectionHeaderTopPadding)
        .padding(.bottom, isCollapsed ? density.collapsedHeaderBottomPadding : density.sectionHeaderBottomPadding)
        .padding(.trailing, 34)
        .overlay(alignment: .trailing) {
            if canCollapse {
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
                        onRemoveFavorite: { onRemoveFavorite(topic) },
                        onFilterPosts: { onFilterPosts(topic) },
                        openContext: openContextProvider(topic)
                    )
                    .contentShape(Rectangle())
                    .listRowInsets(density.rowInsets)
                }
            }
        }
    }
}


@MainActor
struct FavoritesListView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @StateObject private var accountsStore: AccountsStore
    @AppStorage("vos_sujets") private var favoritesTabBehavior = "0"
    @AppStorage("sujets_avec_cat") private var favoritesSortedByCategories = true
    @AppStorage("favorites_auto_refresh") private var favoritesAutoRefresh = false
    @AppStorage(AppLayoutCompactMode.key) private var compactModeEnabled = false
    @AppStorage("FavoritesShowCollapsedSections") private var showCollapsedSections = false
    @State private var visitedURLs: Set<String> = []
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false
    @State private var superFavoriteIDs: Set<Int>
    @State private var collapsedSectionIDs: Set<String>
    @State private var removingTopicIDs: Set<Int> = []
    @State private var topicActionErrorMessage: String?
    @State private var favoritePostFilterProgress: FavoritePostFilterProgress?
    @State private var favoritePostFilterStatusMessage: String?
    @State private var favoritePostFilterTask: Task<Void, Never>?
    @State private var favoritePostFilterStatusTask: Task<Void, Never>?
    @State private var favoritePostFilterTarget: FavoritePostFilterNavigationTarget?
    @State private var navigateToFavoritePostFilter = false

    private let topicActionService: FavoritesTopicActionServicing
    private let favoritePostFilterService: any FavoritePostFilteringServicing

    private struct FavoritePostFilterNavigationTarget: Identifiable {
        let id = UUID()
        let topic: Topic
        let result: FavoritePostFilterResult
    }

    private var isLoggedIn: Bool {
        accountsStore.currentAccount != nil
    }

    private var flattenedTopics: [Topic] {
        FavoritesTopicListOrdering.flattenedTopics(from: viewModel.favorites)
    }

    private var listDensity: FavoritesListDensity {
        FavoritesListDensity.value(isCompactModeEnabled: compactModeEnabled)
    }

    private var usesCategorizedFavoritesList: Bool {
        favoritesSortedByCategories
    }

    private var shouldShowEmptyFavoriteSections: Bool {
        showCollapsedSections && favoritesTabBehavior == "0"
    }

    private func topicOpenContext(for topic: Topic) -> TopicOpenContext {
        favoritesTabBehavior == "1" ? .favoritesOnly : .favorites
    }

    private func refreshContentForSessionState(force: Bool = false) {
        if isLoggedIn {
            if force {
                viewModel.loadFavorites(force: true)
            } else {
                viewModel.ensureLoaded()
            }
        } else {
            viewModel.clearForLoggedOut()
        }
    }

    private func refreshContentWhenViewAppears() {
        guard isLoggedIn else {
            viewModel.clearForLoggedOut()
            return
        }

        if favoritesAutoRefresh {
            guard !viewModel.isLoading else { return }
            viewModel.loadFavorites(force: true, shouldTriggerHaptic: false)
        } else {
            viewModel.ensureLoaded()
        }
    }

    @MainActor
    init(
        viewModel: FavoritesViewModel? = nil,
        accountsStore: AccountsStore? = nil,
        topicActionService: FavoritesTopicActionServicing = ForumFavoritesTopicActionService(),
        favoritePostFilterService: any FavoritePostFilteringServicing = ObjCFavoritePostFilterService()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? FavoritesViewModel())
        _accountsStore = StateObject(wrappedValue: accountsStore ?? AccountsStore())
        _superFavoriteIDs = State(initialValue: FavoritesSuperFavoriteStore.load())
        _collapsedSectionIDs = State(initialValue: FavoritesCollapsedSectionsStore.load())
        self.topicActionService = topicActionService
        self.favoritePostFilterService = favoritePostFilterService
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

    private func topics(in favorite: Favorite) -> [Topic] {
        (favorite.topics as? [Topic]) ?? []
    }

    private func shouldDisplayCategorizedFavorite(_ favorite: Favorite) -> Bool {
        let sectionID = sectionIdentifier(for: favorite)
        if collapsedSectionIDs.contains(sectionID), !showCollapsedSections {
            return false
        }
        if !topics(in: favorite).isEmpty {
            return true
        }
        return shouldShowEmptyFavoriteSections
    }

    private var displayedCategorizedFavorites: [Favorite] {
        viewModel.favorites.filter(shouldDisplayCategorizedFavorite(_:))
    }

    private var collapsibleSectionIDs: Set<String> {
        Set(viewModel.favorites.filter { !topics(in: $0).isEmpty }.map(sectionIdentifier(for:)))
    }

    private var shouldShowAllSectionsCollapsedState: Bool {
        usesCategorizedFavoritesList
        && !showCollapsedSections
        && !viewModel.isLoading
        && viewModel.errorMessage == nil
        && !collapsibleSectionIDs.isEmpty
        && displayedCategorizedFavorites.isEmpty
    }

    private var shouldShowNoFavoritesState: Bool {
        !viewModel.isLoading
        && viewModel.errorMessage == nil
        && !shouldShowAllSectionsCollapsedState
        && displayedCategorizedFavorites.isEmpty
        && flattenedTopics.isEmpty
    }

    private var allSectionsCollapsedState: some View {
        ContentUnavailableView {
            Label("Toutes les sections sont repliées", systemImage: "list.bullet.circle")
        } description: {
            Text("La vue filtrée masque les sections repliées.")
        } actions: {
            Button("Afficher les sections repliées") {
                AppHaptics.impact(.light)
                showCollapsedSections = true
            }
            Button("Tout déplier") {
                AppHaptics.impact(.light)
                expandAllSections()
            }
        }
        .listRowSeparator(.hidden)
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
        guard !viewModel.favorites.isEmpty else { return }
        let validIDs = Set(viewModel.favorites.map(sectionIdentifier(for:)))
        let filtered = collapsedSectionIDs.intersection(validIDs)
        if filtered != collapsedSectionIDs {
            collapsedSectionIDs = filtered
            FavoritesCollapsedSectionsStore.save(filtered)
        }
    }

    private func collapseAllSections() {
        collapsedSectionIDs = collapsibleSectionIDs
        FavoritesCollapsedSectionsStore.save(collapsibleSectionIDs)
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
                    if let errorMessage = viewModel.errorMessage {
                        Text("Erreur : \(errorMessage)")
                            .foregroundStyle(.red)
                    }
                    if shouldShowAllSectionsCollapsedState {
                        allSectionsCollapsedState
                    }
                    if shouldShowNoFavoritesState {
                        Text("Aucun favori")
                            .foregroundStyle(.secondary)
                    }
                    if usesCategorizedFavoritesList {
                        ForEach(displayedCategorizedFavorites) { favorite in
                            let sectionID = sectionIdentifier(for: favorite)
                            FavoriteSectionView(
                                favorite: favorite,
                                sectionID: sectionID,
                                isCollapsed: collapsedSectionIDs.contains(sectionID),
                                density: listDensity,
                                visitedURLs: $visitedURLs,
                                superFavoriteIDs: $superFavoriteIDs,
                                removingTopicIDs: removingTopicIDs,
                                accountsStore: accountsStore,
                                onToggleCollapse: {
                                    toggleSectionCollapse(sectionID: sectionID)
                                },
                                onMarkRead: markTopicAsRead(_:),
                                onToggleSuperFavorite: toggleSuperFavorite(_:),
                                onRemoveFavorite: removeFavoriteFlag(_:),
                                onFilterPosts: filterPosts(_:),
                                openContextProvider: topicOpenContext(for:)
                            )
                        }
                    } else {
                        ForEach(flattenedTopics) { topic in
                            let postID = Int(topic.postID)
                            TopicRowView(
                                topic: topic,
                                visitedURLs: $visitedURLs,
                                isSuperFavorite: superFavoriteIDs.contains(postID),
                                isRemovingFavorite: removingTopicIDs.contains(postID),
                                onMarkRead: { markTopicAsRead(topic) },
                                onToggleSuperFavorite: { toggleSuperFavorite(topic) },
                                onRemoveFavorite: { removeFavoriteFlag(topic) },
                                onFilterPosts: { filterPosts(topic) },
                                openContext: topicOpenContext(for: topic)
                            )
                            .contentShape(Rectangle())
                            .listRowInsets(listDensity.rowInsets)
                        }
                    }
                }
            }
            .compactListSectionSpacing(compactModeEnabled, spacing: listDensity.sectionSpacing, regularSpacing: listDensity.sectionSpacing)
            .refreshable {
                await MainActor.run { viewModel.loadFavorites(shouldTriggerHaptic: true) }
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    @Sendable func checkDone() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            if viewModel.isLoading { checkDone() } else { continuation.resume() }
                        }
                    }
                    checkDone()
                }
            }
            .navigationTitle("Favoris")
            .safeAreaInset(edge: .bottom) {
                if favoritePostFilterProgress != nil || favoritePostFilterStatusMessage != nil {
                    FavoritePostFilterProgressBanner(
                        progress: favoritePostFilterProgress,
                        statusMessage: favoritePostFilterStatusMessage,
                        onAction: favoritePostFilterStatusMessage == nil ? cancelFavoritePostFilter : dismissFavoritePostFilterStatusMessage
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                superFavoriteIDs = FavoritesSuperFavoriteStore.load()
                collapsedSectionIDs = FavoritesCollapsedSectionsStore.load()
                refreshContentWhenViewAppears()
                pruneCollapsedSections()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kLoginChangedNotification"))) { _ in
                refreshContentForSessionState(force: true)
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
                AppHaptics.refreshStarted()
                viewModel.loadFavorites(force: true, shouldTriggerHaptic: true)
            }
            .toolbar {
                MainToolbarContent(
                    onRefresh: {
                        viewModel.loadFavorites(shouldTriggerHaptic: true)
                    },
                    isLoading: viewModel.isLoading,
                    profileImage: accountsStore.currentAvatarImage,
                    profileImageURL: nil,
                    leadingRefreshItem: AnyView(
                        Button {
                            AppHaptics.impact(.light)
                            showCollapsedSections.toggle()
                        } label: {
                            Image(systemName: showCollapsedSections ? "list.bullet.circle.fill" : "list.bullet.circle")
                                .foregroundStyle(.primary)
                        }
                        .disabled(!usesCategorizedFavoritesList)
                        .contextMenu {
                            Button {
                                collapseAllSections()
                            } label: {
                                MenuActionLabel("Tout replier", systemImage: "rectangle.compress.vertical")
                            }
                            .disabled(!usesCategorizedFavoritesList || collapsibleSectionIDs.isEmpty || collapsibleSectionIDs.isSubset(of: collapsedSectionIDs))

                            Button {
                                expandAllSections()
                            } label: {
                                MenuActionLabel("Tout déplier", systemImage: "rectangle.expand.vertical")
                            }
                            .disabled(!usesCategorizedFavoritesList || collapsedSectionIDs.isEmpty)
                        } preview: {
                            Color.clear.frame(width: 1, height: 1)
                        }
                        .accessibilityLabel(
                            showCollapsedSections
                                ? "Masquer les sections repliées"
                                : "Afficher les sections repliées"
                        )
                    )
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
                    Button {
                        showAddAccountSheet = true
                    } label: {
                        MenuActionLabel("Ajouter un pseudo", systemImage: "person.badge.plus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        MenuActionLabel("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive)
                    }
                    .disabled(accountsStore.currentAccount == nil)
                }
            }
            .sheet(isPresented: $showAddAccountSheet) {
                AddAccountView(accountsStore: accountsStore)
            }
            .background {
                NavigationLink(
                    "",
                    isActive: $navigateToFavoritePostFilter
                ) {
                    if let favoritePostFilterTarget {
                        MessagesView(
                            topic: favoritePostFilterTarget.topic,
                            curPage: favoritePostFilterTarget.result.endPage,
                            maxPage: favoritePostFilterTarget.result.maxPage,
                            separatorNewMessages: false,
                            navigationDepth: 1,
                            initialFavoritePostFilterResult: favoritePostFilterTarget.result
                        )
                        .toolbar(.hidden, for: .tabBar)
                    } else {
                        EmptyView()
                    }
                }
                .hidden()
                .allowsHitTesting(false)
            }
            .alert("Déconnexion", isPresented: $showLogoutConfirm) {
                Button("Annuler", role: .cancel) {}
                Button("Déconnecter", role: .destructive) {
                    accountsStore.deleteCurrent()
                }
            } message: {
                Text("Déconnecter le compte courant ?")
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
        let url = topic.aURL ?? topic.aURLOfLastPage ?? topic.aURLOfLastPost ?? ""
        if !url.isEmpty {
            visitedURLs.insert(url)
        }
        topic.isLocallyViewedInApp = true
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

    private func filterPosts(_ topic: Topic) {
        guard favoritePostFilterProgress == nil else { return }

        favoritePostFilterStatusTask?.cancel()
        favoritePostFilterStatusTask = nil
        favoritePostFilterStatusMessage = nil

        favoritePostFilterProgress = FavoritePostFilterProgress(
            currentPage: max(Int(topic.curTopicPage), 1),
            maxPage: max(Int(topic.maxTopicPage), 1),
            resultCount: 0
        )

        favoritePostFilterTask?.cancel()
        favoritePostFilterTask = Task { @MainActor in
            let result = await favoritePostFilterService.filterPosts(
                topic: topic,
                startPage: nil
            ) { progress in
                withAnimation(.easeOut(duration: 0.18)) {
                    favoritePostFilterProgress = progress
                }
            }

            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                favoritePostFilterProgress = nil
            }
            favoritePostFilterTask = nil

            switch result {
            case .success(let filterResult):
                favoritePostFilterTarget = FavoritePostFilterNavigationTarget(
                    topic: topic,
                    result: filterResult
                )
                navigateToFavoritePostFilter = true
            case .failure(.noResult):
                showFavoritePostFilterStatusMessage("Aucun post n'a été trouvé")
            case .failure(let error):
                topicActionErrorMessage = error.localizedDescription
            }
        }
    }

    private func cancelFavoritePostFilter() {
        favoritePostFilterTask?.cancel()
        favoritePostFilterTask = nil
        favoritePostFilterService.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            favoritePostFilterProgress = nil
        }
    }

    private func showFavoritePostFilterStatusMessage(_ message: String) {
        favoritePostFilterStatusTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            favoritePostFilterStatusMessage = message
        }
        favoritePostFilterStatusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            dismissFavoritePostFilterStatusMessage()
        }
    }

    private func dismissFavoritePostFilterStatusMessage() {
        favoritePostFilterStatusTask?.cancel()
        favoritePostFilterStatusTask = nil
        withAnimation(.easeOut(duration: 0.18)) {
            favoritePostFilterStatusMessage = nil
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
    var onFilterPosts: (() -> Void)?
    var openContext: TopicOpenContext = .favorites
    @Environment(\.appThemePalette) private var themePalette
    
    private var isVisited: Bool {
        let url = topic.aURL ?? topic.aURLOfLastPage ?? topic.aURLOfLastPost ?? ""
        return topic.isViewed || topic.isLocallyViewedInApp || visitedURLs.contains(url)
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
            titleFont: nil,
            titleBaseSize: 14.3,
            titleWeight: isVisited ? .regular : .semibold,
            showUnreadBadge: true,
            showUnreadBadgeWhenZero: false,
            leadingBottomText: pageLabel,
            trailingBottomText: trailingLabel,
            rowBackgroundTint: isSuperFavorite ? themePalette.superFavoriteBackgroundColor : nil,
            contentPadding: EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 0),
            rowBackgroundOverflow: isSuperFavorite
                ? EdgeInsets(top: 4, leading: 8, bottom: 2, trailing: 8)
                : EdgeInsets(),
            openContext: openContext,
            extraContextMenu: {
                AnyView(
                    Group {
                        if let onMarkRead {
                            Button {
                                onMarkRead()
                            } label: {
                                MenuActionLabel("Lu", systemImage: "checkmark")
                            }
                        }
                        if let onToggleSuperFavorite {
                            Button {
                                onToggleSuperFavorite()
                            } label: {
                                MenuActionLabel(
                                    isSuperFavorite ? "Retirer super favori" : "Super favori",
                                    systemImage: isSuperFavorite ? "star.slash" : "star"
                                )
                            }
                        }
                        if let onRemoveFavorite {
                            Button(role: .destructive) {
                                onRemoveFavorite()
                            } label: {
                                MenuActionLabel("Supprimer", systemImage: "trash", role: .destructive)
                            }
                            .disabled(isRemovingFavorite)
                        }
                        if let onFilterPosts {
                            Divider()
                            Button {
                                onFilterPosts()
                            } label: {
                                MenuActionLabel("Filtrer les posts", systemImage: "line.3.horizontal.decrease.circle")
                            }
                        }
                    }
                )
            }
        ) { openedURL in
            let url = openedURL ?? topic.aURL ?? topic.aURLOfLastPage ?? topic.aURLOfLastPost ?? ""
            if !url.isEmpty {
                visitedURLs.insert(url)
            }
            topic.isLocallyViewedInApp = true
            topic.isViewed = true
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

private struct FavoritePostFilterProgressBanner: View {
    let progress: FavoritePostFilterProgress?
    let statusMessage: String?
    let onAction: () -> Void

    private var displayText: String {
        statusMessage ?? progress?.statusText ?? ""
    }

    private var buttonTitle: String {
        statusMessage == nil ? "Annuler" : "OK"
    }

    var body: some View {
        HStack(spacing: 10) {
            if statusMessage == nil {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(displayText)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(buttonTitle) {
                onAction()
            }
            .font(.footnote.weight(.semibold))
            .controlSize(.small)
            .buttonBorderShape(.capsule)
            .hfrGlassButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hfrLoadingPanel(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            title: "Jeux vidéo",
            topics: [
                topic(title: "Migration SwiftUI", author: "alice", date: "il y a 1h"),
                topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10),
                topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10)
            ]
        ),
        favorite(
            title: "Programmation",
            topics: [
                topic(title: "Migration SwiftUI", author: "alice", date: "il y a 1h"),
                topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10),
                topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10)
            ]
        ),
        favorite(
            title: "Discussion",
            topics: [
                topic(title: "Migration SwiftUI", author: "alice", date: "il y a 1h"),
                topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10),
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
