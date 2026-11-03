//
//  ContentView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import Combine
import UIKit
import OSLog

@MainActor
final class CategoriesListViewModel: ObservableObject {
    @Published var forums: [Forum] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let forumsLoader: ForumsLoading

    init(forumsLoader: ForumsLoading? = nil) {
        self.forumsLoader = forumsLoader ?? ObjCForumsLoader()
    }

    func load(shouldTriggerHaptic: Bool = false) {
        isLoading = true
        errorMessage = nil
        forumsLoader.fetchForums { [weak self] forums, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.forums = []
                } else {
                    self.errorMessage = nil
                    self.forums = forums ?? []
                }
                if shouldTriggerHaptic {
                    AppHaptics.refreshCompleted()
                }
            }
        }
    }
}

@MainActor
final class ForumTopicsListViewModel: ObservableObject {
    @Published var topics: [Topic] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var selectedFlag: TopicListFlag = .all
    @Published var newTopicURL: URL?
    @Published var pageInfo: ForumSearchPageInfo = .empty

    private var forum: Forum
    private let topicsLoader: ForumTopicsLoading
    private var loadRequestID = 0

    init(
        forum: Forum,
        topicsLoader: ForumTopicsLoading? = nil
    ) {
        self.forum = forum
        self.topicsLoader = topicsLoader ?? ObjCForumTopicsLoader()
    }

    func updateForum(_ forum: Forum) {
        self.forum = forum
    }

    func load(pageURL: String? = nil, shouldTriggerHaptic: Bool = false) {
        loadRequestID += 1
        let requestID = loadRequestID
        isLoading = true
        errorMessage = nil
        newTopicURL = nil
        pageInfo = .empty
        topicsLoader.fetchTopics(for: forum, flag: selectedFlag, pageURL: pageURL) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard requestID == self.loadRequestID else { return }
                self.isLoading = false
                if let error {
                    if Self.isCancellationError(error) {
                        // Ignore cancelled requests when a newer load supersedes an older one.
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    self.topics = []
                    self.newTopicURL = nil
                    self.pageInfo = .empty
                } else {
                    self.errorMessage = nil
                    self.topics = result?.topics ?? []
                    self.newTopicURL = result?.newTopicURL
                    self.pageInfo = result?.pageInfo ?? .empty
                }
                if shouldTriggerHaptic {
                    AppHaptics.refreshCompleted()
                }
            }
        }
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        if nsError.domain == "ASIHTTPRequestErrorDomain" && nsError.code == 4 {
            return true
        }
        return nsError.localizedDescription.lowercased().contains("cancel")
    }

    func removeTopic(_ topic: Topic) {
        topics.removeAll { $0 === topic }
    }

    func clearFlagMetadata(for topic: Topic) {
        topic.aTypeOfFlag = ""
        topic.aURLOfFlag = ""
        topic.curTopicPage = 0
        topics = topics
    }
}

@MainActor
struct CategoriesListView: View {
    @StateObject private var viewModel: CategoriesListViewModel
    @StateObject private var accountsStore: AccountsStore
    @Environment(\.appThemePalette) private var themePalette
    private let selectedTopicID: TopicNavigationID?
    private let onSelectTopic: ((TopicNavigationTarget) -> Void)?
    private let onSelectForum: ((Forum) -> Void)?
    @State private var hasLoaded = false
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false

    @MainActor
    init(
        viewModel: CategoriesListViewModel? = nil,
        accountsStore: AccountsStore? = nil,
        selectedTopicID: TopicNavigationID? = nil,
        onSelectTopic: ((TopicNavigationTarget) -> Void)? = nil,
        onSelectForum: ((Forum) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? CategoriesListViewModel())
        _accountsStore = StateObject(wrappedValue: accountsStore ?? AccountsStore())
        self.selectedTopicID = selectedTopicID
        self.onSelectTopic = onSelectTopic
        self.onSelectForum = onSelectForum
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = viewModel.errorMessage {
                    Text("Erreur : \(errorMessage)")
                        .foregroundStyle(.red)
                        .listRowBackground(themePalette.listRowBackgroundColor)
                }
                if !viewModel.isLoading && viewModel.forums.isEmpty && viewModel.errorMessage == nil {
                    Text("Aucune categorie")
                        .foregroundStyle(.secondary)
                        .listRowBackground(themePalette.listRowBackgroundColor)
                }
                ForEach(viewModel.forums) { forum in
                    if let onSelectForum {
                        Button {
                            onSelectForum(forum)
                        } label: {
                            forumRowLabel(forum)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            ForumTopicsListView(
                                forum: forum,
                                accountsStore: accountsStore,
                                selectedTopicID: selectedTopicID,
                                onSelectTopic: onSelectTopic
                            )
                        } label: {
                            forumRowLabel(forum)
                        }
                    }
                }
                .listRowBackground(themePalette.listRowBackgroundColor)
            }
            .scrollContentBackground(.hidden)
            .background(themePalette.listBackgroundColor)
            .navigationTitle("Categories")
            .expandedPhoneInlineNavigationTitle()
            .foldHandoffDestination()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        accountMenuItems
                    } label: {
                        ToolbarProfileImage(image: accountsStore.currentAvatarImage, url: nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.refreshStarted()
                        viewModel.load(shouldTriggerHaptic: true)
                    } label: {
                        Label {
                            Text("Actualiser")
                        } icon: {
                            ToolbarRefreshIcon(isLoading: viewModel.isLoading)
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .onAppear {
                if !hasLoaded {
                    viewModel.load()
                    hasLoaded = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kLoginChangedNotification"))) { _ in
                viewModel.load()
            }
            .onReceive(NotificationCenter.default.publisher(for: .rootTabReselected)) { notification in
                guard
                    let rawTab = notification.userInfo?["tab"] as? Int,
                    rawTab == RootTabIdentifier.categories.rawValue
                else {
                    return
                }
                AppHaptics.refreshStarted()
                viewModel.load(shouldTriggerHaptic: true)
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
                Text("Déconnecter le compte courant ?")
            }
        }
    }

    private func forumRowLabel(_ forum: Forum) -> some View {
        HStack(spacing: 12) {
            ForumCategoryIconView(forum: forum)

            VStack(alignment: .leading, spacing: 4) {
                Text(forum.aTitle ?? "Forum")
                    .foregroundStyle(.primary)
                if let subForums = forum.subCats as? [Forum], !subForums.isEmpty {
                    Text("\(subForums.count) sous-forums")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var accountMenuItems: some View {
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

@MainActor
struct ForumTopicsListView: View {
    let forum: Forum
    let initialFlagOverride: TopicListFlag?
    @StateObject private var viewModel: ForumTopicsListViewModel
    @ObservedObject private var accountsStore: AccountsStore
    @Environment(\.appThemePalette) private var themePalette
    @AppStorage("HFRswiftGlobalTopicListFlag") private var globalTopicListFlagRawValue = TopicListFlag.all.rawValue
    @State private var hasLoaded = false
    @State private var visitedURLs: Set<String> = []
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false
    @State private var removingTopicIDs: Set<ObjectIdentifier> = []
    @State private var topicActionErrorMessage: String?
    @State private var selectedForumIdentifier: String
    @State private var isNewTopicComposerPresented = false
    @State private var newTopicDraftText = ""
    @State private var isPagePickerPresented = false
    @State private var pagePickerInput = "1"

    private let topicActionService: FavoritesTopicActionServicing
    private let selectedTopicID: TopicNavigationID?
    private let onSelectTopic: ((TopicNavigationTarget) -> Void)?
    private let onBack: (() -> Void)?
    private let onContentContextChange: (() -> Void)?

    @MainActor
    init(
        forum: Forum,
        initialFlagOverride: TopicListFlag? = nil,
        viewModel: ForumTopicsListViewModel? = nil,
        accountsStore: AccountsStore? = nil,
        topicActionService: FavoritesTopicActionServicing = ForumFavoritesTopicActionService(),
        selectedTopicID: TopicNavigationID? = nil,
        onSelectTopic: ((TopicNavigationTarget) -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onContentContextChange: (() -> Void)? = nil
    ) {
        self.forum = forum
        self.initialFlagOverride = initialFlagOverride
        _viewModel = StateObject(wrappedValue: viewModel ?? ForumTopicsListViewModel(forum: forum))
        self._accountsStore = ObservedObject(wrappedValue: accountsStore ?? AccountsStore())
        _selectedForumIdentifier = State(initialValue: ForumTopicsListView.forumIdentifier(for: forum))
        self.topicActionService = topicActionService
        self.selectedTopicID = selectedTopicID
        self.onSelectTopic = onSelectTopic
        self.onBack = onBack
        self.onContentContextChange = onContentContextChange
    }

    private static func forumIdentifier(for forum: Forum) -> String {
        let candidates = [
            forum.aURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            forum.aID?.trimmingCharacters(in: .whitespacesAndNewlines),
            forum.aTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let resolved = candidates.first(where: { ($0 ?? "").isEmpty == false }) {
            return resolved ?? "forum-root"
        }
        return "forum-root"
    }

    private var subForums: [Forum] {
        (forum.subCats as? [Forum]) ?? []
    }

    private var availableForums: [Forum] {
        [forum] + subForums
    }

    private var resolvedSelectedForum: Forum {
        availableForums.first(where: { Self.forumIdentifier(for: $0) == selectedForumIdentifier }) ?? forum
    }

    private var persistedGlobalFlag: TopicListFlag {
        TopicListFlag(rawValue: globalTopicListFlagRawValue) ?? .all
    }

    private var initialFlagForCurrentPresentation: TopicListFlag {
        let preferredFlag = initialFlagOverride ?? persistedGlobalFlag
        if !isLoggedIn && preferredFlag != .all {
            return .all
        }
        return preferredFlag
    }

    private var isLoggedIn: Bool {
        accountsStore.currentAccount != nil
    }

    private var shouldShowPagination: Bool {
        max(viewModel.pageInfo.lastPageNumber, 1) > 1
    }

    private var navigationTitleText: String {
        forum.aTitle ?? "Topics"
    }

    private var navigationSubtitleText: String? {
        guard shouldShowPagination else { return nil }
        return "Page \(max(viewModel.pageInfo.pageNumber, 1)) / \(max(viewModel.pageInfo.lastPageNumber, 1))"
    }

    private func loadPage(_ urlString: String?) {
        guard let urlString = normalizedNonEmpty(urlString) else { return }
        onContentContextChange?()
        AppHaptics.refreshStarted()
        viewModel.load(pageURL: urlString, shouldTriggerHaptic: true)
    }

    private func pageURL(for page: Int) -> String? {
        let boundedPage = min(max(page, 1), max(viewModel.pageInfo.lastPageNumber, 1))
        switch boundedPage {
        case viewModel.pageInfo.pageNumber:
            return viewModel.pageInfo.currentURL
        case viewModel.pageInfo.firstPageNumber:
            return viewModel.pageInfo.firstPageURL ?? TopicPageURLRouting.replacingPage(in: viewModel.pageInfo.currentURL ?? "", page: boundedPage)
        case viewModel.pageInfo.lastPageNumber:
            return viewModel.pageInfo.lastPageURL ?? TopicPageURLRouting.replacingPage(in: viewModel.pageInfo.currentURL ?? "", page: boundedPage)
        case viewModel.pageInfo.pageNumber - 1:
            return viewModel.pageInfo.previousPageURL ?? TopicPageURLRouting.replacingPage(in: viewModel.pageInfo.currentURL ?? "", page: boundedPage)
        case viewModel.pageInfo.pageNumber + 1:
            return viewModel.pageInfo.nextPageURL ?? TopicPageURLRouting.replacingPage(in: viewModel.pageInfo.currentURL ?? "", page: boundedPage)
        default:
            guard let baseURL = [
                viewModel.pageInfo.currentURL,
                viewModel.pageInfo.firstPageURL,
                viewModel.pageInfo.lastPageURL,
                resolvedSelectedForum.aURL
            ].compactMap({ normalizedNonEmpty($0) }).first else {
                return nil
            }
            return TopicPageURLRouting.replacingPage(in: baseURL, page: boundedPage)
        }
    }

    private func openPagePicker() {
        pagePickerInput = "\(max(viewModel.pageInfo.pageNumber, 1))"
        isPagePickerPresented = true
    }

    private func navigateToPage(_ page: Int) {
        loadPage(pageURL(for: page))
    }

    private func footerLeft(for topic: Topic) -> String {
        let currentPage = Int(topic.curTopicPage)
        let maxPage = max(Int(topic.maxTopicPage), 1)
        let pollSuffix = topic.isPoll ? " \u{2263}" : ""
        let pageLabel = maxPage > 1 ? "pages" : "page"

        if topic.isViewedFromForumAtLoad {
            return "⚑\(pollSuffix) \(maxPage) / \(maxPage)"
        }
        if topicHasFlag(topic), currentPage > 0 && currentPage <= maxPage {
            return "⚑\(pollSuffix) \(currentPage) / \(maxPage)"
        }
        return "\(maxPage) \(pageLabel)\(pollSuffix)"
    }

    private func rowBackgroundTint(for topic: Topic) -> Color? {
        if !topicHasFlag(topic) {
            return nil
        }
        guard
            let flagType = topic.aTypeOfFlag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !flagType.isEmpty
        else {
            return nil
        }

        switch flagType {
        case "yellow", "blue", "red":
            return themePalette.topicFlagBackgroundColor(flagType: flagType)
        default:
            return nil
        }
    }

    private func footerRight(for topic: Topic) -> String? {
        guard
            let author = topic.aAuthorOfLastPost,
            let when = topic.aDateOfLastPost
        else {
            return nil
        }
        return "\(author) - \(when)"
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func topicHasFlag(_ topic: Topic) -> Bool {
        if viewModel.selectedFlag != .all {
            return true
        }
        return normalizedNonEmpty(topic.aTypeOfFlag) != nil || normalizedNonEmpty(topic.aURLOfFlag) != nil
    }

    private func isLocallyViewed(_ topic: Topic) -> Bool {
        let openedURL = topic.aURL ?? topic.aURLOfLastPage ?? ""
        return topic.isLocallyViewedInApp || visitedURLs.contains(openedURL)
    }

    private func isDisplayedAsViewed(_ topic: Topic) -> Bool {
        topic.isViewedFromForumAtLoad || isLocallyViewed(topic)
    }

    private func topicIdentifiers(for topic: Topic) -> (postID: Int, categoryID: Int)? {
        let explicitPostID = Int(topic.postID)
        let explicitCategoryID = Int(topic.catID)
        if explicitPostID > 0, explicitCategoryID > 0 {
            return (explicitPostID, explicitCategoryID)
        }

        let urlCandidates = [
            topic.aURLOfFlag,
            topic.aURL,
            topic.aURLOfLastPost,
            topic.aURLOfLastPage,
            topic.aURLOfFirstPage
        ]

        var parsedPostID: Int?
        var parsedCategoryID: Int?
        for rawURL in urlCandidates {
            guard let rawURL = normalizedNonEmpty(rawURL) else { continue }
            if parsedPostID == nil {
                parsedPostID = extractQueryItemInt(named: "post", from: rawURL) ?? extractPostIDFromPath(rawURL)
            }
            if parsedCategoryID == nil {
                parsedCategoryID = extractQueryItemInt(named: "cat", from: rawURL)
            }
            if parsedPostID != nil, parsedCategoryID != nil {
                break
            }
        }

        let fallbackCategoryID = Int(forum.getHFRID())
        let resolvedPostID = parsedPostID ?? explicitPostID
        let resolvedCategoryID: Int
        if let parsedCategoryID, parsedCategoryID > 0 {
            resolvedCategoryID = parsedCategoryID
        } else if explicitCategoryID > 0 {
            resolvedCategoryID = explicitCategoryID
        } else {
            resolvedCategoryID = fallbackCategoryID
        }
        guard resolvedPostID > 0, resolvedCategoryID > 0 else {
            return nil
        }
        return (resolvedPostID, resolvedCategoryID)
    }

    private func extractQueryItemInt(named name: String, from rawURL: String) -> Int? {
        guard
            let components = URLComponents(string: rawURL),
            let value = components.queryItems?.first(where: { $0.name == name })?.value,
            let intValue = Int(value),
            intValue > 0
        else {
            return nil
        }
        return intValue
    }

    private func extractPostIDFromPath(_ rawURL: String) -> Int? {
        let pattern = "sujet_(\\d+)_"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(rawURL.startIndex..<rawURL.endIndex, in: rawURL)
        guard
            let match = regex.firstMatch(in: rawURL, options: [], range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: rawURL),
            let value = Int(rawURL[captureRange]),
            value > 0
        else {
            return nil
        }
        return value
    }

    private func markTopicAsRead(_ topic: Topic) {
        let openedURL = normalizedNonEmpty(topic.aURL) ?? normalizedNonEmpty(topic.aURLOfLastPage) ?? normalizedNonEmpty(topic.aURLOfFlag)
        if let openedURL {
            visitedURLs.insert(openedURL)
        }
        topic.isLocallyViewedInApp = true
        topic.isViewed = true
    }

    private func removeFlag(_ topic: Topic) {
        guard let identifiers = topicIdentifiers(for: topic) else {
            topicActionErrorMessage = FavoritesTopicActionError.invalidTopicIdentifier.localizedDescription
            return
        }

        let topicID = ObjectIdentifier(topic)
        guard !removingTopicIDs.contains(topicID) else { return }

        removingTopicIDs.insert(topicID)
        Task {
            do {
                try await topicActionService.removeFavoriteFlag(postID: identifiers.postID, categoryID: identifiers.categoryID)
                withAnimation(.easeOut(duration: 0.18)) {
                    if viewModel.selectedFlag == .all {
                        viewModel.clearFlagMetadata(for: topic)
                    } else {
                        viewModel.removeTopic(topic)
                    }
                }
            } catch {
                topicActionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            removingTopicIDs.remove(topicID)
        }
    }

    private func extraContextMenu(for topic: Topic, hasFlag: Bool, isRemoving: Bool) -> (() -> AnyView)? {
        guard hasFlag else { return nil }
        return {
            AnyView(
                Group {
                    Button {
                        markTopicAsRead(topic)
                    } label: {
                        MenuActionLabel("Lu", systemImage: "checkmark")
                    }
                    Button(role: .destructive) {
                        removeFlag(topic)
                    } label: {
                        MenuActionLabel("Supprimer", systemImage: "trash", role: .destructive)
                    }
                    .disabled(isRemoving)
                }
            )
        }
    }

    var body: some View {
        List {
            if !subForums.isEmpty {
                LabeledContent("Sous-forum") {
                    Picker("Sous-forum", selection: $selectedForumIdentifier) {
                        Text("Tous les sous-forums")
                            .tag(Self.forumIdentifier(for: forum))
                        ForEach(subForums) { subForum in
                            Text(subForum.aTitle ?? "Sous-forum")
                                .tag(Self.forumIdentifier(for: subForum))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(themePalette.listElevatedBackgroundColor)
            }

            Picker("Filtre", selection: $viewModel.selectedFlag) {
                Text("Tous").tag(TopicListFlag.all)
                Text("Favoris")
                    .tag(TopicListFlag.favorites)
                    .disabled(!isLoggedIn)
                Text("Suivis")
                    .tag(TopicListFlag.tracked)
                    .disabled(!isLoggedIn)
                Text("Lus")
                    .tag(TopicListFlag.read)
                    .disabled(!isLoggedIn)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(themePalette.listElevatedBackgroundColor)

            if !isLoggedIn {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Connexion requise pour Favoris, Suivis et Lus", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote.weight(.semibold))
                    Text("Vous pouvez consulter \"Tous\" sans compte.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(themePalette.listElevatedBackgroundColor)
            }

            if let errorMessage = viewModel.errorMessage {
                Text("Erreur : \(errorMessage)")
                    .foregroundStyle(.red)
                    .listRowBackground(themePalette.listRowBackgroundColor)
            }
            if !viewModel.isLoading && viewModel.topics.isEmpty && viewModel.errorMessage == nil {
                Text("Aucun topic")
                    .foregroundStyle(.secondary)
                    .listRowBackground(themePalette.listRowBackgroundColor)
            }

            ForEach(viewModel.topics) { topic in
                let hasFlag = topicHasFlag(topic)
                let topicID = ObjectIdentifier(topic)
                let isRemoving = removingTopicIDs.contains(topicID)
                let isVisited = isDisplayedAsViewed(topic)
                TopicListRowView(
                    topic: topic,
                    isVisited: isVisited,
                    titleFont: nil,
                    titleBaseSize: 14.3,
                    titleWeight: isVisited ? .regular : .semibold,
                    showUnreadBadge: hasFlag && !topic.isViewedFromForumAtLoad,
                    leadingBottomText: footerLeft(for: topic),
                    trailingBottomText: footerRight(for: topic),
                    rowBackgroundTint: rowBackgroundTint(for: topic),
                    contentPadding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0),
                    rowBackgroundOverflow: hasFlag
                        ? EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
                        : EdgeInsets(),
                    openContext: .forum(selectedFlag: viewModel.selectedFlag),
                    extraContextMenu: extraContextMenu(for: topic, hasFlag: hasFlag, isRemoving: isRemoving),
                    selectedTopicID: selectedTopicID,
                    onSelectTarget: onSelectTopic
                ) { openedURL in
                    if let openedURL, !openedURL.isEmpty {
                        visitedURLs.insert(openedURL)
                    }
                    topic.isLocallyViewedInApp = true
                    topic.isViewed = true
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if hasFlag {
                        Button {
                            markTopicAsRead(topic)
                        } label: {
                            Label("Lu", systemImage: "checkmark")
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if hasFlag {
                        Button(role: .destructive) {
                            removeFlag(topic)
                        } label: {
                            Label(isRemoving ? "Suppression..." : "Supprimer", systemImage: isRemoving ? "hourglass" : "trash")
                        }
                        .disabled(isRemoving)
                    }
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                .listRowBackground(themePalette.listRowBackgroundColor)
            }

            if shouldShowPagination {
                ForumTopicsPaginationBar(
                    pageInfo: viewModel.pageInfo,
                    onFirst: { loadPage(viewModel.pageInfo.firstPageURL) },
                    onPrevious: { loadPage(viewModel.pageInfo.previousPageURL) },
                    onPagePicker: openPagePicker,
                    onNext: { loadPage(viewModel.pageInfo.nextPageURL) },
                    onLast: { loadPage(viewModel.pageInfo.lastPageURL) }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 18, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(themePalette.listElevatedBackgroundColor)
            }
        }
        .scrollContentBackground(.hidden)
        .background(themePalette.listBackgroundColor)
        .refreshable {
            await MainActor.run { viewModel.load(shouldTriggerHaptic: true) }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                @Sendable func checkDone() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if viewModel.isLoading { checkDone() } else { continuation.resume() }
                    }
                }
                checkDone()
            }
        }
        .navigationTitle(navigationTitleText)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if let onBack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Retour aux catégories")
                }
                Menu {
                    accountMenuItems
                } label: {
                    ToolbarProfileImage(image: accountsStore.currentAvatarImage, url: nil)
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(navigationTitleText)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let navigationSubtitleText {
                        Text(navigationSubtitleText)
                            .font(.caption2)
                            .foregroundStyle(.primary.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .multilineTextAlignment(.center)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    AppHaptics.impact(.light)
                    isNewTopicComposerPresented = true
                } label: {
                    Label("Nouveau sujet", systemImage: "plus.bubble")
                }
                .disabled(!isLoggedIn || viewModel.newTopicURL == nil)

                Button {
                    AppHaptics.refreshStarted()
                    viewModel.load(shouldTriggerHaptic: true)
                } label: {
                    Label {
                        Text("Actualiser")
                    } icon: {
                        ToolbarRefreshIcon(isLoading: viewModel.isLoading)
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .onAppear {
            if !hasLoaded {
                let initialFlag = initialFlagForCurrentPresentation
                if viewModel.selectedFlag != initialFlag {
                    viewModel.selectedFlag = initialFlag
                }
                viewModel.updateForum(resolvedSelectedForum)
                viewModel.load()
                hasLoaded = true
            }
        }
        .onChange(of: selectedForumIdentifier) { _, _ in
            onContentContextChange?()
            viewModel.updateForum(resolvedSelectedForum)
            guard hasLoaded else { return }
            viewModel.load()
        }
        .onChange(of: viewModel.selectedFlag) { _, newValue in
            if !isLoggedIn && newValue != .all {
                viewModel.selectedFlag = .all
                return
            }
            if globalTopicListFlagRawValue != newValue.rawValue {
                globalTopicListFlagRawValue = newValue.rawValue
            }
            onContentContextChange?()
            guard hasLoaded else { return }
            viewModel.load()
        }
        .onChange(of: accountsStore.currentAccount?.id) { _, _ in
            if !isLoggedIn && viewModel.selectedFlag != .all {
                viewModel.selectedFlag = .all
                return
            }
            guard hasLoaded else { return }
            AppHaptics.refreshStarted()
            viewModel.load(shouldTriggerHaptic: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .rootTabReselected)) { notification in
            guard
                let rawTab = notification.userInfo?["tab"] as? Int,
                rawTab == RootTabIdentifier.categories.rawValue
            else {
                return
            }
            viewModel.load()
        }
        .sheet(isPresented: $showAddAccountSheet) {
            AddAccountView(accountsStore: accountsStore)
        }
        .sheet(isPresented: $isNewTopicComposerPresented) {
            AnswerView(
                topicURL: viewModel.newTopicURL,
                title: "Nouv. Sujet",
                requiresSubject: true,
                requiresSubcategory: true,
                offersPollConfiguration: true,
                subjectCharacterLimit: 70,
                subjectPlaceholder: "Sujet du topic",
                initialMessage: newTopicDraftText,
                onPostSuccess: { _ in
                    newTopicDraftText = ""
                    viewModel.load()
                },
                composerDraftText: $newTopicDraftText,
                isComposerPresented: $isNewTopicComposerPresented
            )
        }
        .sheet(isPresented: $isPagePickerPresented) {
            TopicPagePickerSheet(
                maxPage: max(viewModel.pageInfo.lastPageNumber, 1),
                pageInput: $pagePickerInput
            ) { selectedPage in
                navigateToPage(selectedPage)
            }
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

    @ViewBuilder
    private var accountMenuItems: some View {
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

private struct ForumCategoryIconView: View {
    let forum: Forum
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedImage: UIImage? {
        let resolved = forum.getImage().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else { return nil }
        return UIImage(named: resolved)
    }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(uiImage: resolvedImage.withRenderingMode(.alwaysTemplate))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
            } else {
                Image(systemName: "folder.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

private struct ForumTopicsPaginationBar: View {
    let pageInfo: ForumSearchPageInfo
    let onFirst: () -> Void
    let onPrevious: () -> Void
    let onPagePicker: () -> Void
    let onNext: () -> Void
    let onLast: () -> Void

    private var pageNumber: Int {
        max(pageInfo.pageNumber, 1)
    }

    private var lastPageNumber: Int {
        max(pageInfo.lastPageNumber, 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onFirst) {
                Image(systemName: "backward.end")
            }
            .disabled(pageNumber <= 1 || pageInfo.firstPageURL == nil)

            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .disabled(pageNumber <= 1 || pageInfo.previousPageURL == nil)

            Spacer(minLength: 8)

            Button(action: onPagePicker) {
                Text("\(pageNumber) / \(lastPageNumber)")
                    .font(.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(minWidth: 74)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choisir une page")

            Spacer(minLength: 8)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(pageNumber >= lastPageNumber || pageInfo.nextPageURL == nil)

            Button(action: onLast) {
                Image(systemName: "forward.end")
            }
            .disabled(pageNumber >= lastPageNumber || pageInfo.lastPageURL == nil)
        }
        .hfrGlassButton()
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .hfrGlassSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum CategoriesPreviewFactory {
    final class PreviewForumsLoader: ForumsLoading {
        enum Result {
            case success([Forum])
            case failure(Error)
        }

        private let result: Result
        private let delay: TimeInterval

        init(result: Result, delay: TimeInterval = 0) {
            self.result = result
            self.delay = delay
        }

        func fetchForums(completion: @escaping ForumsLoadCompletion) {
            let work = {
                switch self.result {
                case .success(let forums):
                    completion(forums, nil)
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

    final class PreviewForumTopicsLoader: ForumTopicsLoading {
        enum Result {
            case success([Topic])
            case failure(Error)
        }

        private let result: Result

        init(result: Result) {
            self.result = result
        }

        func fetchTopics(for forum: Forum, flag: TopicListFlag, pageURL: String?, completion: @escaping ForumTopicsLoadCompletion) {
            switch result {
            case .success(let topics):
                let rawPageInfo: NSDictionary = [
                    "currentURL": pageURL ?? "/forum1.php?config=hfr.inc&cat=13&page=2",
                    "nextPageURL": "/forum1.php?config=hfr.inc&cat=13&page=3",
                    "previousPageURL": "/forum1.php?config=hfr.inc&cat=13&page=1",
                    "firstPageURL": "/forum1.php?config=hfr.inc&cat=13&page=1",
                    "lastPageURL": "/forum1.php?config=hfr.inc&cat=13&page=8",
                    "pageNumber": 2,
                    "firstPageNumber": 1,
                    "lastPageNumber": 8,
                    "resultCount": topics.count
                ]
                completion(
                    ForumTopicsLoadResult(
                        topics: topics,
                        newTopicURL: URL(string: "https://forum.hardware.fr/bddpost.php?config=hfr.inc&cat=13&post=0"),
                        pageInfo: ForumSearchPageInfo(raw: rawPageInfo)
                    ),
                    nil
                )
            case .failure(let error):
                completion(nil, error)
            }
        }
    }

    enum PreviewError: Error, LocalizedError {
        case offline

        var errorDescription: String? { "Connexion indisponible" }
    }

    static func forum(title: String, url: String, subForumCount: Int = 0) -> Forum {
        let forum = Forum()
        forum.aTitle = title
        forum.aURL = url
        if subForumCount > 0 {
            let subForums = NSMutableArray()
            for index in 1...subForumCount {
                let sub = Forum()
                sub.aTitle = "\(title) - Sous-forum \(index)"
                sub.aURL = "\(url)?sub=\(index)"
                subForums.add(sub)
            }
            forum.subCats = subForums
        }
        return forum
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

    static let sampleForums: [Forum] = [
        forum(title: "Programmation", url: "https://forum.hardware.fr/hfr/Programmation/liste_sujet-1.htm", subForumCount: 3),
        forum(title: "Hardware", url: "https://forum.hardware.fr/hfr/Hardware/liste_sujet-1.htm")
    ]

    static let sampleTopics: [Topic] = [
        topic(title: "Migration SwiftUI", author: "alice", date: "il y a 1h"),
        topic(title: "ObjC wrappers", author: "bob", date: "il y a 3h", currentPage: 2, maxPage: 10)
    ]
}

private enum RootTabAudit {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HFRswift",
        category: "RootTabAudit"
    )

    static func log(
        _ event: String,
        source: String,
        current: RootTabIdentifier? = nil,
        previous: RootTabIdentifier? = nil,
        target: RootTabIdentifier? = nil,
        runtime: RootTabIdentifier? = nil,
        selectedIndex: Int? = nil,
        uiSelectedIndex: Int? = nil,
        viewControllerCount: Int? = nil,
        mode: String? = nil,
        scenePhase: String? = nil,
        note: String? = nil
    ) {
        var parts = [
            "[RootTabAudit]",
            "t=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime))",
            "event=\(event)",
            "source=\(source)"
        ]

        if let current { parts.append("current=\(current.auditName)") }
        if let previous { parts.append("previous=\(previous.auditName)") }
        if let target { parts.append("target=\(target.auditName)") }
        if let runtime { parts.append("runtime=\(runtime.auditName)") }
        if let selectedIndex { parts.append("selectedIndex=\(indexDescription(selectedIndex))") }
        if let uiSelectedIndex { parts.append("uiSelectedIndex=\(indexDescription(uiSelectedIndex))") }
        if let viewControllerCount { parts.append("vcCount=\(viewControllerCount)") }
        if let mode { parts.append("mode=\(mode)") }
        if let scenePhase { parts.append("scenePhase=\(scenePhase)") }
        if let note { parts.append("note=\(note)") }

        let message = parts.joined(separator: " ")
        logger.notice("\(message, privacy: .public)")
#if DEBUG
        print(message)
#endif
    }

    static func currentTabBarSnapshot() -> (selectedIndex: Int, viewControllerCount: Int)? {
        guard let tabBarController = findTabBarController(in: keyWindowRootViewController()) else {
            return nil
        }
        return (
            selectedIndex: tabBarController.selectedIndex,
            viewControllerCount: tabBarController.viewControllers?.count ?? 0
        )
    }

    private static func indexDescription(_ index: Int) -> String {
        if let tab = RootTabIdentifier(rawValue: index) {
            return "\(index):\(tab.auditName)"
        }
        return "\(index):unknown"
    }

    private static func findTabBarController(in root: UIViewController?) -> UITabBarController? {
        guard let root else { return nil }
        if let tabBarController = root as? UITabBarController {
            return tabBarController
        }
        for child in root.children {
            if let tabBarController = findTabBarController(in: child) {
                return tabBarController
            }
        }
        return root.presentedViewController.flatMap { findTabBarController(in: $0) }
    }

    private static func keyWindowRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }
}

private extension RootTabIdentifier {
    var auditName: String {
        switch self {
        case .categories:
            return "categories"
        case .favorites:
            return "favorites"
        case .messages:
            return "messages"
        case .more:
            return "more"
        }
    }
}

struct RootTabView: View {
    private enum RuntimeState {
        static var selectedTab: RootTabIdentifier?
    }

    private enum IPadSidebarDestination: String, Hashable, CaseIterable {
        case categories
        case favorites
        case messages
        case bookmarks
        case qualityAlerts
        case settings
        case search
        case credits
        case charter
        case deleteAccount

        var rootTab: RootTabIdentifier {
            switch self {
            case .categories:
                .categories
            case .favorites:
                .favorites
            case .messages:
                .messages
            case .bookmarks, .qualityAlerts, .settings, .search, .credits, .charter, .deleteAccount:
                .more
            }
        }

        var usesTopicList: Bool {
            switch self {
            case .categories, .favorites, .messages, .bookmarks, .qualityAlerts:
                true
            case .settings, .search, .credits, .charter, .deleteAccount:
                false
            }
        }
    }

    private enum SidebarVisibilityStorage {
        static let key = "HFRswiftIPadSplitColumnVisibilityV3"
        static let automatic = "automatic"
        static let all = "all"
        static let doubleColumn = "doubleColumn"
        static let detailOnly = "detailOnly"
    }

    @StateObject private var appTheme = AppThemeStore.shared
    @StateObject private var accountsStore = AccountsStore()
    @StateObject private var favoritesViewModel = FavoritesViewModel()
    @StateObject private var messagesViewModel = MPListViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedTab: RootTabIdentifier
    @State private var iPadSidebarDestination: IPadSidebarDestination
    @State private var hasScheduledColdLaunchPrefetch = false
    @State private var coldLaunchPrefetchTask: Task<Void, Never>?
    @State private var hasScheduledAQBadgeCheck = false
    @State private var aqBadgeCheckTask: Task<Void, Never>?
    @State private var messagesNavigationResetToken = UUID()
    /// Navigation identity of each split detail; a new value rebuilds that detail only.
    @State private var detailNavigationResetTokens: [IPadSidebarDestination: UUID] = [:]
    /// Last destination chosen in the Plus tab, shown again when the tab is reselected.
    @State private var lastMoreDestination = IPadSidebarDestination.settings
    @State private var preferredCompactColumn = NavigationSplitViewColumn.content
    @State private var isPortraitLayout = false
    @State private var iPadDirectSidebarVisibility = NavigationSplitViewVisibility.all
    @State private var categoriesSelectedForum: Forum?
    @State private var categoriesInitialFlagOverride: TopicListFlag?
    @State private var categoriesTopicTarget: TopicNavigationTarget?
    @State private var favoritesTopicTarget: TopicNavigationTarget?
    @State private var messagesTopicTarget: TopicNavigationTarget?
    @State private var bookmarksTopicTarget: TopicNavigationTarget?
    @State private var qualityAlertsTopicTarget: TopicNavigationTarget?
    @AppStorage("nb_mp") private var unreadMPCount = 0
    @AppStorage(AQUnreadCounter.storageKey) private var unreadAQCount = 0
    @AppStorage("mp_badge_enabled") private var mpBadgeEnabled = true
    @AppStorage(AppTabBarMinimizeOnScroll.key) private var tabBarMinimizeOnScroll = true
    @AppStorage(SidebarVisibilityStorage.key) private var iPadSidebarVisibilityRawValue = SidebarVisibilityStorage.doubleColumn

    /// Split views inside the tabs (list + topic) whenever the scene is regular in both
    /// dimensions: iPad full screen, and the iPhone Duo inner display (a `.phone` idiom that
    /// reports regular/regular when unfolded, in portrait and in landscape). The cover screen,
    /// regular iPhones and the landscape Pro Max (regular width, compact height) keep push
    /// navigation. The tab bar is there in every case. iPad keeps its existing rule (regular
    /// width only). The name is kept from #372, where this flag chose a sidebar root.
    private var usesSidebarRoot: Bool {
        guard horizontalSizeClass == .regular else { return false }
        return verticalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
    }

    /// iPhone Duo inner display in portrait: too narrow for list + topic side by side, so the
    /// topic goes full width (`detailOnly`) once chosen (decision of 2026-11-01). iPad and the
    /// landscape inner display keep list + topic. The split style stays `.balanced`: switching
    /// style types would rebuild the whole split view (and the topic being read) on rotation.
    private var prefersDetailOnlyTopic: Bool {
        usesSidebarRoot && UIDevice.current.userInterfaceIdiom == .phone && isPortraitLayout
    }

    init() {
        let startupRawValue = UserDefaults.standard.string(forKey: AppStartupScreen.storageKey)
        let runtimeTab = RuntimeState.selectedTab
        let initialTab = runtimeTab ?? AppStartupScreen.rootTab(for: startupRawValue)
        _selectedTab = State(initialValue: initialTab)
        _iPadSidebarDestination = State(initialValue: Self.defaultIPadDestination(for: initialTab))
        RuntimeState.selectedTab = initialTab
        RootTabAudit.log(
            "init",
            source: "RootTabView.init",
            target: initialTab,
            runtime: runtimeTab,
            note: "startup=\(startupRawValue ?? "nil")"
        )
    }

    private static func defaultIPadDestination(for tab: RootTabIdentifier) -> IPadSidebarDestination {
        switch tab {
        case .categories:
            .categories
        case .favorites:
            .favorites
        case .messages:
            .messages
        case .more:
            .settings
        }
    }

    private var rootModeAuditName: String {
        usesSidebarRoot ? "splitTabs" : "tabbar"
    }

    private var tabSelectionBinding: Binding<RootTabIdentifier> {
        Binding {
            selectedTab
        } set: { newValue in
            setSelectedTab(newValue, source: "SwiftUI.TabView.selection")
        }
    }

    private func setSelectedTab(_ tab: RootTabIdentifier, source: String) {
        let previous = selectedTab
        RootTabAudit.log(
            previous == tab ? "selectedTab.noop" : "selectedTab.set",
            source: source,
            current: selectedTab,
            previous: previous,
            target: tab,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName
        )
        if previous != tab {
            selectedTab = tab
            if iPadSidebarDestination.rootTab != tab {
                iPadSidebarDestination = destination(forTab: tab)
            }
            // No detail reset here: each tab keeps its own split detail (HIG Tab bars: switch
            // sections "while preserving the current navigation state within each section").
            preferredCompactColumn = activeTopicTarget == nil ? .content : .detail
            // The four splits share one column visibility: re-derive it for the tab shown.
            if usesSidebarRoot, iPadSidebarDestination.usesTopicList {
                applyListVisibility(for: iPadSidebarDestination)
            }
        }
        syncRuntimeSelectedTab(tab, source: "\(source).runtime")
    }

    private func syncRuntimeSelectedTab(_ tab: RootTabIdentifier, source: String) {
        let previous = RuntimeState.selectedTab
        guard previous != tab else { return }
        RuntimeState.selectedTab = tab
        RootTabAudit.log(
            "runtimeSelectedTab.set",
            source: source,
            previous: previous,
            target: tab,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName
        )
    }

    private var iPadSidebarColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            Self.sidebarVisibility(from: iPadSidebarVisibilityRawValue)
        } set: { newValue in
            let requestedRawValue = Self.rawValue(for: newValue)
            RootTabAudit.log(
                "splitVisibility.bindingSet",
                source: "NavigationSplitView.columnVisibility",
                current: selectedTab,
                runtime: RuntimeState.selectedTab,
                mode: rootModeAuditName,
                scenePhase: String(describing: scenePhase),
                note: splitVisibilityAuditNote(
                    extra: "previousStored=\(iPadSidebarVisibilityRawValue) requested=\(requestedRawValue)"
                )
            )
            iPadSidebarVisibilityRawValue = requestedRawValue
        }
    }

    private func splitVisibilityAuditNote(extra: String? = nil) -> String {
        var parts = [
            "stored=\(iPadSidebarVisibilityRawValue)",
            "sizeClass=\(Self.sizeClassAuditName(horizontalSizeClass))",
            "usesSidebarRoot=\(usesSidebarRoot)",
            "preferredCompact=\(String(describing: preferredCompactColumn))",
            "destination=\(iPadSidebarDestination.rawValue)",
            "activeTopic=\(activeTopicTarget != nil)"
        ]
        if let extra {
            parts.append(extra)
        }
        return parts.joined(separator: " ")
    }

    private static func sizeClassAuditName(_ sizeClass: UserInterfaceSizeClass?) -> String {
        switch sizeClass {
        case .compact:
            return "compact"
        case .regular:
            return "regular"
        case nil:
            return "nil"
        @unknown default:
            return "unknown"
        }
    }

    private static func sidebarVisibility(from rawValue: String) -> NavigationSplitViewVisibility {
        switch rawValue {
        case SidebarVisibilityStorage.all:
            return .all
        case SidebarVisibilityStorage.doubleColumn:
            return .doubleColumn
        case SidebarVisibilityStorage.detailOnly:
            return .detailOnly
        case SidebarVisibilityStorage.automatic:
            fallthrough
        default:
            return .automatic
        }
    }

    private static func rawValue(for visibility: NavigationSplitViewVisibility) -> String {
        if visibility == .all {
            return SidebarVisibilityStorage.all
        } else if visibility == .doubleColumn {
            return SidebarVisibilityStorage.doubleColumn
        } else if visibility == .detailOnly {
            return SidebarVisibilityStorage.detailOnly
        } else {
            return SidebarVisibilityStorage.automatic
        }
    }

    private func syncAppIconBadge() async {
        let count = (mpBadgeEnabled && unreadMPCount > 0) ? unreadMPCount : 0
        await MPBackgroundService.shared.updateAppIconBadge(count: count)
    }

    private func startColdLaunchPrefetchIfNeeded() {
        guard !hasScheduledColdLaunchPrefetch else { return }
        guard accountsStore.currentAccount != nil else { return }

        hasScheduledColdLaunchPrefetch = true
        favoritesViewModel.ensureLoaded()

        coldLaunchPrefetchTask?.cancel()
        coldLaunchPrefetchTask = Task { @MainActor in
            while favoritesViewModel.isLoading {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled, accountsStore.currentAccount != nil else { return }
            messagesViewModel.ensureLoaded()
        }
    }

    private func cancelColdLaunchPrefetch() {
        coldLaunchPrefetchTask?.cancel()
        coldLaunchPrefetchTask = nil
    }

    private func startAQBadgeCheckIfNeeded() {
        guard !hasScheduledAQBadgeCheck else { return }
        hasScheduledAQBadgeCheck = true

        aqBadgeCheckTask?.cancel()
        aqBadgeCheckTask = Task {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await AQBadgeCheckService.shared.refreshUnreadCount()
        }
    }

    private func handleUIKitTabSelection(_ selectedIndex: Int) {
        guard let tab = RootTabIdentifier(rawValue: selectedIndex) else { return }
        RootTabAudit.log(
            "UIKit.didSelect",
            source: "TabBarReselectionObserver",
            current: selectedTab,
            target: tab,
            runtime: RuntimeState.selectedTab,
            selectedIndex: selectedIndex,
            mode: rootModeAuditName
        )
        setSelectedTab(tab, source: "UIKit.didSelect")
    }

    private func showMessagesList(forceRefresh: Bool) {
        RootTabAudit.log(
            "showMessagesList",
            source: "MessagesNotificationNavigation",
            current: selectedTab,
            target: .messages,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName,
            note: "forceRefresh=\(forceRefresh)"
        )
        messagesNavigationResetToken = UUID()
        messagesTopicTarget = nil
        resetDetailNavigation(for: .messages)
        preferredCompactColumn = .content
        if usesSidebarRoot || UIDevice.current.userInterfaceIdiom == .pad {
            iPadSidebarVisibilityRawValue = SidebarVisibilityStorage.doubleColumn
            setIPadSidebarDestination(.messages, source: "showMessagesList")
        } else {
            setSelectedTab(.messages, source: "showMessagesList")
        }

        guard accountsStore.currentAccount != nil else { return }
        if forceRefresh {
            messagesViewModel.load()
        } else {
            messagesViewModel.ensureLoaded()
        }
    }

    private func handlePendingMessagesNotificationNavigationIfNeeded(forceRefresh: Bool = true) {
        guard MessagesNotificationNavigation.consumePendingOpenMessagesRequest() else { return }
        RootTabAudit.log(
            "pendingMessagesNotification.consume",
            source: "MessagesNotificationNavigation",
            current: selectedTab,
            target: .messages,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName,
            note: "forceRefresh=\(forceRefresh)"
        )
        showMessagesList(forceRefresh: forceRefresh)
    }

    var body: some View {
        rootContainer
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.height > proxy.size.width
            } action: { isPortrait in
                isPortraitLayout = isPortrait
            }
            .environment(\.hfrIsExpandedPhoneRoot, usesSidebarRoot && UIDevice.current.userInterfaceIdiom == .phone)
            .preferredColorScheme(appTheme.preferredColorScheme)
            .tint(appTheme.actionTintColor)
            .environment(\.appThemePalette, appTheme.palette)
            .onAppear(perform: handleAppear)
            .onChange(of: selectedTab) { oldValue, newValue in
                RootTabAudit.log(
                    "selectedTab.observed",
                    source: "SwiftUI.onChange",
                    previous: oldValue,
                    target: newValue,
                    runtime: RuntimeState.selectedTab,
                    mode: rootModeAuditName
                )
                syncRuntimeSelectedTab(newValue, source: "SwiftUI.onChange")
            }
            .onChange(of: accountsStore.currentAccount?.id) { oldValue, newValue in
                handleCurrentAccountChange(from: oldValue, to: newValue)
            }
            .onChange(of: systemColorScheme) { _, newValue in
                appTheme.refresh(systemColorScheme: newValue, notifyLegacy: true)
            }
            .onChange(of: horizontalSizeClass) { oldValue, newValue in
                RootTabAudit.log(
                    "splitVisibility.sizeClassChanged",
                    source: "SwiftUI.horizontalSizeClass",
                    current: selectedTab,
                    runtime: RuntimeState.selectedTab,
                    mode: rootModeAuditName,
                    scenePhase: String(describing: scenePhase),
                    note: splitVisibilityAuditNote(
                        extra: "previousSizeClass=\(Self.sizeClassAuditName(oldValue)) newSizeClass=\(Self.sizeClassAuditName(newValue))"
                    )
                )
                ensureVisibleIPadListIfNeeded()
            }
            .onChange(of: verticalSizeClass) { oldValue, newValue in
                // iPhone Duo and large iPhones: rotation or fold can flip only the height class,
                // which also switches the tab contents between push navigation and split views.
                RootTabAudit.log(
                    "splitVisibility.verticalSizeClassChanged",
                    source: "SwiftUI.verticalSizeClass",
                    current: selectedTab,
                    runtime: RuntimeState.selectedTab,
                    mode: rootModeAuditName,
                    scenePhase: String(describing: scenePhase),
                    note: splitVisibilityAuditNote(
                        extra: "previousVerticalSizeClass=\(Self.sizeClassAuditName(oldValue)) newVerticalSizeClass=\(Self.sizeClassAuditName(newValue))"
                    )
                )
                ensureVisibleIPadListIfNeeded()
                // Fold/unfold: re-apply the phone orientation locks (rotation setting, composer).
                HFRSwiftOrientationPolicy.refreshSupportedOrientations()
            }
            .onChange(of: usesSidebarRoot) { _, newValue in
                handleRootSwap(toSidebar: newValue)
            }
            .onChange(of: activeTopicTarget?.id) {
                // Any path that clears the topic shown (deletion of the MP or bookmark, account
                // change, forum change) must not leave an empty detail with the list hidden.
                ensureVisibleIPadListIfNeeded()
            }
            .onChange(of: prefersDetailOnlyTopic) { _, detailOnly in
                // Unfolded Duo rotation with a topic open: full-width topic in portrait,
                // list + topic again in landscape.
                guard usesSidebarRoot, activeTopicTarget != nil else { return }
                iPadSidebarVisibilityRawValue = detailOnly
                    ? SidebarVisibilityStorage.detailOnly
                    : SidebarVisibilityStorage.doubleColumn
            }
            .onChange(of: iPadSidebarVisibilityRawValue) { oldValue, newValue in
                RootTabAudit.log(
                    "splitVisibility.storedChanged",
                    source: "AppStorage.onChange",
                    current: selectedTab,
                    runtime: RuntimeState.selectedTab,
                    mode: rootModeAuditName,
                    scenePhase: String(describing: scenePhase),
                    note: splitVisibilityAuditNote(
                        extra: "previousStored=\(oldValue) newStored=\(newValue)"
                    )
                )
            }
            .onChange(of: scenePhase) { _, newValue in
                handleScenePhaseChange(newValue)
            }
            .onChange(of: unreadMPCount) { _, _ in
                Task { await syncAppIconBadge() }
            }
            .onChange(of: mpBadgeEnabled) { _, _ in
                Task { await syncAppIconBadge() }
            }
            .background(tabBarReselectionObserver)
            .onReceive(NotificationCenter.default.publisher(for: MessagesNotificationNavigation.openMessagesNotification)) { _ in
                handlePendingMessagesNotificationNavigationIfNeeded()
            }
    }

    /// One `TabView` for every size class, so the sections stay in the tab bar folded and
    /// unfolded (HIG Sidebars: "Consider using a tab bar first"; HIG iPhone Duo: "Keep controls
    /// consistent across device poses"). Same 4 tabs, same order and indexes as before: the
    /// UIKit observer of HFR-092 keeps working. Only the content of each tab changes with the
    /// size class: push navigation in compact, a split view (list + topic) in regular/regular.
    private var rootContainer: some View {
        rootTabs
            .hfrTabBarMinimizeBehavior(tabBarMinimizeOnScroll: tabBarMinimizeOnScroll)
    }

    private var rootTabs: some View {
        TabView(selection: tabSelectionBinding) {
            Group {
                if usesSidebarRoot {
                    listTabSplit(for: .categories)
                } else {
                    CategoriesListView(accountsStore: accountsStore)
                }
            }
            .environment(\.foldHandoffScope, FoldHandoffScope(tab: .categories, isCompactRoot: !usesSidebarRoot))
            .onAppear { auditTabContentAppear(.categories, source: "TabView.categories") }
            .tabItem { Label("Catégories", systemImage: "folder.fill") }
            .tag(RootTabIdentifier.categories)

            Group {
                if usesSidebarRoot {
                    listTabSplit(for: .favorites)
                } else {
                    FavoritesListView(
                        viewModel: favoritesViewModel,
                        accountsStore: accountsStore
                    )
                }
            }
            .environment(\.foldHandoffScope, FoldHandoffScope(tab: .favorites, isCompactRoot: !usesSidebarRoot))
            .onAppear { auditTabContentAppear(.favorites, source: "TabView.favorites") }
            .tabItem { Label("Favoris", systemImage: "star.fill") }
            .tag(RootTabIdentifier.favorites)

            Group {
                if usesSidebarRoot {
                    listTabSplit(for: .messages)
                } else {
                    MPListView(
                        viewModel: messagesViewModel,
                        accountsStore: accountsStore,
                        isActive: selectedTab == .messages,
                        navigationResetToken: messagesNavigationResetToken
                    )
                }
            }
            .environment(\.foldHandoffScope, FoldHandoffScope(tab: .messages, isCompactRoot: !usesSidebarRoot))
            .onAppear { auditTabContentAppear(.messages, source: "TabView.messages") }
            .tabItem { Label("Messages", systemImage: "envelope") }
            .tag(RootTabIdentifier.messages)
            .badge(mpBadgeEnabled && unreadMPCount > 0 ? unreadMPCount : 0)

            Group {
                if usesSidebarRoot {
                    moreTabSplit
                } else {
                    NavigationStack {
                        PlusHomeView()
                            .foldHandoffDestination()
                    }
                }
            }
            .environment(\.foldHandoffScope, FoldHandoffScope(tab: .more, isCompactRoot: !usesSidebarRoot))
            .onAppear { auditTabContentAppear(.more, source: "TabView.more") }
            .tabItem { Label("Plus", systemImage: "ellipsis") }
            .tag(RootTabIdentifier.more)
            .badge(unreadAQCount > 0 ? unreadAQCount : 0)
        }
    }

    /// Catégories, Favoris and Messages in regular/regular: list and topic side by side inside
    /// the tab (HIG iPhone Duo: Mail "shows both side by side" when open). The system sidebar
    /// toggle of this two-column split hides or shows the list.
    private func listTabSplit(for destination: IPadSidebarDestination) -> some View {
        NavigationSplitView(columnVisibility: iPadSidebarColumnVisibility) {
            iPadListContent(for: destination)
                .expandedPhoneInlineNavigationTitle()
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
        } detail: {
            iPadDetail(for: destination)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The Plus tab in regular/regular keeps a sidebar of its own destinations (HIG Sidebars:
    /// "consider using a sidebar within a tab"): Bookmarks / Alertes Qualitay with list + topic,
    /// the other destinations in two columns. Selecting a row never changes the selected tab.
    @ViewBuilder
    private var moreTabSplit: some View {
        let destination = moreTabDestination
        if destination.usesTopicList {
            NavigationSplitView(
                columnVisibility: iPadSidebarColumnVisibility,
                preferredCompactColumn: $preferredCompactColumn
            ) {
                iPadSidebarNavigationList
            } content: {
                iPadListContent(for: destination)
                    .expandedPhoneInlineNavigationTitle()
                    .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
            } detail: {
                iPadDetail(for: destination)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationSplitView(
                columnVisibility: $iPadDirectSidebarVisibility,
                preferredCompactColumn: $preferredCompactColumn
            ) {
                iPadSidebarNavigationList
            } detail: {
                iPadDetail(for: destination)
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    /// Destination shown by the Plus tab: the current one when the Plus tab is selected,
    /// otherwise the last one chosen there.
    private var moreTabDestination: IPadSidebarDestination {
        iPadSidebarDestination.rootTab == .more ? iPadSidebarDestination : lastMoreDestination
    }

    private var iPadSidebarNavigationList: some View {
        List(selection: iPadSidebarSelection) {
            Section("Outils") {
                ForEach(Self.toolsSidebarDestinations, id: \.self) { destination in
                    NavigationLink(value: destination) {
                        iPadSidebarRow(for: destination)
                    }
                }
            }
            Section("Plus") {
                ForEach(Self.moreSidebarDestinations, id: \.self) { destination in
                    NavigationLink(value: destination) {
                        iPadSidebarRow(for: destination)
                    }
                }
            }
        }
        .navigationTitle("Plus")
        .expandedPhoneInlineNavigationTitle()
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .toolbar {
            // Informational pages only: they stay one tap away without taking sidebar rows.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(Self.infoMenuDestinations, id: \.self) { destination in
                        Button(
                            iPadSidebarTitle(for: destination),
                            systemImage: iPadSidebarSystemImage(for: destination)
                        ) {
                            setIPadSidebarDestination(destination, source: "PlusInfoMenu")
                        }
                    }
                } label: {
                    Label("Informations", systemImage: "ellipsis")
                }
            }
        }
    }

    private var iPadSidebarSelection: Binding<IPadSidebarDestination?> {
        Binding {
            moreTabDestination
        } set: { newValue in
            guard let newValue else {
                RootTabAudit.log(
                    "sidebarSelection.nilIgnored",
                    source: "NavigationSplitView.sidebarSelection",
                    current: selectedTab,
                    runtime: RuntimeState.selectedTab,
                    mode: rootModeAuditName
                )
                return
            }
            setIPadSidebarDestination(
                newValue,
                source: "NavigationSplitView.sidebarSelection"
            )
        }
    }

    @ViewBuilder
    private func iPadListContent(for destination: IPadSidebarDestination) -> some View {
        switch destination {
        case .categories:
            if let categoriesSelectedForum {
                ForumTopicsListView(
                    forum: categoriesSelectedForum,
                    initialFlagOverride: categoriesInitialFlagOverride,
                    accountsStore: accountsStore,
                    selectedTopicID: categoriesTopicTarget?.id,
                    onSelectTopic: { selectTopic($0, for: .categories) },
                    onBack: showCategoriesRoot,
                    onContentContextChange: clearCategoriesTopicSelection
                )
                .id(iPadForumIdentity(for: categoriesSelectedForum))
                .onAppear { auditTabContentAppear(.categories, source: "Split.categories.topics") }
            } else {
                CategoriesListView(
                    accountsStore: accountsStore,
                    selectedTopicID: categoriesTopicTarget?.id,
                    onSelectTopic: { selectTopic($0, for: .categories) },
                    onSelectForum: {
                        showTopicsForForum($0, initialFlagOverride: nil)
                    }
                )
                .onAppear { auditTabContentAppear(.categories, source: "Split.categories") }
            }
        case .favorites:
            FavoritesListView(
                viewModel: favoritesViewModel,
                accountsStore: accountsStore,
                selectedTopicID: favoritesTopicTarget?.id,
                onSelectTopic: { selectTopic($0, for: .favorites) },
                onOpenForum: {
                    showTopicsForForum($0, initialFlagOverride: .favorites)
                }
            )
            .onAppear { auditTabContentAppear(.favorites, source: "Split.favorites") }
        case .messages:
            MPListView(
                viewModel: messagesViewModel,
                accountsStore: accountsStore,
                isActive: selectedTab == .messages,
                navigationResetToken: messagesNavigationResetToken,
                selectedTopicID: messagesTopicTarget?.id,
                onSelectTopic: { selectTopic($0, for: .messages) },
                onDeleteTopic: handleDeletedMessageTopic
            )
            .onAppear { auditTabContentAppear(.messages, source: "Split.messages") }
        case .bookmarks:
            BookmarksPlusView(
                selectedTopicID: bookmarksTopicTarget?.id,
                onSelectTopic: { selectTopic($0, for: .bookmarks) },
                onDeleteTopic: handleDeletedBookmarkTopic
            )
            .onAppear { auditTabContentAppear(.more, source: "Split.bookmarks") }
        case .qualityAlerts:
            AQPlusView(
                selectedTopicID: qualityAlertsTopicTarget?.id,
                onSelectTopic: { selectTopic($0, for: .qualityAlerts) }
            )
            .onAppear { auditTabContentAppear(.more, source: "Split.qualityAlerts") }
        case .settings, .search, .credits, .charter, .deleteAccount:
            EmptyView()
        }
    }

    /// Detail column of a split. Each destination keeps its own navigation identity, so
    /// switching tabs keeps the topic and the links opened from it in every other tab.
    private func iPadDetail(for destination: IPadSidebarDestination) -> some View {
        NavigationStack {
            if let target = topicTarget(for: destination) {
                MessagesView(
                    topic: target.topic,
                    curPage: target.page,
                    maxPage: target.maxPage,
                    separatorNewMessages: target.separatorNewMessages,
                    initialLoadScroll: target.initialScroll,
                    initialFavoritePostFilterResult: target.initialFavoritePostFilterResult,
                    resetMessagesStackToRootAction: { resetDetailNavigation(for: destination) }
                )
            } else {
                switch destination {
                case .settings:
                    AppSettingsView()
                case .search:
                    ForumSearchView()
                case .credits:
                    StaticInfoPageView(kind: .credits)
                case .charter:
                    StaticInfoPageView(kind: .charter)
                case .deleteAccount:
                    AccountDeletionView()
                case .categories, .favorites, .messages, .bookmarks, .qualityAlerts:
                    ContentUnavailableView {
                        Label(
                            detailPlaceholderTitle(for: destination),
                            systemImage: detailPlaceholderSystemImage(for: destination)
                        )
                    } description: {
                        Text(detailPlaceholderDescription(for: destination))
                    }
                }
            }
        }
        .id(detailNavigationResetTokens[destination])
        .toolbar {
            // Three-column split of the Plus tab only: there the system toggle opens the Plus
            // sidebar, so hiding the list needs its own button. The two-column splits of the
            // other tabs use the system toggle, which already hides or shows the list.
            if destination.rootTab == .more,
               destination.usesTopicList,
               topicTarget(for: destination) != nil,
               !isTopicListHidden {
                ToolbarItem(placement: .topBarLeading) {
                    // Not a sidebar symbol: the system sidebar toggle of the list column opens
                    // the sidebar, this one gives the topic the full width.
                    Button(
                        "Masquer la liste",
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        action: toggleTopicListVisibility
                    )
                }
            }
        }
    }

    private func detailPlaceholderTitle(for destination: IPadSidebarDestination) -> String {
        switch destination {
        case .bookmarks:
            "Aucun bookmark sélectionné"
        case .qualityAlerts:
            "Aucune alerte sélectionnée"
        case .categories, .favorites, .messages:
            "Aucun topic sélectionné"
        case .settings, .search, .credits, .charter, .deleteAccount:
            ""
        }
    }

    private func detailPlaceholderSystemImage(for destination: IPadSidebarDestination) -> String {
        switch destination {
        case .bookmarks:
            "pin"
        case .qualityAlerts:
            "bell"
        case .categories, .favorites, .messages:
            "text.bubble"
        case .settings, .search, .credits, .charter, .deleteAccount:
            "doc"
        }
    }

    private func detailPlaceholderDescription(for destination: IPadSidebarDestination) -> String {
        switch destination {
        case .categories:
            categoriesSelectedForum == nil
                ? "Choisissez une catégorie dans la liste."
                : "Choisissez un topic dans la liste."
        case .favorites:
            "Choisissez un favori dans la liste."
        case .messages:
            "Choisissez une conversation dans la liste."
        case .bookmarks:
            "Choisissez un bookmark dans la liste."
        case .qualityAlerts:
            "Choisissez une alerte dans la liste."
        case .settings, .search, .credits, .charter, .deleteAccount:
            ""
        }
    }

    /// Topic shown by the selected tab's split (or the current Plus destination).
    private var activeTopicTarget: TopicNavigationTarget? {
        topicTarget(for: iPadSidebarDestination)
    }

    private func topicTarget(for destination: IPadSidebarDestination) -> TopicNavigationTarget? {
        switch destination {
        case .categories:
            categoriesTopicTarget
        case .favorites:
            favoritesTopicTarget
        case .messages:
            messagesTopicTarget
        case .bookmarks:
            bookmarksTopicTarget
        case .qualityAlerts:
            qualityAlertsTopicTarget
        case .settings, .search, .credits, .charter, .deleteAccount:
            nil
        }
    }

    private var isTopicListHidden: Bool {
        Self.sidebarVisibility(from: iPadSidebarVisibilityRawValue) == .detailOnly
    }

    private func setIPadSidebarDestination(
        _ destination: IPadSidebarDestination,
        source: String
    ) {
        let previousDestination = iPadSidebarDestination
        guard previousDestination != destination else {
            setSelectedTab(destination.rootTab, source: source)
            return
        }

        iPadSidebarDestination = destination
        if destination.rootTab == .more {
            lastMoreDestination = destination
        }
        setSelectedTab(destination.rootTab, source: source)
        resetDetailNavigation(for: destination)

        if destination.usesTopicList {
            applyListVisibility(for: destination)
            preferredCompactColumn = activeTopicTarget == nil ? .content : .detail
        } else {
            iPadDirectSidebarVisibility = .all
            preferredCompactColumn = .detail
        }
    }

    /// Fold/unfold (or iPad Split View resize) swaps each tab's content between push navigation
    /// and a split view; the tab bar itself stays. Replays the topic being read in the selected
    /// tab into the new content, on the same page. Only the root topic of the selected tab is
    /// carried; the Plus tab is carried only towards Bookmarks / Alertes Qualitay when one of
    /// them is the Plus tab's current destination.
    private func handleRootSwap(toSidebar: Bool) {
        let reading = FoldHandoffStore.shared.beginRootSwap(selectedTab: selectedTab)
        let readingNote = reading.map { "page \($0.page)/\($0.maxPage)" } ?? "nil"
        RootTabAudit.log(
            "foldHandoff.rootSwap",
            source: "RootTabView.usesSidebarRoot",
            current: selectedTab,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName,
            note: "toSidebar=\(toSidebar) reading=\(readingNote)"
        )

        if toSidebar {
            guard let reading else {
                // Nothing open on the cover screen: no older split selection may come back.
                clearAllTopicTargets()
                return
            }
            let destination: IPadSidebarDestination
            if iPadSidebarDestination.rootTab == reading.tab {
                destination = iPadSidebarDestination
            } else {
                destination = self.destination(forTab: reading.tab)
            }
            guard destination.usesTopicList else { return }
            if destination != iPadSidebarDestination {
                setIPadSidebarDestination(destination, source: "foldHandoff")
            }
            selectTopic(reading.navigationTarget, for: destination)
        } else {
            // The split selection must not outlive the fold: if the user closes the topic on the
            // cover screen, unfolding must not bring it back.
            let target = reading?.navigationTarget ?? activeTopicTarget
            clearAllTopicTargets()
            if let target {
                FoldHandoffStore.shared.requestCompactPush(tab: selectedTab, target: target)
            }
        }
    }

    /// The compact root keeps no split selection, so after a swap every destination starts
    /// empty; only the topic carried by `FoldHandoffStore` is restored.
    private func clearAllTopicTargets() {
        categoriesTopicTarget = nil
        favoritesTopicTarget = nil
        messagesTopicTarget = nil
        bookmarksTopicTarget = nil
        qualityAlertsTopicTarget = nil
        resetAllDetailNavigation()
    }

    private func selectTopic(
        _ target: TopicNavigationTarget,
        for destination: IPadSidebarDestination
    ) {
        switch destination {
        case .categories:
            categoriesTopicTarget = target
        case .favorites:
            favoritesTopicTarget = target
        case .messages:
            messagesTopicTarget = target
        case .bookmarks:
            bookmarksTopicTarget = target
        case .qualityAlerts:
            qualityAlertsTopicTarget = target
        case .settings, .search, .credits, .charter, .deleteAccount:
            return
        }
        resetDetailNavigation(for: destination)
        preferredCompactColumn = .detail
        if prefersDetailOnlyTopic {
            iPadSidebarVisibilityRawValue = SidebarVisibilityStorage.detailOnly
        }
    }

    private func showTopicsForForum(
        _ forum: Forum,
        initialFlagOverride: TopicListFlag?
    ) {
        categoriesSelectedForum = forum
        categoriesInitialFlagOverride = initialFlagOverride
        categoriesTopicTarget = nil
        setIPadSidebarDestination(.categories, source: "showTopicsForForum")
        iPadSidebarVisibilityRawValue = SidebarVisibilityStorage.doubleColumn
        preferredCompactColumn = .content
        resetDetailNavigation(for: .categories)
    }

    private func showCategoriesRoot() {
        categoriesSelectedForum = nil
        categoriesInitialFlagOverride = nil
        clearCategoriesTopicSelection()
        iPadSidebarVisibilityRawValue = SidebarVisibilityStorage.doubleColumn
        preferredCompactColumn = .content
    }

    private func clearCategoriesTopicSelection() {
        categoriesTopicTarget = nil
        resetDetailNavigation(for: .categories)
        if iPadSidebarDestination == .categories {
            preferredCompactColumn = .content
        }
    }

    private func iPadForumIdentity(for forum: Forum) -> String {
        let forumIdentity = forum.aURL ?? forum.aID ?? forum.aTitle ?? "forum-root"
        let flagIdentity = categoriesInitialFlagOverride
            .map { String($0.rawValue) }
            ?? "default"
        return "\(forumIdentity):\(flagIdentity)"
    }

    private func handleDeletedMessageTopic(_ deletedTopicID: TopicNavigationID) {
        guard messagesTopicTarget?.id == deletedTopicID else { return }
        messagesTopicTarget = nil
        resetDetailNavigation(for: .messages)
        if iPadSidebarDestination == .messages {
            preferredCompactColumn = .content
        }
    }

    private func handleDeletedBookmarkTopic(_ deletedTopicID: TopicNavigationID) {
        guard bookmarksTopicTarget?.id == deletedTopicID else { return }
        bookmarksTopicTarget = nil
        resetDetailNavigation(for: .bookmarks)
        if iPadSidebarDestination == .bookmarks {
            preferredCompactColumn = .content
        }
    }

    private func toggleTopicListVisibility() {
        iPadSidebarVisibilityRawValue = isTopicListHidden
            ? SidebarVisibilityStorage.doubleColumn
            : SidebarVisibilityStorage.detailOnly
    }

    private func ensureVisibleIPadListIfNeeded() {
        guard usesSidebarRoot,
              iPadSidebarDestination.usesTopicList,
              activeTopicTarget == nil,
              isTopicListHidden else {
            return
        }
        iPadSidebarVisibilityRawValue = SidebarVisibilityStorage.doubleColumn
        preferredCompactColumn = .content
    }

    private func resetDetailNavigation(for destination: IPadSidebarDestination) {
        detailNavigationResetTokens[destination] = UUID()
    }

    private func resetAllDetailNavigation() {
        detailNavigationResetTokens = Dictionary(
            uniqueKeysWithValues: IPadSidebarDestination.allCases.map { ($0, UUID()) }
        )
    }

    /// Duo portrait: a destination that holds a topic shows it at full width (decision of
    /// 2026-11-01); otherwise list + topic. Used whenever the shown list destination changes.
    private func applyListVisibility(for destination: IPadSidebarDestination) {
        iPadSidebarVisibilityRawValue = prefersDetailOnlyTopic && topicTarget(for: destination) != nil
            ? SidebarVisibilityStorage.detailOnly
            : SidebarVisibilityStorage.doubleColumn
    }

    /// Destination a tab shows in regular/regular; the Plus tab returns to its last choice.
    private func destination(forTab tab: RootTabIdentifier) -> IPadSidebarDestination {
        tab == .more ? lastMoreDestination : Self.defaultIPadDestination(for: tab)
    }

    private func auditTabContentAppear(_ tab: RootTabIdentifier, source: String) {
        let tabBarSnapshot = RootTabAudit.currentTabBarSnapshot()
        RootTabAudit.log(
            "tabContent.onAppear",
            source: source,
            current: selectedTab,
            target: tab,
            runtime: RuntimeState.selectedTab,
            uiSelectedIndex: tabBarSnapshot?.selectedIndex,
            viewControllerCount: tabBarSnapshot?.viewControllerCount,
            mode: rootModeAuditName
        )
        reconcileVisibleTabSelectionIfNeeded(
            appearedTab: tab,
            source: source,
            tabBarSnapshot: tabBarSnapshot
        )
    }

    private func reconcileVisibleTabSelectionIfNeeded(
        appearedTab: RootTabIdentifier,
        source: String,
        tabBarSnapshot: (selectedIndex: Int, viewControllerCount: Int)?
    ) {
        guard #available(iOS 27.0, *) else { return }
        // The regular/regular root is the same TabView now, so the HFR-092 resync applies to it too.
        guard appearedTab != selectedTab else { return }

        guard let tabBarSnapshot else {
            RootTabAudit.log(
                "visibleTab.reconcileSkipped",
                source: source,
                current: selectedTab,
                target: appearedTab,
                runtime: RuntimeState.selectedTab,
                mode: rootModeAuditName,
                note: "noUITabBarSnapshot"
            )
            return
        }

        guard tabBarSnapshot.selectedIndex == appearedTab.rawValue else {
            RootTabAudit.log(
                "visibleTab.reconcileSkipped",
                source: source,
                current: selectedTab,
                target: appearedTab,
                runtime: RuntimeState.selectedTab,
                uiSelectedIndex: tabBarSnapshot.selectedIndex,
                viewControllerCount: tabBarSnapshot.viewControllerCount,
                mode: rootModeAuditName,
                note: "uiSelectedIndexMismatch"
            )
            return
        }

        RootTabAudit.log(
            "visibleTab.reconcile",
            source: source,
            current: selectedTab,
            target: appearedTab,
            runtime: RuntimeState.selectedTab,
            uiSelectedIndex: tabBarSnapshot.selectedIndex,
            viewControllerCount: tabBarSnapshot.viewControllerCount,
            mode: rootModeAuditName
        )
        setSelectedTab(appearedTab, source: "\(source).visibleTabReconcile")
    }

    private func iPadSidebarRow(for destination: IPadSidebarDestination) -> some View {
        HStack {
            Label(
                iPadSidebarTitle(for: destination),
                systemImage: iPadSidebarSystemImage(for: destination)
            )
            .foregroundStyle(destination == .deleteAccount ? Color.red : Color.primary)
            Spacer()
            if iPadSidebarBadgeCount(for: destination) > 0 {
                Text("\(iPadSidebarBadgeCount(for: destination))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }
        }
    }

    private static let toolsSidebarDestinations: [IPadSidebarDestination] = [
        .bookmarks,
        .qualityAlerts
    ]

    private static let moreSidebarDestinations: [IPadSidebarDestination] = [
        .settings,
        .search,
        .deleteAccount
    ]

    /// Purely informational pages, in the « … » menu of the Plus sidebar instead of rows.
    private static let infoMenuDestinations: [IPadSidebarDestination] = [
        .credits,
        .charter
    ]

    private func iPadSidebarTitle(for destination: IPadSidebarDestination) -> String {
        switch destination {
        case .categories: "Catégories"
        case .favorites: "Favoris"
        case .messages: "Messages"
        case .bookmarks: "Bookmarks"
        case .qualityAlerts: "Alertes Qualitay"
        case .settings: "Réglages"
        case .search: "Rechercher sur le forum"
        case .credits: "Crédits"
        case .charter: "Charte du forum"
        case .deleteAccount: "Supprimer mon compte"
        }
    }

    private func iPadSidebarSystemImage(for destination: IPadSidebarDestination) -> String {
        switch destination {
        case .categories: "folder.fill"
        case .favorites: "star.fill"
        case .messages: "envelope"
        case .bookmarks: "pin"
        case .qualityAlerts: "bell"
        case .settings: "gearshape"
        case .search: "magnifyingglass"
        case .credits: "info.circle"
        case .charter: "doc.text"
        case .deleteAccount: "trash"
        }
    }

    private func iPadSidebarBadgeCount(for destination: IPadSidebarDestination) -> Int {
        switch destination {
        case .messages:
            mpBadgeEnabled ? unreadMPCount : 0
        case .qualityAlerts:
            unreadAQCount
        case .categories, .favorites, .bookmarks, .settings, .search, .credits, .charter, .deleteAccount:
            0
        }
    }

    private var tabBarReselectionObserver: some View {
        TabBarReselectionObserver(
            onSelect: handleUIKitTabSelection
        ) { selectedIndex in
            handleUIKitTabReselection(selectedIndex)
        }
        .frame(width: 0, height: 0)
    }

    private func handleUIKitTabReselection(_ selectedIndex: Int) {
        guard let tab = RootTabIdentifier(rawValue: selectedIndex) else {
            RootTabAudit.log(
                "UIKit.reselect.unknownIndex",
                source: "TabBarReselectionObserver",
                current: selectedTab,
                runtime: RuntimeState.selectedTab,
                selectedIndex: selectedIndex,
                mode: rootModeAuditName
            )
            return
        }

        RootTabAudit.log(
            "UIKit.reselect",
            source: "TabBarReselectionObserver",
            current: selectedTab,
            target: tab,
            runtime: RuntimeState.selectedTab,
            selectedIndex: selectedIndex,
            mode: rootModeAuditName
        )

        guard tab == .categories || tab == .favorites || tab == .messages else {
            return
        }

        RootTabAudit.log(
            "rootTabReselected.post",
            source: "UIKit.reselect",
            current: selectedTab,
            target: tab,
            runtime: RuntimeState.selectedTab,
            selectedIndex: selectedIndex,
            mode: rootModeAuditName
        )
        NotificationCenter.default.post(
            name: .rootTabReselected,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )
    }

    private func handleAppear() {
        RootTabAudit.log(
            "root.onAppear",
            source: "RootTabView",
            current: selectedTab,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName
        )
        RootTabAudit.log(
            "splitVisibility.rootAppear",
            source: "RootTabView.onAppear",
            current: selectedTab,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName,
            scenePhase: String(describing: scenePhase),
            note: splitVisibilityAuditNote()
        )
        appTheme.refresh(systemColorScheme: systemColorScheme, forceThemeRevision: true, notifyLegacy: true)
        syncRuntimeSelectedTab(selectedTab, source: "RootTabView.onAppear")
        ensureVisibleIPadListIfNeeded()
        startColdLaunchPrefetchIfNeeded()
        startAQBadgeCheckIfNeeded()
        handlePendingMessagesNotificationNavigationIfNeeded()
    }

    private func handleCurrentAccountChange(from oldAccountID: String?, to newAccountID: String?) {
        RootTabAudit.log(
            "accountChange",
            source: "RootTabView.onChangeAccount",
            current: selectedTab,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName,
            note: "oldNil=\(oldAccountID == nil) newNil=\(newAccountID == nil)"
        )
        if oldAccountID != newAccountID {
            clearTopicSelections()
        }

        if newAccountID == nil {
            cancelColdLaunchPrefetch()
            hasScheduledColdLaunchPrefetch = false
        } else {
            startColdLaunchPrefetchIfNeeded()
        }

        guard oldAccountID != newAccountID, newAccountID != nil else { return }
        DispatchQueue.main.async {
            RootTabAudit.log(
                "rootTabReselected.post",
                source: "accountChange",
                current: selectedTab,
                runtime: RuntimeState.selectedTab,
                mode: rootModeAuditName
            )
            NotificationCenter.default.post(
                name: .rootTabReselected,
                object: nil,
                userInfo: ["tab": selectedTab.rawValue]
            )
        }
    }

    private func clearTopicSelections() {
        categoriesSelectedForum = nil
        categoriesInitialFlagOverride = nil
        categoriesTopicTarget = nil
        favoritesTopicTarget = nil
        messagesTopicTarget = nil
        bookmarksTopicTarget = nil
        qualityAlertsTopicTarget = nil
        // A new account starts the Plus tab on Réglages, not on the last page of the old one
        // (e.g. « Supprimer mon compte »).
        lastMoreDestination = .settings
        if iPadSidebarDestination.rootTab == .more {
            iPadSidebarDestination = .settings
        }
        resetAllDetailNavigation()
        preferredCompactColumn = .content
    }

    private func handleScenePhaseChange(_ newValue: ScenePhase) {
        RootTabAudit.log(
            "scenePhase.change",
            source: "RootTabView.onChangeScenePhase",
            current: selectedTab,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName,
            scenePhase: String(describing: newValue)
        )
        RootTabAudit.log(
            "splitVisibility.scenePhaseChanged",
            source: "RootTabView.onChangeScenePhase",
            current: selectedTab,
            runtime: RuntimeState.selectedTab,
            mode: rootModeAuditName,
            scenePhase: String(describing: newValue),
            note: splitVisibilityAuditNote()
        )
        guard newValue == .active else { return }
        appTheme.refresh(systemColorScheme: systemColorScheme, forceThemeRevision: true, notifyLegacy: true)
        startColdLaunchPrefetchIfNeeded()
        startAQBadgeCheckIfNeeded()
        handlePendingMessagesNotificationNavigationIfNeeded()
        Task { await syncAppIconBadge() }
    }
}

private struct TabBarReselectionObserver: UIViewControllerRepresentable {
    let onSelect: (Int) -> Void
    let onReselect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onReselect: onReselect)
    }

    func makeUIViewController(context: Context) -> ObserverViewController {
        let observer = ObserverViewController()
        observer.onHierarchyUpdate = { host in
            context.coordinator.attach(from: host)
        }
        return observer
    }

    func updateUIViewController(_ uiViewController: ObserverViewController, context: Context) {
        uiViewController.onHierarchyUpdate = { host in
            context.coordinator.attach(from: host)
        }
        context.coordinator.attach(from: uiViewController)
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private let onSelect: (Int) -> Void
        private let onReselect: (Int) -> Void
        private weak var tabBarController: UITabBarController?

        init(onSelect: @escaping (Int) -> Void, onReselect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
            self.onReselect = onReselect
        }

        func attach(from host: UIViewController?) {
            if let tabBarController = host?.tabBarController ?? findTabBarController(in: host) {
                bind(to: tabBarController)
                return
            }
            if
                let root = host?.view.window?.rootViewController ?? Self.keyWindowRootViewController(),
                let tabBarController = findTabBarController(in: root)
            {
                bind(to: tabBarController)
            }
        }

        private func bind(to tabBarController: UITabBarController) {
            guard self.tabBarController !== tabBarController else { return }
            self.tabBarController = tabBarController
            tabBarController.delegate = self
            RootTabAudit.log(
                "UIKit.bindTabBarController",
                source: "TabBarReselectionObserver.Coordinator",
                selectedIndex: tabBarController.selectedIndex,
                viewControllerCount: tabBarController.viewControllers?.count
            )
        }

        @available(iOS 18.0, *)
        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            guard #available(iOS 27.0, *) else { return true }

            guard let tappedIndex = index(of: tab, in: tabBarController) else {
                RootTabAudit.log(
                    "UIKit.delegate.shouldSelectTab.unresolved",
                    source: "UITabBarControllerDelegate",
                    uiSelectedIndex: tabBarController.selectedIndex,
                    viewControllerCount: tabBarController.tabs.count,
                    note: "tabNotFoundInRootTabs"
                )
                return true
            }

            RootTabAudit.log(
                "UIKit.delegate.shouldSelectTab",
                source: "UITabBarControllerDelegate",
                selectedIndex: tappedIndex,
                uiSelectedIndex: tabBarController.selectedIndex,
                viewControllerCount: tabBarController.tabs.count,
                note: tappedIndex == tabBarController.selectedIndex ? "reselect=true" : "reselect=false"
            )
            if tappedIndex == tabBarController.selectedIndex {
                onReselect(tappedIndex)
            }
            return true
        }

        @available(iOS 18.0, *)
        func tabBarController(
            _ tabBarController: UITabBarController,
            didSelectTab selectedTab: UITab,
            previousTab: UITab?
        ) {
            guard #available(iOS 27.0, *) else { return }

            guard let selectedIndex = index(of: selectedTab, in: tabBarController) else {
                RootTabAudit.log(
                    "UIKit.delegate.didSelectTab.unresolved",
                    source: "UITabBarControllerDelegate",
                    uiSelectedIndex: tabBarController.selectedIndex,
                    viewControllerCount: tabBarController.tabs.count,
                    note: "tabNotFoundInRootTabs"
                )
                return
            }

            RootTabAudit.log(
                "UIKit.delegate.didSelectTab",
                source: "UITabBarControllerDelegate",
                selectedIndex: selectedIndex,
                uiSelectedIndex: tabBarController.selectedIndex,
                viewControllerCount: tabBarController.tabs.count
            )
            onSelect(selectedIndex)
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard #unavailable(iOS 27.0) else { return }

            guard
                let viewControllers = tabBarController.viewControllers,
                let selectedIndex = viewControllers.firstIndex(where: { $0 === viewController })
            else {
                return
            }
            RootTabAudit.log(
                "UIKit.delegate.didSelect",
                source: "UITabBarControllerDelegate",
                selectedIndex: selectedIndex,
                uiSelectedIndex: tabBarController.selectedIndex,
                viewControllerCount: viewControllers.count
            )
            onSelect(selectedIndex)
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            guard #unavailable(iOS 27.0) else { return true }

            if
                let viewControllers = tabBarController.viewControllers,
                let tappedIndex = viewControllers.firstIndex(where: { $0 === viewController })
            {
                RootTabAudit.log(
                    "UIKit.delegate.shouldSelect",
                    source: "UITabBarControllerDelegate",
                    selectedIndex: tappedIndex,
                    uiSelectedIndex: tabBarController.selectedIndex,
                    viewControllerCount: viewControllers.count,
                    note: tappedIndex == tabBarController.selectedIndex ? "reselect=true" : "reselect=false"
                )
                if tappedIndex == tabBarController.selectedIndex {
                    onReselect(tappedIndex)
                }
            }
            return true
        }

        @available(iOS 18.0, *)
        private func index(of tab: UITab, in tabBarController: UITabBarController) -> Int? {
            tabBarController.tabs.firstIndex {
                $0 === tab || $0.identifier == tab.identifier
            }
        }

        private func findTabBarController(in root: UIViewController?) -> UITabBarController? {
            guard let root else { return nil }
            if let tabBarController = root as? UITabBarController {
                return tabBarController
            }
            for child in root.children {
                if let tabBarController = findTabBarController(in: child) {
                    return tabBarController
                }
            }
            return root.presentedViewController.flatMap { findTabBarController(in: $0) }
        }

        private static func keyWindowRootViewController() -> UIViewController? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: { $0.isKeyWindow })?
                .rootViewController
        }
    }
}

private extension View {
    @ViewBuilder
    func hfrTabBarMinimizeBehavior(tabBarMinimizeOnScroll: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(tabBarMinimizeOnScroll ? .onScrollDown : .never)
        } else {
            self
        }
    }
}

private final class ObserverViewController: UIViewController {
    var onHierarchyUpdate: ((UIViewController) -> Void)?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        onHierarchyUpdate?(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onHierarchyUpdate?(self)
    }
}


#Preview {
    CategoriesListView(
        viewModel: CategoriesListViewModel(
            forumsLoader: CategoriesPreviewFactory.PreviewForumsLoader(result: .success(CategoriesPreviewFactory.sampleForums))
        )
    )
}

#Preview("Forum topics - happy path") {
    NavigationStack {
        ForumTopicsListView(
            forum: CategoriesPreviewFactory.sampleForums[0],
            viewModel: ForumTopicsListViewModel(
                forum: CategoriesPreviewFactory.sampleForums[0],
                topicsLoader: CategoriesPreviewFactory.PreviewForumTopicsLoader(result: .success(CategoriesPreviewFactory.sampleTopics))
            )
        )
    }
}

#Preview("Categories - error") {
    CategoriesListView(
        viewModel: CategoriesListViewModel(
            forumsLoader: CategoriesPreviewFactory.PreviewForumsLoader(result: .failure(CategoriesPreviewFactory.PreviewError.offline))
        )
    )
}
