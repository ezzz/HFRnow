//
//  ContentView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class CategoriesListViewModel: ObservableObject {
    @Published var forums: [Forum] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let forumsLoader: ForumsLoading

    init(forumsLoader: ForumsLoading? = nil) {
        self.forumsLoader = forumsLoader ?? ObjCForumsLoader()
    }

    func load() {
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

    func load() {
        loadRequestID += 1
        let requestID = loadRequestID
        isLoading = true
        errorMessage = nil
        newTopicURL = nil
        topicsLoader.fetchTopics(for: forum, flag: selectedFlag) { [weak self] result, error in
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
                } else {
                    self.errorMessage = nil
                    self.topics = result?.topics ?? []
                    self.newTopicURL = result?.newTopicURL
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
    @State private var hasLoaded = false
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false

    @MainActor
    init(
        viewModel: CategoriesListViewModel? = nil,
        accountsStore: AccountsStore? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? CategoriesListViewModel())
        _accountsStore = StateObject(wrappedValue: accountsStore ?? AccountsStore())
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = viewModel.errorMessage {
                    Text("Erreur : \(errorMessage)")
                        .foregroundStyle(.red)
                }
                if !viewModel.isLoading && viewModel.forums.isEmpty && viewModel.errorMessage == nil {
                    Text("Aucune categorie")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.forums) { forum in
                    NavigationLink {
                        ForumTopicsListView(
                            forum: forum,
                            accountsStore: accountsStore
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ForumCategoryIconView(forum: forum)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(forum.aTitle ?? "Forum")
                                if let subForums = forum.subCats as? [Forum], !subForums.isEmpty {
                                    Text("\(subForums.count) sous-forums")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categories")
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
                        AppHaptics.impact(.light)
                        viewModel.load()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
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
                viewModel.load()
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

    private let topicActionService: FavoritesTopicActionServicing

    @MainActor
    init(
        forum: Forum,
        initialFlagOverride: TopicListFlag? = nil,
        viewModel: ForumTopicsListViewModel? = nil,
        accountsStore: AccountsStore? = nil,
        topicActionService: FavoritesTopicActionServicing = ForumFavoritesTopicActionService()
    ) {
        self.forum = forum
        self.initialFlagOverride = initialFlagOverride
        _viewModel = StateObject(wrappedValue: viewModel ?? ForumTopicsListViewModel(forum: forum))
        self._accountsStore = ObservedObject(wrappedValue: accountsStore ?? AccountsStore())
        _selectedForumIdentifier = State(initialValue: ForumTopicsListView.forumIdentifier(for: forum))
        self.topicActionService = topicActionService
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

            if !isLoggedIn {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Connexion requise pour Favoris, Suivis et Lus", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote.weight(.semibold))
                    Text("Vous pouvez consulter \"Tous\" sans compte.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            if let errorMessage = viewModel.errorMessage {
                Text("Erreur : \(errorMessage)")
                    .foregroundStyle(.red)
            }
            if !viewModel.isLoading && viewModel.topics.isEmpty && viewModel.errorMessage == nil {
                Text("Aucun topic")
                    .foregroundStyle(.secondary)
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
                    extraContextMenu: hasFlag ? {
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
                    } : nil
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
            }
        }
        .refreshable {
            await MainActor.run { viewModel.load() }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                @Sendable func checkDone() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if viewModel.isLoading { checkDone() } else { continuation.resume() }
                    }
                }
                checkDone()
            }
        }
        .navigationTitle(forum.aTitle ?? "Topics")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    accountMenuItems
                } label: {
                    ToolbarProfileImage(image: accountsStore.currentAvatarImage, url: nil)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    AppHaptics.impact(.light)
                    isNewTopicComposerPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isLoggedIn || viewModel.newTopicURL == nil)

                Button {
                    AppHaptics.impact(.light)
                    viewModel.load()
                } label: {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
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
            guard hasLoaded else { return }
            viewModel.load()
        }
        .onChange(of: accountsStore.currentAccount?.id) { _, _ in
            if !isLoggedIn && viewModel.selectedFlag != .all {
                viewModel.selectedFlag = .all
                return
            }
            guard hasLoaded else { return }
            viewModel.load()
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

        func fetchTopics(for forum: Forum, flag: TopicListFlag, completion: @escaping ForumTopicsLoadCompletion) {
            switch result {
            case .success(let topics):
                completion(ForumTopicsLoadResult(topics: topics, newTopicURL: URL(string: "https://forum.hardware.fr/bddpost.php?config=hfr.inc&cat=13&post=0")), nil)
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

struct RootTabView: View {
    private enum RuntimeState {
        static var selectedTab: RootTabIdentifier = .favorites
    }

    @StateObject private var appTheme = AppThemeStore.shared
    @StateObject private var accountsStore = AccountsStore()
    @StateObject private var favoritesViewModel = FavoritesViewModel()
    @StateObject private var messagesViewModel = MPListViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: RootTabIdentifier
    @State private var hasScheduledColdLaunchPrefetch = false
    @State private var coldLaunchPrefetchTask: Task<Void, Never>?
    @State private var hasScheduledAQBadgeCheck = false
    @State private var aqBadgeCheckTask: Task<Void, Never>?
    @State private var messagesNavigationResetToken = UUID()
    @AppStorage("nb_mp") private var unreadMPCount = 0
    @AppStorage(AQUnreadCounter.storageKey) private var unreadAQCount = 0
    @AppStorage("mp_badge_enabled") private var mpBadgeEnabled = true
    @AppStorage(AppTabBarMinimizeOnScroll.key) private var tabBarMinimizeOnScroll = true

    init() {
        _selectedTab = State(initialValue: RuntimeState.selectedTab)
    }

    private func syncRuntimeSelectedTab(_ tab: RootTabIdentifier) {
        if RuntimeState.selectedTab != tab {
            RuntimeState.selectedTab = tab
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
        if selectedTab != tab {
            selectedTab = tab
        }
        syncRuntimeSelectedTab(tab)
    }

    private func showMessagesList(forceRefresh: Bool) {
        messagesNavigationResetToken = UUID()
        if selectedTab != .messages {
            selectedTab = .messages
        }
        syncRuntimeSelectedTab(.messages)

        guard accountsStore.currentAccount != nil else { return }
        if forceRefresh {
            messagesViewModel.load()
        } else {
            messagesViewModel.ensureLoaded()
        }
    }

    private func handlePendingMessagesNotificationNavigationIfNeeded(forceRefresh: Bool = true) {
        guard MessagesNotificationNavigation.consumePendingOpenMessagesRequest() else { return }
        showMessagesList(forceRefresh: forceRefresh)
    }

    var body: some View {
        rootContainer
            .preferredColorScheme(appTheme.preferredColorScheme)
            .tint(appTheme.actionTintColor)
            .environment(\.appThemePalette, appTheme.palette)
            .onAppear(perform: handleAppear)
            .onChange(of: selectedTab) { _, newValue in
                syncRuntimeSelectedTab(newValue)
            }
            .onChange(of: accountsStore.currentAccount?.id) { oldValue, newValue in
                handleCurrentAccountChange(from: oldValue, to: newValue)
            }
            .onChange(of: systemColorScheme) { _, newValue in
                appTheme.refresh(systemColorScheme: newValue)
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

    @ViewBuilder
    private var rootContainer: some View {
        if horizontalSizeClass == .regular {
            iPadSidebarRoot
        } else {
            compactTabRoot
        }
    }

    private var compactTabRoot: some View {
        rootTabs
            .hfrTabBarMinimizeBehavior(tabBarMinimizeOnScroll: tabBarMinimizeOnScroll)
            .background(tabBarReselectionObserver)
    }

    private var rootTabs: some View {
        TabView(selection: $selectedTab) {
            CategoriesListView(accountsStore: accountsStore)
                .tabItem { Label("Catégories", systemImage: "folder.fill") }
                .tag(RootTabIdentifier.categories)

            //FeedView()
            FavoritesListView(
                viewModel: favoritesViewModel,
                accountsStore: accountsStore
            )
            .tabItem { Label("Favoris", systemImage: "star.fill") }
            .tag(RootTabIdentifier.favorites)

            MPListView(
                viewModel: messagesViewModel,
                accountsStore: accountsStore,
                isActive: selectedTab == .messages,
                navigationResetToken: messagesNavigationResetToken
            )
            .tabItem { Label("Messages", systemImage: "envelope") }
            .tag(RootTabIdentifier.messages)
            .badge(mpBadgeEnabled && unreadMPCount > 0 ? unreadMPCount : 0)

            NavigationStack {
                PlusHomeView()
            }
            .tabItem { Label("Plus", systemImage: "ellipsis") }
            .tag(RootTabIdentifier.more)
            .badge(unreadAQCount > 0 ? unreadAQCount : 0)
        }
    }

    private var iPadSidebarRoot: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(Self.sidebarTabs, id: \.self) { tab in
                    NavigationLink(value: tab) {
                        sidebarRow(for: tab)
                    }
                }
            }
            .navigationTitle("HFRnow")
        } detail: {
            selectedTabContent
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebarSelection: Binding<RootTabIdentifier?> {
        Binding {
            selectedTab
        } set: { newValue in
            guard let newValue else { return }
            selectedTab = newValue
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .categories:
            CategoriesListView(accountsStore: accountsStore)
        case .favorites:
            FavoritesListView(
                viewModel: favoritesViewModel,
                accountsStore: accountsStore
            )
        case .messages:
            MPListView(
                viewModel: messagesViewModel,
                accountsStore: accountsStore,
                isActive: selectedTab == .messages,
                navigationResetToken: messagesNavigationResetToken
            )
        case .more:
            PlusHomeView()
        }
    }

    private func sidebarRow(for tab: RootTabIdentifier) -> some View {
        HStack {
            Label(sidebarTitle(for: tab), systemImage: sidebarSystemImage(for: tab))
            Spacer()
            if sidebarBadgeCount(for: tab) > 0 {
                Text("\(sidebarBadgeCount(for: tab))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }
        }
    }

    private static let sidebarTabs: [RootTabIdentifier] = [
        .categories,
        .favorites,
        .messages,
        .more
    ]

    private func sidebarTitle(for tab: RootTabIdentifier) -> String {
        switch tab {
        case .categories: "Catégories"
        case .favorites: "Favoris"
        case .messages: "Messages"
        case .more: "Plus"
        }
    }

    private func sidebarSystemImage(for tab: RootTabIdentifier) -> String {
        switch tab {
        case .categories: "folder.fill"
        case .favorites: "star.fill"
        case .messages: "envelope"
        case .more: "ellipsis"
        }
    }

    private func sidebarBadgeCount(for tab: RootTabIdentifier) -> Int {
        switch tab {
        case .messages:
            mpBadgeEnabled ? unreadMPCount : 0
        case .more:
            unreadAQCount
        case .categories, .favorites:
            0
        }
    }

    private var tabBarReselectionObserver: some View {
        TabBarReselectionObserver(
            onSelect: handleUIKitTabSelection
        ) { selectedIndex in
            guard
                let tab = RootTabIdentifier(rawValue: selectedIndex),
                tab == .categories || tab == .favorites || tab == .messages
            else {
                return
            }
            NotificationCenter.default.post(
                name: .rootTabReselected,
                object: nil,
                userInfo: ["tab": tab.rawValue]
            )
        }
        .frame(width: 0, height: 0)
    }

    private func handleAppear() {
        appTheme.refresh(systemColorScheme: systemColorScheme, forceThemeRevision: true)
        syncRuntimeSelectedTab(selectedTab)
        startColdLaunchPrefetchIfNeeded()
        startAQBadgeCheckIfNeeded()
        handlePendingMessagesNotificationNavigationIfNeeded()
    }

    private func handleCurrentAccountChange(from oldAccountID: String?, to newAccountID: String?) {
        if newAccountID == nil {
            cancelColdLaunchPrefetch()
            hasScheduledColdLaunchPrefetch = false
        } else {
            startColdLaunchPrefetchIfNeeded()
        }

        guard oldAccountID != newAccountID, newAccountID != nil else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .rootTabReselected,
                object: nil,
                userInfo: ["tab": selectedTab.rawValue]
            )
        }
    }

    private func handleScenePhaseChange(_ newValue: ScenePhase) {
        guard newValue == .active else { return }
        appTheme.refresh(systemColorScheme: systemColorScheme, forceThemeRevision: true)
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
            onSelect(tabBarController.selectedIndex)
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard
                let viewControllers = tabBarController.viewControllers,
                let selectedIndex = viewControllers.firstIndex(where: { $0 === viewController })
            else {
                return
            }
            onSelect(selectedIndex)
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            if
                let viewControllers = tabBarController.viewControllers,
                let tappedIndex = viewControllers.firstIndex(where: { $0 === viewController }),
                tappedIndex == tabBarController.selectedIndex
            {
                onReselect(tappedIndex)
            }
            return true
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
