import HFRParsing
import SwiftUI

// Port of HFRswift/Swift/UserProfileView.swift (GAP-167: UserProfileView, UserProfileHeaderView, UserProfileQuickActionsView,
// UserProfileSectionView, UserProfileFieldRow, UserProfileSmiliesView, UserProfileActionsView) @ 2440d79. Differences: images
// through the reader's cookie-less fetcher and image policy, not `AsyncImage`; no smiley favourite toggle (LOT-104); a
// list instead of cards (LOT-116 spec).
/// A member's public profile in a sheet (LOT-116): header (avatar, pseudo, status, figures), the page's sections, personal
/// smileys and the page's link rows. Every text the member wrote is shown verbatim, never read as Markdown or HTML.
struct UserProfileView: View {
    let model: UserProfileModel
    let services: ReaderServices
    @State private var external: ProfileExternalLink?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await model.reload() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                            .disabled(model.isLoading)
                    }
                }
                .task { await model.onAppear() }
                .sheet(item: $external) { link in SafariView(url: link.url).ignoresSafeArea() }
        }
    }

    @ViewBuilder private var content: some View {
        if let profile = model.profile {
            List {
                if let error = model.error {
                    LoadFailureBanner(error: error, retry: model.reload).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                ProfileHeaderSection(profile: profile, fetcher: services.imageFetcher, model: model)
                ForEach(profile.sections) { section in
                    Section(section.title) {
                        ForEach(section.fields) { field in ProfileFieldRow(field: field, open: open) }
                    }
                }
                if !profile.personalSmilies.isEmpty {
                    ProfileSmileysSection(
                        smileys: profile.personalSmilies, fetcher: services.imageFetcher, generation: model.loadGeneration
                    )
                }
                if !profile.actions.isEmpty {
                    Section("Liens") {
                        ForEach(profile.actions) { action in ProfileActionRow(action: action, open: open) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.reload() }
        } else if let error = model.error {
            LoadFailureView(error: error, retry: model.reload)
        } else {
            ProgressView("Chargement du profil…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func open(_ url: URL) {
        switch model.action(forLink: url, defaultBrowser: services.settings.opensLinksInDefaultBrowser()) {
        case .inAppBrowser(let url): external = ProfileExternalLink(url: url)
        case .defaultBrowser(let url): openURL(url)
        case .ignored: break
        }
    }
}

private struct ProfileExternalLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Avatar, pseudo, status, the three figures and the quick actions.
private struct ProfileHeaderSection: View {
    let profile: UserProfile
    let fetcher: ReaderImageFetcher
    let model: UserProfileModel

    var body: some View {
        Section {
            HStack(spacing: 16) {
                ProfileImage(
                    url: profile.avatarURL, fetcher: fetcher, placeholder: "person.crop.circle.fill", generation: model.loadGeneration
                )
                    .frame(width: 98, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: profile.pseudo).scaledFont(.title2).bold().textSelection(.enabled)
                    if let status = profile.status {
                        Label { Text(verbatim: status) } icon: { Image(systemName: "person.text.rectangle") }
                            .scaledFont(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(profile.summary) { item in
                LabeledContent {
                    Text(verbatim: item.value).textSelection(.enabled)
                } label: {
                    Label(item.kind.shortTitle, systemImage: item.kind.symbol)
                }
                .scaledFont(.body)
            }
            // The buttons flip their label; VoiceOver hears the result as it does from the message menu's toast. Attached to a
            // row that is always there: the feedback `Text` appears already holding the first sentence, which no change reports.
            .onChange(of: model.listFeedback) { _, text in
                if let text { AccessibilityNotification.Announcement(text).post() }
            }
            if let recipient = model.privateMessageRecipient {
                Button { model.writePrivateMessage() } label: { Label("Écrire un MP", systemImage: "message") }
                    .accessibilityHint("Message privé à \(recipient)")
            }
            if model.offers(.blocklist) {
                Button { Task { await model.toggle(.blocklist) } } label: {
                    Label(model.isBlocked ? "Retirer de la liste noire" : "Ajouter à la liste noire", systemImage: "hand.raised")
                }
            }
            if model.offers(.allowlist) {
                Button { Task { await model.toggle(.allowlist) } } label: {
                    Label(model.isAllowed ? "Retirer de la love list" : "Ajouter à la love list", systemImage: "heart")
                }
            }
            if let feedback = model.listFeedback {
                Text(feedback).scaledFont(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// One labelled field; a member's link opens in a browser.
private struct ProfileFieldRow: View {
    let field: UserProfileField
    let open: (URL) -> Void

    var body: some View {
        if let url = field.url {
            // The row itself is the button, labelled with its title and value, so VoiceOver activates the link directly.
            let value = field.value.isEmpty ? url.absoluteString : field.value
            Button { open(url) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: field.title).scaledFont(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: value).multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.forward").scaledFont(.caption2).accessibilityHidden(true)
                    }
                    .foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .scaledFont(.body)
            .accessibilityLabel(Text(verbatim: "\(field.title), \(value)"))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: field.title).scaledFont(.subheadline).foregroundStyle(.secondary)
                if field.isPlaceholder {
                    Text("Non renseigné").foregroundStyle(.tertiary)
                } else {
                    Text(verbatim: field.value).textSelection(.enabled)
                }
            }
            .scaledFont(.body)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The member's personal smileys with their codes.
private struct ProfileSmileysSection: View {
    let smileys: [UserProfileSmiley]
    let fetcher: ReaderImageFetcher
    let generation: Int

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                ForEach(smileys) { smiley in
                    VStack(spacing: 8) {
                        ProfileImage(url: smiley.imageURL, fetcher: fetcher, placeholder: "photo", generation: generation)
                            .frame(height: 42)
                            .accessibilityHidden(true)
                        Text(verbatim: smiley.code)
                            .scaledFont(.caption2).monospaced().multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }
        } header: {
            Text("Smilies persos (\(smileys.count))")
        }
    }
}

/// A link row of the page (MP, all messages, transactions, configuration), opened in a browser as legacy did.
private struct ProfileActionRow: View {
    let action: UserProfileAction
    let open: (URL) -> Void

    var body: some View {
        Button { open(action.url) } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: action.title)
                    if let subtitle = action.subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle).scaledFont(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: action.kind.symbol)
            }
        }
        .scaledFont(.body)
    }
}

/// An image of the profile (avatar, smiley) through the reader's cookie-less fetcher: forum hosts only, no third party
/// (LOT-071 policy); the placeholder stays when the policy refuses it or the download fails.
private struct ProfileImage: View {
    let url: URL?
    let fetcher: ReaderImageFetcher
    let placeholder: String
    /// `UserProfileModel.loadGeneration`: part of the task identity, so a reload retries an image that failed.
    let generation: Int
    @State private var state = ProfileImageState<UIImage>()

    var body: some View {
        Group {
            if let image = state.image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: placeholder).resizable().scaledToFit().foregroundStyle(.secondary).padding(8)
            }
        }
        .task(id: ImageTaskID(url: url, generation: generation)) {
            guard state.begin(url: url), let url else { return }
            let loaded = await Self.load(url, fetcher: fetcher)
            state.finish(url: url, loaded: loaded, cancelled: Task.isCancelled)
        }
    }

    private struct ImageTaskID: Equatable {
        let url: URL?
        let generation: Int
    }

    private static func load(_ url: URL, fetcher: ReaderImageFetcher) async -> UIImage? {
        guard let data = try? await fetcher.image(at: url, allowsThirdParty: false).data else { return nil }
        return await Task.detached { UIImage(data: data) }.value
    }
}

extension UserProfileSummaryItem.Kind {
    /// Short label of a figure (legacy `UserProfileSummaryItem` titles: Messages, Arrivée, Dernier).
    var shortTitle: String {
        switch self {
        case .messageCount: "Messages"
        case .joinDate: "Arrivée"
        case .lastMessageDate: "Dernier message"
        }
    }

    /// SF Symbol of a figure (legacy `text.bubble`, `calendar`, `clock`).
    var symbol: String {
        switch self {
        case .messageCount: "text.bubble"
        case .joinDate: "calendar"
        case .lastMessageDate: "clock"
        }
    }
}

extension UserProfileAction.Kind {
    /// SF Symbol of a link row (legacy `UserProfileAction.systemImage`).
    var symbol: String {
        switch self {
        case .privateMessage: "message"
        case .allMessages: "text.bubble"
        case .addContact: "person.badge.plus"
        case .transaction: "arrow.left.arrow.right"
        case .configuration: "desktopcomputer"
        case .link: "link"
        }
    }
}
