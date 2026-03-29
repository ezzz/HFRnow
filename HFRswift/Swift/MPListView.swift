//
//  MPListView.swift
//  HFRswift
//
//  Created by Bruno ARENE on 19/07/2025.
//

import SwiftUI
import Combine
import CryptoKit

final class MPListViewModel: ObservableObject {
    @Published var topics: [Topic] = []
    @Published var errorMessage: String? = nil
    @Published var isLoading = false

    private let topicsLoader: MPTopicsLoading
    private var loadRequestID = 0

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

    func load(retryOnCancellation: Bool = true) {
        loadRequestID += 1
        let requestID = loadRequestID
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        topicsLoader.fetchTopics { [weak self] topics, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard requestID == self.loadRequestID else { return }
                self.isLoading = false
                if let error, Self.isCancellationError(error) {
                    if retryOnCancellation {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                            self?.load(retryOnCancellation: false)
                        }
                    }
                    return
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

    func clearForLoggedOut() {
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorMessage = nil
            self.topics = []
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
        let message = nsError.localizedDescription.lowercased()
        return message.contains("cancel") || message.contains("annul")
    }
}

@MainActor
struct MPListView: View {
    @StateObject private var viewModel: MPListViewModel
    @StateObject private var accountsStore: AccountsStore
    @State private var hasLoaded = false
    @State private var showAddAccountSheet = false
    @State private var showLogoutConfirm = false

    private var isLoggedIn: Bool {
        accountsStore.currentAccount != nil
    }

    private func refreshContentForSessionState() {
        if isLoggedIn {
            viewModel.load()
        } else {
            viewModel.clearForLoggedOut()
        }
    }

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
            }
            .navigationTitle("Messages")
            .onAppear {
                if !hasLoaded {
                    refreshContentForSessionState()
                    hasLoaded = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kLoginChangedNotification"))) { _ in
                refreshContentForSessionState()
            }
            .onChange(of: accountsStore.currentAccount?.id) { _, newAccountID in
                if newAccountID != nil {
                    if viewModel.topics.isEmpty && !viewModel.isLoading {
                        viewModel.load()
                    }
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
                refreshContentForSessionState()
            }
            .toolbar {
                MainToolbarContent(
                    onRefresh: {
                        viewModel.load()
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
                Text("Supprimer le compte courant ?")
            }
        }
    }
}

struct MPRowView: View {
    var topic: Topic

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
        if interlocutor.contains("multiples") { return "Interlocuteurs multiples" }
        return interlocutor
    }

    private var trailingLabel: String? {
        guard let author = topic.aAuthorOfLastPost, let when = topic.aDateOfLastPost else { return nil }
        return "\(author) - \(when)"
    }

    private var avatarAccessory: AnyView {
        AnyView(MPAvatarView(interlocutor: topic.aAuthorOrInter))
    }

    var body: some View {
        TopicListRowView(
            topic: topic,
            isVisited: isViewed,
            titleFont: .system(size: 13, weight: isViewed ? .regular : .semibold),
            titleOverride: cleanedTitle,
            titleLeadingBadge: nonLuBadge,
            showUnreadBadge: false,
            leadingBottomText: interlocutorLabel,
            trailingBottomText: trailingLabel,
            contentPadding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0),
            leadingAccessory: avatarAccessory,
            openContext: .messages,
            quickActions: TopicQuickActionPolicy.defaults(for: .messages)
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
