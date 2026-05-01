//
//  UserProfileView.swift
//  HFRswift
//
//  Native SwiftUI rendering for forum user profiles.
//

import SwiftUI
import UIKit
import SafariServices

struct UserProfile: Equatable {
    var pseudo: String
    var status: String?
    var avatarURL: URL?
    var summary: [UserProfileSummaryItem]
    var sections: [UserProfileSection]
    var personalSmilies: [UserProfileSmiley]
    var actions: [UserProfileAction]

    var displayName: String {
        pseudo.isEmpty ? "Profil" : pseudo
    }
}

struct UserProfileSummaryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
}

struct UserProfileSection: Identifiable, Equatable {
    let id: String
    let title: String
    var fields: [UserProfileField]
}

struct UserProfileField: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let url: URL?
    let isPlaceholder: Bool
}

struct UserProfileSmiley: Identifiable, Equatable {
    let id: String
    let code: String
    let imageURL: URL
    let title: String?
}

struct UserProfileAction: Identifiable, Equatable {
    enum Kind: Equatable {
        case privateMessage
        case allMessages
        case addContact
        case transaction
        case configuration
        case link
    }

    let id: String
    let title: String
    let subtitle: String?
    let url: URL
    let kind: Kind

    var systemImage: String {
        switch kind {
        case .privateMessage:
            return "message"
        case .allMessages:
            return "text.bubble"
        case .addContact:
            return "person.badge.plus"
        case .transaction:
            return "arrow.left.arrow.right"
        case .configuration:
            return "desktopcomputer"
        case .link:
            return "link"
        }
    }
}

struct UserProfileQuickActions {
    let privateMessageURL: URL?
    let authorName: String?
    let isBlacklisted: Bool
    let isWhitelisted: Bool
    let onPrivateMessage: (URL) -> Void
    let onBlacklist: (String) -> Void
    let onWhitelist: (String) -> Void
}

enum UserProfileLoadingError: LocalizedError {
    case invalidProfile

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            return "Profil impossible à lire."
        }
    }
}

protocol UserProfileServicing {
    func fetchProfile(url: URL) async throws -> UserProfile
}

struct UserProfileService: UserProfileServicing {
    var session: URLSession = .shared

    func fetchProfile(url: URL) async throws -> UserProfile {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, _) = try await session.data(for: request)
        let html = Self.decodeHTML(data)
        return try UserProfileHTMLParser.parse(html: html, sourceURL: url)
    }

    private static func decodeHTML(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        if let cp1252 = String(data: data, encoding: .windowsCP1252) {
            return cp1252
        }
        return String(decoding: data, as: UTF8.self)
    }
}

enum UserProfileHTMLParser {
    private struct Cell {
        let className: String
        let attributes: String
        let rawHTML: String
    }

    static func parse(html: String, sourceURL: URL) throws -> UserProfile {
        let profileHTML = firstCapture(pattern: #"<table\b[^>]*class=["']?main["']?[^>]*>([\s\S]*?)</table>"#, in: html) ?? html
        let rows = matches(pattern: #"<tr\b([^>]*)>([\s\S]*?)</tr>"#, in: profileHTML)

        var sections: [UserProfileSection] = []
        var currentSectionIndex: Int?
        var avatarURL: URL?
        var smilies: [UserProfileSmiley] = []
        var actions: [UserProfileAction] = []

        for row in rows {
            let attributes = row.captures[0]
            let content = row.captures[1]
            let className = attribute(named: "class", in: attributes)

            if className.contains("cBackHeader") {
                let title = cleanText(content)
                guard !title.isEmpty else { continue }
                sections.append(UserProfileSection(id: stableID("section", title, "\(sections.count)"), title: title, fields: []))
                currentSectionIndex = sections.indices.last
                continue
            }

            guard className.contains("profil") else { continue }
            let cells = parseCells(in: content)
            if avatarURL == nil, let avatar = extractAvatarURL(from: content, sourceURL: sourceURL) {
                avatarURL = avatar
            }
            let rowSmilies = extractSmilies(from: content, sourceURL: sourceURL)
            if !rowSmilies.isEmpty {
                smilies.append(contentsOf: rowSmilies.filter { candidate in
                    !smilies.contains(where: { $0.id == candidate.id })
                })
            }

            guard let sectionIndex = currentSectionIndex else { continue }
            let sectionTitle = sections[sectionIndex].title

            if let fullWidthCell = cells.first(where: { $0.className.contains("profilCase3") && $0.attributes.localizedCaseInsensitiveContains("colspan") }) {
                if let action = action(from: fullWidthCell.rawHTML, sectionTitle: sectionTitle, sourceURL: sourceURL) {
                    actions.append(action)
                }
                continue
            }

            guard
                let titleCell = cells.first(where: { $0.className.contains("profilCase2") }),
                let valueCell = cells.first(where: { $0.className.contains("profilCase3") })
            else {
                continue
            }

            let title = cleanTitle(titleCell.rawHTML)
            guard !title.isEmpty else { continue }

            let rawValue = cleanText(valueCell.rawHTML)
            let value = rawValue.isEmpty ? "Non renseigné" : rawValue
            let linkURL = firstHref(in: valueCell.rawHTML).flatMap { resolvedURL(from: $0, sourceURL: sourceURL) }
            let field = UserProfileField(
                id: stableID("field", sectionTitle, title),
                title: title,
                value: value,
                url: linkURL,
                isPlaceholder: rawValue.isEmpty
            )

            if linkURL != nil, title.localizedCaseInsensitiveContains("Configuration") {
                actions.append(UserProfileAction(
                    id: stableID("action", "configuration", linkURL?.absoluteString ?? title),
                    title: title,
                    subtitle: nil,
                    url: linkURL!,
                    kind: .configuration
                ))
            } else {
                sections[sectionIndex].fields.append(field)
            }
        }

        sections.removeAll { $0.fields.isEmpty }

        let allFields = sections.flatMap(\.fields)
        let pseudo = value(for: "Pseudo", in: allFields) ?? ""
        let status = value(for: "Statut", in: allFields)
        let summary = summaryItems(from: allFields)

        guard !sections.isEmpty || !pseudo.isEmpty || avatarURL != nil || !smilies.isEmpty else {
            throw UserProfileLoadingError.invalidProfile
        }

        return UserProfile(
            pseudo: pseudo,
            status: status,
            avatarURL: avatarURL,
            summary: summary,
            sections: sections,
            personalSmilies: smilies,
            actions: unique(actions)
        )
    }

    private static func summaryItems(from fields: [UserProfileField]) -> [UserProfileSummaryItem] {
        [
            ("Messages", "Nombre de messages postés", "text.bubble"),
            ("Arrivée", "Date d'arrivée sur le forum", "calendar"),
            ("Dernier", "Date du dernier message", "clock")
        ].compactMap { title, key, image in
            guard let value = value(for: key, in: fields), !value.isEmpty else { return nil }
            return UserProfileSummaryItem(id: key, title: title, value: value, systemImage: image)
        }
    }

    private static func value(for title: String, in fields: [UserProfileField]) -> String? {
        fields.first { $0.title.localizedCaseInsensitiveContains(title) && !$0.isPlaceholder }?.value
    }

    private static func unique(_ actions: [UserProfileAction]) -> [UserProfileAction] {
        var seen: Set<String> = []
        return actions.filter { action in
            seen.insert(action.id).inserted
        }
    }

    private static func parseCells(in rowHTML: String) -> [Cell] {
        matches(pattern: #"<td\b([^>]*)>([\s\S]*?)</td>"#, in: rowHTML).map { match in
            Cell(className: attribute(named: "class", in: match.captures[0]), attributes: match.captures[0], rawHTML: match.captures[1])
        }
    }

    private static func action(from html: String, sectionTitle: String, sourceURL: URL) -> UserProfileAction? {
        guard let href = firstHref(in: html), let url = resolvedURL(from: href, sourceURL: sourceURL) else { return nil }
        let text = cleanText(html)
        guard !text.isEmpty else { return nil }
        let section = sectionTitle.lowercased()
        let lowerText = text.lowercased()

        let kind: UserProfileAction.Kind
        if lowerText.contains("message privé") {
            kind = .privateMessage
        } else if lowerText.contains("tous ses messages") {
            kind = .allMessages
        } else if lowerText.contains("liste de contacts") {
            kind = .addContact
        } else if section.contains("transaction") || lowerText.contains("transaction") {
            kind = .transaction
        } else {
            kind = .link
        }

        return UserProfileAction(
            id: stableID("action", kind.systemKey, url.absoluteString),
            title: text,
            subtitle: sectionTitle,
            url: url,
            kind: kind
        )
    }

    private static func extractAvatarURL(from html: String, sourceURL: URL) -> URL? {
        guard
            let avatarBlock = firstCapture(pattern: #"<div\b[^>]*class=["']?avatar_center["']?[^>]*>([\s\S]*?)</div>"#, in: html),
            let src = firstImageSource(in: avatarBlock)
        else {
            return nil
        }
        return resolvedURL(from: src, sourceURL: sourceURL)
    }

    private static func extractSmilies(from html: String, sourceURL: URL) -> [UserProfileSmiley] {
        guard html.localizedCaseInsensitiveContains("smilie perso") || html.localizedCaseInsensitiveContains("/images/perso/") else {
            return []
        }

        return matches(pattern: #"((?:\[:[^\]]+\])?)\s*<img\b([^>]*)>"#, in: html).compactMap { match in
            let rawCode = cleanText(match.captures[0])
            let imageAttributes = match.captures[1]
            guard
                let src = attributeOptional(named: "src", in: imageAttributes),
                src.contains("/images/perso/"),
                let url = resolvedURL(from: src, sourceURL: sourceURL)
            else {
                return nil
            }
            let alt = attributeOptional(named: "alt", in: imageAttributes)
            let title = attributeOptional(named: "title", in: imageAttributes) ?? alt
            let code = rawCode.isEmpty
                ? title.map { "[:\($0)]" } ?? url.lastPathComponent
                : rawCode
            return UserProfileSmiley(id: stableID("smiley", code, url.absoluteString), code: code, imageURL: url, title: title)
        }
    }

    private static func firstHref(in html: String) -> String? {
        firstCapture(pattern: #"<a\b[^>]*href=["']([^"']+)["']"#, in: html)
    }

    private static func firstImageSource(in html: String) -> String? {
        firstCapture(pattern: #"<img\b[^>]*src=["']([^"']+)["']"#, in: html)
    }

    private static func cleanTitle(_ html: String) -> String {
        cleanText(html)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }

    private static func cleanText(_ html: String) -> String {
        let withBreaks = html
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</div>"#, with: "\n", options: .regularExpression)
        let withoutTags = withBreaks.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return decodeEntities(withoutTags)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        for match in matches(pattern: #"&#(x?[0-9A-Fa-f]+);"#, in: result).reversed() {
            let token = match.captures[0]
            let scalarValue: UInt32?
            if token.lowercased().hasPrefix("x") {
                scalarValue = UInt32(token.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(token, radix: 10)
            }
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue), let range = Range(match.range, in: result) else {
                continue
            }
            result.replaceSubrange(range, with: String(Character(scalar)))
        }
        return result
    }

    private static func resolvedURL(from rawURL: String, sourceURL: URL) -> URL? {
        if let absolute = URL(string: decodeEntities(rawURL)), absolute.scheme != nil {
            return absolute
        }
        let baseURL = URL(string: k.forumURL()) ?? sourceURL
        return URL(string: decodeEntities(rawURL), relativeTo: baseURL)?.absoluteURL
    }

    private static func attribute(named name: String, in attributes: String) -> String {
        attributeOptional(named: name, in: attributes) ?? ""
    }

    private static func attributeOptional(named name: String, in attributes: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(pattern: #"\b\#(escaped)\s*=\s*["']([^"']*)["']"#, in: attributes)
    }

    private static func firstCapture(pattern: String, in text: String, captureIndex: Int = 0) -> String? {
        matches(pattern: pattern, in: text).first?.captures[safe: captureIndex]
    }

    private static func matches(pattern: String, in text: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { match in
            let captures = (1..<match.numberOfRanges).map { index -> String in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
            return RegexMatch(range: match.range, captures: captures)
        }
    }

    private static func stableID(_ parts: String...) -> String {
        parts.joined(separator: "|")
    }
}

private struct RegexMatch {
    let range: NSRange
    let captures: [String]
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension UserProfileAction.Kind {
    var systemKey: String {
        switch self {
        case .privateMessage:
            return "privateMessage"
        case .allMessages:
            return "allMessages"
        case .addContact:
            return "addContact"
        case .transaction:
            return "transaction"
        case .configuration:
            return "configuration"
        case .link:
            return "link"
        }
    }
}

@Observable
@MainActor
final class UserProfileViewModel {
    var profile: UserProfile?
    var isLoading = false
    var errorMessage: String?

    private let profileURL: URL
    private let service: any UserProfileServicing

    init(profileURL: URL, service: any UserProfileServicing = UserProfileService()) {
        self.profileURL = profileURL
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            profile = try await service.fetchProfile(url: profileURL)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

struct UserProfileView: View {
    private struct SafariDestination: Identifiable {
        let id = UUID()
        let url: URL
    }

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: UserProfileViewModel
    @State private var didLoad = false
    @State private var safariDestination: SafariDestination?

    private let profileURL: URL
    private let quickActions: UserProfileQuickActions?

    init(
        profileURL: URL,
        quickActions: UserProfileQuickActions? = nil,
        service: any UserProfileServicing = UserProfileService()
    ) {
        self.profileURL = profileURL
        self.quickActions = quickActions
        _viewModel = State(initialValue: UserProfileViewModel(profileURL: profileURL, service: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile = viewModel.profile {
                    profileContent(profile)
                } else if viewModel.isLoading {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(errorMessage)
                } else {
                    loadingView
                }
            }
            .navigationTitle(viewModel.profile?.displayName ?? "Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        safariDestination = SafariDestination(url: profileURL)
                    } label: {
                        Label("Ouvrir dans Safari", systemImage: "safari")
                    }
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Label("Actualiser", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .sheet(item: $safariDestination) { destination in
                UserProfileSafariView(url: destination.url)
                    .ignoresSafeArea()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Chargement du profil...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Profil indisponible", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Réessayer") {
                Task { await viewModel.load() }
            }
            .hfrGlassButton(prominent: true)
        }
    }

    private func profileContent(_ profile: UserProfile) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                UserProfileHeaderView(profile: profile, quickActions: quickActions)

                ForEach(profile.sections) { section in
                    UserProfileSectionView(section: section, openURL: openInSafari)
                }

                if !profile.personalSmilies.isEmpty {
                    UserProfileSmiliesView(smilies: profile.personalSmilies)
                }

                if !profile.actions.isEmpty {
                    UserProfileActionsView(actions: profile.actions, openURL: openInSafari)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func openInSafari(_ url: URL) {
        safariDestination = SafariDestination(url: url)
    }
}

private struct UserProfileSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct UserProfileHeaderView: View {
    let profile: UserProfile
    let quickActions: UserProfileQuickActions?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                UserProfileAvatarView(url: profile.avatarURL, width: 98, height: 70)

                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    if let status = profile.status, !status.isEmpty {
                        Label(status, systemImage: "person.text.rectangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if !profile.summary.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: min(profile.summary.count, 3)), alignment: .leading, spacing: 10) {
                    ForEach(profile.summary) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(item.title, systemImage: item.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(item.value)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 8))
                    }
                }
            }

            if let quickActions {
                UserProfileQuickActionsView(actions: quickActions)
            }
        }
        .padding(16)
        .hfrGlassSurface(in: .rect(cornerRadius: 18))
    }
}

private struct UserProfileQuickActionsView: View {
    let actions: UserProfileQuickActions

    private var canToggleLists: Bool {
        actions.authorName?.isEmpty == false
    }

    var body: some View {
        HStack(spacing: 10) {
            if let privateMessageURL = actions.privateMessageURL {
                quickActionButton(title: "MP", systemImage: "message") {
                    actions.onPrivateMessage(privateMessageURL)
                }
            }

            if canToggleLists, let authorName = actions.authorName {
                quickActionButton(
                    title: actions.isWhitelisted ? "Retirer WL" : "Ajouter WL",
                    systemImage: actions.isWhitelisted ? "heart.slash" : "heart"
                ) {
                    actions.onWhitelist(authorName)
                }

                quickActionButton(
                    title: actions.isBlacklisted ? "Retirer BL" : "Ajouter BL",
                    systemImage: actions.isBlacklisted ? "hand.raised.slash" : "hand.raised",
                    role: actions.isBlacklisted ? nil : .destructive
                ) {
                    actions.onBlacklist(authorName)
                }
            }
        }
    }

    private func quickActionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .hfrGlassButton()
    }
}

private struct UserProfileAvatarView: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .padding(min(width, height) * 0.12)
    }
}

private struct UserProfileActionsView: View {
    let actions: [UserProfileAction]
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(actions) { action in
                    Button {
                        openURL(action.url)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.callout.weight(.semibold))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .hfrGlassButton()
                }
            }
        }
    }
}

private struct UserProfileSmiliesView: View {
    let smilies: [UserProfileSmiley]
    @State private var favoriteCodes: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Smilies persos", systemImage: "face.smiling")
                    .font(.headline)
                Spacer()
                Text("\(smilies.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                ForEach(smilies) { smiley in
                    VStack(spacing: 8) {
                        AsyncImage(url: smiley.imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(height: 42)
                        .frame(maxWidth: .infinity)

                        Text(smiley.code)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .textSelection(.enabled)

                        Button {
                            toggleFavorite(smiley)
                        } label: {
                            let isFavorite = favoriteCodes.contains(smiley.code)
                            Label(isFavorite ? "Retirer" : "Favori", systemImage: isFavorite ? "star.slash" : "star")
                                .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.background, in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
                }
            }
        }
        .padding(14)
        .hfrGlassSurface(in: .rect(cornerRadius: 18))
        .onAppear(perform: refreshFavorites)
    }

    private func refreshFavorites() {
        favoriteCodes = Set(smilies.map(\.code).filter(ReplySmileyCacheBridge.isFavoriteFromApp))
    }

    private func toggleFavorite(_ smiley: UserProfileSmiley) {
        let add = !favoriteCodes.contains(smiley.code)
        guard ReplySmileyCacheBridge.updateAppFavorite(
            code: smiley.code,
            imageURL: smiley.imageURL.absoluteString,
            add: add
        ) else {
            return
        }

        if add {
            favoriteCodes.insert(smiley.code)
        } else {
            favoriteCodes.remove(smiley.code)
        }
        AppHaptics.impact(.light)
    }
}

private struct UserProfileSectionView: View {
    let section: UserProfileSection
    let openURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(section.fields.enumerated()), id: \.element.id) { index, field in
                    UserProfileFieldRow(field: field, openURL: openURL)
                    if index < section.fields.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.background, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
        }
    }
}

private struct UserProfileFieldRow: View {
    let field: UserProfileField
    let openURL: (URL) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(field.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 130, alignment: .leading)

            if let url = field.url {
                Button {
                    openURL(url)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(field.value)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        Image(systemName: "arrow.up.forward")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            } else {
                Text(field.value)
                    .foregroundStyle(field.isPlaceholder ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

#Preview("Profil") {
    UserProfileView(profileURL: URL(string: "https://forum.hardware.fr/hfr/profil-802171.htm")!)
}
