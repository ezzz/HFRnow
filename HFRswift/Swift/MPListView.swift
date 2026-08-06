//
//  MPListView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import Combine
import CryptoKit

enum MPTopicReadState {
    private static let unreadPrefix = "[non lu]"

    static func hasUnreadPrefix(_ title: String?) -> Bool {
        guard let title else { return false }
        return title.lowercased().hasPrefix(unreadPrefix)
    }

    static func isUnread(_ topic: Topic) -> Bool {
        hasUnreadPrefix(topic._aTitle) || !topic.isViewed
    }

    static func markTopicAsRead(_ topic: Topic) -> Bool {
        let wasUnread = isUnread(topic)

        if hasUnreadPrefix(topic._aTitle), let title = topic._aTitle {
            topic._aTitle = String(title.dropFirst(unreadPrefix.count)).trimmingCharacters(in: .whitespaces)
        }

        topic.isLocallyViewedInApp = true
        topic.isViewed = true
        return wasUnread
    }

    static func markTopicAsUnread(_ topic: Topic) -> Bool {
        let wasRead = topic.isViewed
        topic.isLocallyViewedInApp = false
        topic.isViewedFromForumAtLoad = false
        topic.isViewed = false
        return wasRead
    }

    static func decrementedUnreadCount(_ count: Int, afterMarkingUnreadTopic didMarkUnreadTopic: Bool) -> Int {
        didMarkUnreadTopic ? max(count - 1, 0) : count
    }

    static func incrementedUnreadCount(_ count: Int, afterMarkingReadTopic didMarkReadTopic: Bool) -> Int {
        didMarkReadTopic ? count + 1 : count
    }
}

enum MPTopicActionError: LocalizedError {
    case invalidTopicIdentifier
    case missingHash
    case invalidRequest
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidTopicIdentifier:
            return "MP invalide."
        case .missingHash:
            return "Session invalide: hash manquant."
        case .invalidRequest:
            return "Requête invalide."
        case .serverError(let statusCode):
            return "Erreur serveur (\(statusCode))."
        }
    }
}

protocol MPTopicActionServicing {
    func markTopicUnread(topic: Topic) async throws
    func deleteTopic(topic: Topic) async throws
}

final class ForumMPTopicActionService: MPTopicActionServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func markTopicUnread(topic: Topic) async throws {
        guard let topicID = topicID(from: topic) else {
            throw MPTopicActionError.invalidTopicIdentifier
        }

        let baseURL = URL(string: k.forumURL()) ?? URL(string: "https://forum.hardware.fr")!
        var components = URLComponents(
            url: baseURL.appendingPathComponent("user/nonlu.php"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "config", value: "hfr.inc"),
            URLQueryItem(name: "cat", value: "prive"),
            URLQueryItem(name: "subcat", value: "0"),
            URLQueryItem(name: "post", value: "\(topicID)"),
            URLQueryItem(name: "page", value: "\(pageNumber(from: topic))"),
            URLQueryItem(name: "p", value: "1"),
            URLQueryItem(name: "sondage", value: "0"),
            URLQueryItem(name: "owntopic", value: "0"),
            URLQueryItem(name: "new", value: "0")
        ]
        guard let requestURL = components?.url else {
            throw MPTopicActionError.invalidRequest
        }

        let (_, response) = try await session.data(from: requestURL)
        try validate(response: response)
    }

    func deleteTopic(topic: Topic) async throws {
        guard let topicID = topicID(from: topic) else {
            throw MPTopicActionError.invalidTopicIdentifier
        }
        guard
            let hash = HFRplusAppDelegate.shared()?
                .hash_check?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !hash.isEmpty
        else {
            throw MPTopicActionError.missingHash
        }

        let baseURL = URL(string: k.forumURL()) ?? URL(string: "https://forum.hardware.fr")!
        var components = URLComponents(
            url: baseURL.appendingPathComponent("modo/manageaction.php"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "config", value: "hfr.inc"),
            URLQueryItem(name: "cat", value: "prive"),
            URLQueryItem(name: "type_page", value: "forum1"),
            URLQueryItem(name: "moderation", value: "0")
        ]
        guard let requestURL = components?.url else {
            throw MPTopicActionError.invalidRequest
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded([
            "hash_check": hash,
            "topic0": "\(topicID)",
            "valuecat0": "prive",
            "valueforum0": "hardwarefr",
            "topic1": "-1",
            "topic_statusno1": "-1",
            "action_reaction": "valid_eff_prive",
            "type_page": "forum1"
        ])
        .data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MPTopicActionError.invalidRequest
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MPTopicActionError.serverError(httpResponse.statusCode)
        }
    }

    private func topicID(from topic: Topic) -> Int? {
        if topic.postID > 0 {
            return Int(topic.postID)
        }
        return topicID(from: topic.aURL)
            ?? topicID(from: topic.aURLOfLastPost)
            ?? topicID(from: topic.aURLOfLastPage)
            ?? topicID(from: topic.aURLOfFirstPage)
    }

    private func topicID(from urlString: String?) -> Int? {
        guard let urlString, !urlString.isEmpty else { return nil }

        if
            let components = URLComponents(string: urlString),
            let value = components.queryItems?.first(where: { $0.name == "post" })?.value,
            let topicID = Int(value),
            topicID > 0
        {
            return topicID
        }

        guard
            let regex = try? NSRegularExpression(pattern: "(?:\\?|&)post=(\\d+)", options: [.caseInsensitive])
        else {
            return nil
        }
        let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        guard
            let match = regex.firstMatch(in: urlString, options: [], range: range),
            match.numberOfRanges >= 2,
            let captureRange = Range(match.range(at: 1), in: urlString),
            let topicID = Int(urlString[captureRange]),
            topicID > 0
        else {
            return nil
        }

        return topicID
    }

    private func pageNumber(from topic: Topic) -> Int {
        let page = TopicPageURLRouting.pageNumber(from: topic.aURL)
            ?? TopicPageURLRouting.pageNumber(from: topic.aURLOfLastPost)
            ?? TopicPageURLRouting.pageNumber(from: topic.aURLOfLastPage)
            ?? Int(topic.curTopicPage)
        return max(page, 1)
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

final class MPListViewModel: ObservableObject {
    @Published var topics: [Topic] = []
    @Published var errorMessage: String? = nil
    @Published var isLoading = false
    @Published private(set) var hasLoadedOnce: Bool

    private let topicsLoader: MPTopicsLoading
    private let mpStorage: LegacyMPStorageManaging
    private var loadRequestID = 0
    private var lastSuccessfulLoadDate: Date?
    private var pendingForcedReload = false

    init(
        topicsLoader: MPTopicsLoading = ObjCMPTopicsLoader(),
        mpStorage: LegacyMPStorageManaging = ObjCMPStorageBridge.shared,
        initialTopics: [Topic] = [],
        initialErrorMessage: String? = nil,
        initialIsLoading: Bool = false
    ) {
        self.topicsLoader = topicsLoader
        self.mpStorage = mpStorage
        self.topics = initialTopics
        self.errorMessage = initialErrorMessage
        self.isLoading = initialIsLoading
        self.hasLoadedOnce = initialIsLoading || !initialTopics.isEmpty || initialErrorMessage != nil
    }

    func load(retryOnCancellation: Bool = true, force: Bool = false, shouldTriggerHaptic: Bool = false) {
        guard !isLoading else {
            if force {
                pendingForcedReload = true
            }
            return
        }
        loadRequestID += 1
        let requestID = loadRequestID
        isLoading = true
        errorMessage = nil
        topicsLoader.fetchTopics { [weak self] topics, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard requestID == self.loadRequestID else { return }
                self.isLoading = false
                if let error, Self.isCancellationError(error) {
                    if retryOnCancellation {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                            self?.load(retryOnCancellation: false, shouldTriggerHaptic: shouldTriggerHaptic)
                        }
                    }
                    return
                }
                if let error {
                    self.hasLoadedOnce = true
                    self.errorMessage = error.localizedDescription
                    self.topics = []
                } else {
                    self.hasLoadedOnce = true
                    self.lastSuccessfulLoadDate = Date()
                    self.errorMessage = nil
                    self.topics = self.topicsDecoratedWithMPStorageFlags(topics ?? [])
                }
                if shouldTriggerHaptic {
                    AppHaptics.refreshCompleted()
                }
                if self.pendingForcedReload {
                    self.pendingForcedReload = false
                    self.load(retryOnCancellation: retryOnCancellation, force: true, shouldTriggerHaptic: shouldTriggerHaptic)
                }
            }
        }
    }

    func ensureLoaded() {
        guard !isLoading else { return }
        guard !hasLoadedOnce || errorMessage != nil else { return }
        load()
    }

    func loadIfStale(maxAge: TimeInterval = 30) {
        guard !isLoading else { return }
        guard hasLoadedOnce, errorMessage == nil else {
            load()
            return
        }
        guard let lastSuccessfulLoadDate else {
            load()
            return
        }
        guard Date().timeIntervalSince(lastSuccessfulLoadDate) >= maxAge else { return }
        load()
    }

    func clearForLoggedOut() {
        isLoading = false
        pendingForcedReload = false
        errorMessage = nil
        topics = []
        hasLoadedOnce = false
        lastSuccessfulLoadDate = nil
    }

    @discardableResult
    func markTopicAsRead(_ topic: Topic) -> Bool {
        let didMarkUnreadTopic = MPTopicReadState.markTopicAsRead(topic)
        topics = topics
        return didMarkUnreadTopic
    }

    @discardableResult
    func markTopicAsUnread(_ topic: Topic) -> Bool {
        let didMarkReadTopic = MPTopicReadState.markTopicAsUnread(topic)
        topics = topics
        return didMarkReadTopic
    }

    func removeTopic(_ topic: Topic) {
        topics.removeAll { $0 === topic }
    }

    private func topicsDecoratedWithMPStorageFlags(_ topics: [Topic]) -> [Topic] {
        guard UserDefaults.standard.bool(forKey: "mpstorage_active"), mpStorage.isAvailable else {
            return topics
        }

        for topic in topics where Self.hasMultipleInterlocutors(topic) {
            guard let topicID = Self.topicID(from: topic) else { continue }
            guard let flagURL = mpStorage.mpFlagURL(topicID: topicID), !flagURL.isEmpty else { continue }

            let page = mpStorage.mpFlagPage(topicID: topicID)
                ?? TopicPageURLRouting.pageNumber(from: flagURL)
                ?? max(Int(topic.curTopicPage), 1)

            topic.aURLOfFlag = flagURL
            topic.aTypeOfFlag = "red"
            topic.curTopicPage = Int32(max(page, 1))
            topic.maxTopicPage = Int32(max(Int(topic.maxTopicPage), page, 1))
        }

        return topics
    }

    private static func hasMultipleInterlocutors(_ topic: Topic) -> Bool {
        topic.aAuthorOrInter?.localizedCaseInsensitiveContains("multiples") == true
    }

    private static func topicID(from topic: Topic) -> Int? {
        if topic.postID > 0 {
            return Int(topic.postID)
        }
        return topicID(from: topic.aURL)
            ?? topicID(from: topic.aURLOfLastPost)
            ?? topicID(from: topic.aURLOfLastPage)
    }

    private static func topicID(from urlString: String?) -> Int? {
        guard let urlString, !urlString.isEmpty else { return nil }

        if
            let components = URLComponents(string: urlString),
            let value = components.queryItems?.first(where: { $0.name == "post" })?.value,
            let topicID = Int(value),
            topicID > 0
        {
            return topicID
        }

        guard
            let regex = try? NSRegularExpression(pattern: "(?:\\?|&)post=(\\d+)", options: [.caseInsensitive])
        else {
            return nil
        }
        let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        guard
            let match = regex.firstMatch(in: urlString, options: [], range: range),
            match.numberOfRanges >= 2,
            let captureRange = Range(match.range(at: 1), in: urlString),
            let topicID = Int(urlString[captureRange]),
            topicID > 0
        else {
            return nil
        }

        return topicID
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        if nsError.domain == "ASIHTTPRequestErrorDomain" && nsError.code == 4 {
            return true
        }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("annul")
    }
}

@MainActor
struct MPListView: View {
    @StateObject private var viewModel: MPListViewModel
    @StateObject private var accountsStore: AccountsStore
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false
    @State private var topicActionErrorMessage: String?
    @State private var pendingDeletedTopic: Topic?
    @State private var processingTopicIDs: Set<ObjectIdentifier> = []
    @AppStorage("nb_mp") private var unreadMPCount = 0

    private let topicActionService: any MPTopicActionServicing
    private let isActive: Bool
    private let navigationResetToken: UUID
    private let selectedTopicID: TopicNavigationID?
    private let onSelectTopic: ((TopicNavigationTarget) -> Void)?
    private let onDeleteTopic: ((TopicNavigationID) -> Void)?

    private var isLoggedIn: Bool {
        accountsStore.currentAccount != nil
    }

    private func refreshContentForSessionState(force: Bool = false) {
        if isLoggedIn {
            if force {
                viewModel.load(force: true)
            } else {
                viewModel.ensureLoaded()
            }
        } else {
            viewModel.clearForLoggedOut()
        }
    }

    private func refreshContentOnVisibility() {
        guard isLoggedIn else {
            viewModel.clearForLoggedOut()
            return
        }
        viewModel.loadIfStale(maxAge: 30)
    }

    @MainActor
    init(
        viewModel: MPListViewModel? = nil,
        accountsStore: AccountsStore? = nil,
        topicActionService: (any MPTopicActionServicing)? = nil,
        isActive: Bool = true,
        navigationResetToken: UUID = UUID(),
        selectedTopicID: TopicNavigationID? = nil,
        onSelectTopic: ((TopicNavigationTarget) -> Void)? = nil,
        onDeleteTopic: ((TopicNavigationID) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? MPListViewModel())
        _accountsStore = StateObject(wrappedValue: accountsStore ?? AccountsStore())
        self.topicActionService = topicActionService ?? ForumMPTopicActionService()
        self.isActive = isActive
        self.navigationResetToken = navigationResetToken
        self.selectedTopicID = selectedTopicID
        self.onSelectTopic = onSelectTopic
        self.onDeleteTopic = onDeleteTopic
    }

    private func markTopicAsRead(_ topic: Topic) {
        let didMarkUnreadTopic = viewModel.markTopicAsRead(topic)
        unreadMPCount = MPTopicReadState.decrementedUnreadCount(
            unreadMPCount,
            afterMarkingUnreadTopic: didMarkUnreadTopic
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletedTopic != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletedTopic = nil
                }
            }
        )
    }

    private var topicActionErrorBinding: Binding<Bool> {
        Binding(
            get: { topicActionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    topicActionErrorMessage = nil
                }
            }
        )
    }

    private func markTopicAsUnread(_ topic: Topic) {
        guard topic.isViewed else { return }
        let topicID = ObjectIdentifier(topic)
        guard !processingTopicIDs.contains(topicID) else { return }

        processingTopicIDs.insert(topicID)
        Task {
            defer { processingTopicIDs.remove(topicID) }
            do {
                try await topicActionService.markTopicUnread(topic: topic)
                let didMarkReadTopic = viewModel.markTopicAsUnread(topic)
                unreadMPCount = MPTopicReadState.incrementedUnreadCount(
                    unreadMPCount,
                    afterMarkingReadTopic: didMarkReadTopic
                )
            } catch {
                topicActionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func requestDeleteTopic(_ topic: Topic) {
        pendingDeletedTopic = topic
    }

    private func deleteTopic(_ topic: Topic) {
        let topicID = ObjectIdentifier(topic)
        guard !processingTopicIDs.contains(topicID) else { return }

        processingTopicIDs.insert(topicID)
        Task {
            defer { processingTopicIDs.remove(topicID) }
            do {
                let wasUnread = !topic.isViewed
                try await topicActionService.deleteTopic(topic: topic)
                viewModel.removeTopic(topic)
                onDeleteTopic?(
                    TopicNavigationIdentity.id(
                        for: topic,
                        context: .privateMessages
                    )
                )
                if wasUnread {
                    unreadMPCount = max(unreadMPCount - 1, 0)
                }
            } catch {
                topicActionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !isLoggedIn {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Connectez-vous pour accéder aux MP", systemImage: "envelope.badge")
                            .font(.headline)
                        Text("Ajoutez un pseudo pour charger vos messages privés.")
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
                            .foregroundColor(.red)
                    }
                    if !viewModel.isLoading && viewModel.topics.isEmpty && viewModel.errorMessage == nil {
                        Text("Aucun message")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.topics) { topic in
                        let isProcessing = processingTopicIDs.contains(ObjectIdentifier(topic))
                        MPRowView(
                            topic: topic,
                            onOpen: {
                                markTopicAsRead(topic)
                            },
                            onMarkUnread: {
                                markTopicAsUnread(topic)
                            },
                            onDelete: {
                                requestDeleteTopic(topic)
                            },
                            isProcessingAction: {
                                isProcessing
                            },
                            selectedTopicID: selectedTopicID,
                            onSelectTopic: onSelectTopic
                        )
                    }
                }
            }
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
            .navigationTitle("Messages")
            .onAppear {
                if isActive {
                    refreshContentOnVisibility()
                }
            }
            .onChange(of: isActive) { _, newValue in
                guard newValue else { return }
                refreshContentOnVisibility()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kLoginChangedNotification"))) { _ in
                refreshContentForSessionState(force: true)
            }
            .onChange(of: accountsStore.currentAccount?.id) { _, newAccountID in
                if newAccountID != nil {
                    refreshContentForSessionState(force: true)
                } else {
                    viewModel.clearForLoggedOut()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .rootTabReselected)) { notification in
                guard
                    let rawTab = notification.userInfo?["tab"] as? Int,
                    rawTab == RootTabIdentifier.messages.rawValue
                else {
                    return
                }
                AppHaptics.refreshStarted()
                viewModel.load(force: true, shouldTriggerHaptic: true)
            }
            .toolbar {
                MainToolbarContent(
                    onRefresh: {
                        viewModel.load(shouldTriggerHaptic: true)
                    },
                    isLoading: viewModel.isLoading,
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
            .alert("Déconnexion", isPresented: $showLogoutConfirm) {
                Button("Annuler", role: .cancel) {}
                Button("Déconnecter", role: .destructive) {
                    accountsStore.deleteCurrent()
                }
            } message: {
                Text("Déconnecter le compte courant ?")
            }
            .alert("Supprimer ce MP ?", isPresented: deleteConfirmationBinding) {
                Button("Annuler", role: .cancel) {
                    pendingDeletedTopic = nil
                }
                Button("Supprimer", role: .destructive) {
                    if let pendingDeletedTopic {
                        deleteTopic(pendingDeletedTopic)
                    }
                    pendingDeletedTopic = nil
                }
            } message: {
                Text("La conversation sera effacée du forum.")
            }
            .alert("Action impossible", isPresented: topicActionErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(topicActionErrorMessage ?? "Erreur inconnue.")
            }
        }
        .id(navigationResetToken)
    }
}

struct MPRowView: View {
    var topic: Topic
    var onOpen: (() -> Void)? = nil
    var onMarkUnread: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isProcessingAction: (() -> Bool)? = nil
    var selectedTopicID: TopicNavigationID?
    var onSelectTopic: ((TopicNavigationTarget) -> Void)?
    @AppStorage("mpstorage_active") private var mpStorageActive = false

    // "[non lu]" prefix detection — strips brackets, returns the keyword if present.
    private static let nonLuPrefix = "[non lu]"

    private var isViewed: Bool {
        topic.isViewed
    }

    private var hasNonLuPrefix: Bool {
        (topic._aTitle ?? "").lowercased().hasPrefix(Self.nonLuPrefix)
    }

    private var cleanedTitle: String? {
        guard hasNonLuPrefix, let raw = topic._aTitle else { return nil }
        return raw.dropFirst(Self.nonLuPrefix.count)
            .trimmingCharacters(in: .whitespaces)
    }

    private var nonLuBadge: AnyView? {
        guard hasNonLuPrefix else { return nil }
        return AnyView(
            Text("non lu")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(uiColor: .systemGray).opacity(isViewed ? 0.5 : 1), in: Capsule())
        )
    }

    private var interlocutorLabel: String? {
        guard let interlocutor = topic.aAuthorOrInter else { return nil }
        if interlocutor.localizedCaseInsensitiveContains("multiples") {
            if mpStorageActive,
               topic.aURLOfFlag?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                let currentPage = max(Int(topic.curTopicPage), 1)
                let maxPage = max(Int(topic.maxTopicPage), currentPage)
                return "⚑ \(currentPage) / \(maxPage)"
            }
            return "Interlocuteurs multiples"
        }
        return interlocutor
    }

    private var trailingLabel: String? {
        guard let author = topic.aAuthorOfLastPost, let when = topic.aDateOfLastPost else { return nil }
        return "\(author) - \(when)"
    }

    private var avatarAccessory: AnyView {
        AnyView(MPAvatarView(interlocutor: topic.aAuthorOrInter))
    }

    private var isProcessing: Bool {
        isProcessingAction?() ?? false
    }

    private var extraContextMenu: (() -> AnyView)? {
        guard onMarkUnread != nil || onDelete != nil else { return nil }

        return {
            AnyView(
                Group {
                    if isViewed, let onMarkUnread {
                        Button {
                            onMarkUnread()
                        } label: {
                            MenuActionLabel("Marquer non lu", systemImage: "envelope.badge")
                        }
                        .disabled(isProcessing)
                    }

                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            MenuActionLabel("Supprimer", systemImage: "trash", role: .destructive)
                        }
                        .disabled(isProcessing)
                    }
                }
            )
        }
    }

    var body: some View {
        TopicListRowView(
            topic: topic,
            isVisited: isViewed,
            titleFont: nil,
            titleBaseSize: 14.3,
            titleWeight: isViewed ? .regular : .semibold,
            titleOverride: cleanedTitle,
            titleLeadingBadge: nonLuBadge,
            showUnreadBadge: false,
            leadingBottomText: interlocutorLabel,
            trailingBottomText: trailingLabel,
            contentPadding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0),
            leadingAccessory: avatarAccessory,
            openContext: .privateMessages,
            quickActions: TopicQuickActionPolicy.defaults(for: .privateMessages),
            extraContextMenu: extraContextMenu,
            selectedTopicID: selectedTopicID,
            onSelectTarget: onSelectTopic,
            onDidOpen: { _ in
                onOpen?()
            }
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
    }
}

private struct MPAvatarView: View {
    let interlocutor: String?
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedImage: UIImage? {
        MPAvatarImageStore.image(for: interlocutor, colorScheme: colorScheme)
    }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(uiImage: resolvedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .padding(5)
                    }
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.tertiary, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private enum MPAvatarImageStore {
    static func image(for interlocutor: String?, colorScheme: ColorScheme) -> UIImage? {
        guard let normalized = normalizedInterlocutor(interlocutor) else {
            return defaultAvatar(for: colorScheme)
        }
        if normalized.localizedCaseInsensitiveContains("multiples") {
            return groupAvatar(for: colorScheme)
        }
        return cachedAvatar(for: normalized) ?? defaultAvatar(for: colorScheme)
    }

    private static func normalizedInterlocutor(_ interlocutor: String?) -> String? {
        guard let trimmed = interlocutor?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func cachedAvatar(for pseudo: String) -> UIImage? {
        guard let cacheDirectory else { return nil }
        let digest = Insecure.MD5.hash(data: Data(pseudo.lowercased().utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        let fileURL = cacheDirectory.appendingPathComponent(filename, isDirectory: false)
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            let image = UIImage(data: data)
        else {
            return nil
        }
        return image
    }

    private static var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("avatars", isDirectory: true)
    }

    private static func defaultAvatar(for colorScheme: ColorScheme) -> UIImage? {
        let assetName = colorScheme == .dark ? "avatar_male_gray_on_dark_48x48" : "avatar_male_gray_on_light_48x48"
        return UIImage(named: assetName)
    }

    private static func groupAvatar(for colorScheme: ColorScheme) -> UIImage? {
        let assetName = colorScheme == .dark ? "group_dark" : "group_light"
        return UIImage(named: assetName) ?? UIImage(named: "group")
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
