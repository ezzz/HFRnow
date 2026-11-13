import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MPListView.swift (MPListView) @ 2440d79. Differences: paged (legacy shows page 1 only); the conversation opens
// in the reader column (GAP-110); the "MP" / "MP multiples" switch is new (LOT-171).
// LOT-185: the pager (legacy shows page 1 only, no counterpart) is the system bottom bar (`PagerToolbar`); the switch is a
// `safeAreaBar` without fill; GAP row pending #545.
/// The Messages list: the member's conversations, paged, with pull to refresh. A tap selects a row; the reader shows it.
/// "Nouveau message" opens the new-MP composer (LOT-128) when an account is current and the page links to the form.
struct MessageListView: View {
    let model: MessageListModel
    /// The current account's composer; nil when logged out, which hides "Nouveau message".
    let composer: ComposerServices?
    @State private var newMessage: ReplyComposerModel?

    var body: some View {
        let loader = model.loader
        List(selection: Binding(get: { model.selected }, set: { model.selected = $0 })) {
            if loader.value != nil {
                ForEach(model.visibleThreads) { thread in
                    MessageRowView(
                        thread: thread, isUnread: model.isUnread(thread), isSelected: model.selected == thread,
                        flagLabel: model.flagLabel(for: thread)
                    )
                    .tag(thread)
                }
            }
        }
        .listStyle(.insetGrouped) // explicit: the row tint's base colour is the grouped one (#570)
        .densityListMargins()
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .seasonalScrollTracking()
        .overlay { overlay(loader) }
        .safeAreaBar(edge: .top) {
            if model.showsSegmentSwitch { MessageSegmentSwitch(model: model) }
        }
        .safeAreaInset(edge: .top) {
            // Both can show: a message HFR confirmed stays confirmed when the reload after it fails.
            VStack(spacing: 8) {
                if let confirmation = model.sentConfirmation {
                    MessageSentBanner(text: confirmation, close: model.clearSentConfirmation)
                }
                if let error = loader.error, loader.value != nil {
                    LoadFailureBanner(error: error, retry: model.retry)
                }
            }
        }
        .onChange(of: model.sentConfirmation) { _, text in
            // The banner is not on the focused element: say what HFR confirmed, once, when it arrives.
            if let text { AccessibilityNotification.Announcement(text).post() }
        }
        .task(id: model.sentConfirmation) {
            guard model.sentConfirmation != nil else { return }
            // Long enough to read, like the reply banner (LOT-084); cancelled when another confirmation replaces it.
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            model.clearSentConfirmation()
        }
        .pagerBar(loader.value.map { $0.page > 1 || $0.hasNext } == true ? MessagePageBar(model: model).pager : nil)
        .toolbar {
            if let composer, let target = model.newMessageTarget {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newMessage = ReplyComposerModel(composing: .newPrivateMessage(target), services: composer)
                    } label: {
                        Label("Nouveau message", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .sheet(item: $newMessage) { composer in
            ReplyComposerView(model: composer) { reason in
                Task { await model.newMessageDidClose(reason, subject: composer.subject) }
            }
        }
        .refreshable { await model.refresh() }
        .task { await model.onAppear() }
        // Separate from the list's load, which never waits for MPStorage (LOT-130): the flags appear when the copy is read.
        .task { await model.mpStorage?.start() }
        .alert(
            "Action impossible", isPresented: Binding(get: { model.actionFailure != nil }, set: { if !$0 { model.actionFailure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionFailure ?? "")
        }
    }

    @ViewBuilder
    private func overlay(_ loader: ContentLoader<MessageListContent>) -> some View {
        if let content = loader.value {
            if model.isSearchingSegment, model.visibleThreads.isEmpty {
                ProgressView("Recherche des \(model.segment.title)")
            } else if model.visibleThreads.isEmpty {
                EmptyMessagesView(
                    reason: content.emptyReason ?? .nothing, segment: model.display == .split ? model.segment : nil,
                    refresh: model.refresh
                )
            }
        } else if let error = loader.error {
            LoadFailureView(error: error, retry: model.retry)
        } else if loader.isLoading {
            ProgressView("Chargement des messages")
        }
    }
}

/// HFR's confirmation of a new private message or of a conversation marked unread, above the list.
private struct MessageSentBanner: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            Text(text).scaledFont(.subheadline)
            Spacer()
            Button(action: close) { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                .accessibilityLabel("Masquer")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

private struct EmptyMessagesView: View {
    let reason: EmptyReason
    /// The switch position when the list is split: the page may hold none of it though later pages exist.
    let segment: MPSegment?
    let refresh: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        } actions: {
            Button("Actualiser") { Task { await refresh() } }
        }
    }

    private var title: String {
        switch reason {
        case .nothing:
            switch segment {
            case .group: "Aucun MP multiple"
            case .oneToOne: "Aucun MP individuel"
            case nil: "Aucun message privé"
            }
        case .signInRequired: "Connexion requise"
        case .notice: "Rien à afficher"
        }
    }

    private var symbol: String {
        if case .signInRequired = reason { "lock" } else { "envelope" }
    }

    private var message: String? {
        switch reason {
        case .nothing: nil
        case .signInRequired(let notice): notice ?? "Connectez-vous pour lire vos messages privés."
        case .notice(let notice): notice
        }
    }
}

/// Previous / next controls. Only "a next page exists" is known: the pager is a window, never a total.
@MainActor private struct MessagePageBar {
    let model: MessageListModel

    var pager: PagerToolbar {
        PagerToolbar(
            first: .init(enabled: model.canGoToPrevious) { Task { await model.goToFirstPage() } },
            previous: .init(enabled: model.canGoToPrevious) { Task { await model.goToPreviousPage() } },
            next: .init(enabled: model.canGoToNext) { Task { await model.goToNextPage() } },
            last: nil,
            status: model.loader.isLoading ? .loading : .page(model.currentPage)
        )
    }
}

/// The "MP" / "MP multiples" switch of the split list, each segment with its own unread count (page-bounded).
private struct MessageSegmentSwitch: View {
    let model: MessageListModel

    var body: some View {
        Picker("Type de MP", selection: Binding(get: { model.segment }, set: { segment in
            model.chooseSegment(segment)
            Task { await model.searchForSegment() }
        })) {
            ForEach(MPSegment.allCases, id: \.self) { segment in
                let unread = model.unreadCount(in: segment)
                Text(unread > 0 ? "\(segment.title) (\(unread))" : segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
