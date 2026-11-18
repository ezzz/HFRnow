import HFRModels
import SwiftUI
import UIKit

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsListView, ForumTopicsPaginationBar) @ 87fe0d1c and HFRswift/Swift/Favorites.swift
// (FavoritesListView) @ 2440d79; the section title opens its category (`Favorites.swift:344-372` @ 87fe0d1c). Differences: « page x / y »
// (« y+ » while HFR's pager gives a lower bound, no « last » then; GAP-024, #980); the sub-forum menu and the filter are `ForumScopeBar`
// (GAP-022, 023). LOT-185: the pager is the system bottom bar (`PagerToolbar`), the store-problem strip a `safeAreaBar`; GAP row pending
// #545. #770: "+" is hidden, not greyed, when the account cannot post (legacy `.disabled`, `MainWindow.swift:842` @ 87fe0d1c); no haptic
// on refresh (`:382`; no haptics caller yet).
// List look (#803): one rounded block per section, flat rows, highlights as pills (`RowTint`), as legacy (`Favorites.swift:429, 738`,
// `MainWindow.swift:738-740`, `Common.swift:3677-3684` @ 87fe0d1c). Differences: Favoris and Drapeaux (legacy's one
// Favoris view, `vos_sujets` 0 or 1) pill only super favourites, as legacy; the category lists pill every flagged row, as legacy's
// `MainWindow` (GAP-027, GAP-227). #1073: the inset-grouped style is explicit, as Catégories and Messages. Legacy sets no style
// (`Favorites.swift:666`, `MainWindow.swift:663` @ 87fe0d1c) and paints its palette behind the list (`.scrollContentBackground(.hidden)`,
// `Favorites.swift:744-745`, `MainWindow.swift:789-790`); its iPad look is not measured (87fe0d1c does not build). Here the automatic
// style was a plain list in an iPad column (measured), unlike Catégories and Messages; the iPad choice waits on #648 (GAP-1073).
// #1107: that style is the classic look of `listLook`; « Lignes denses » draws the rows without the card (`DenseListLook`).
/// The middle column: the topics of the selected source, with pagination for forums.
struct TopicListView: View {
    let model: TopicListModel
    @Binding var selection: TopicSummary?
    /// The post filter, offered on a favourite's context menu (LOT-114); nil hides the entry.
    var filtering: FilteredPostsModel?
    /// The current account's composer (LOT-089); nil when logged out, which hides "Nouveau sujet".
    var composer: ComposerServices?
    /// Opens a row's topic at a page its menu names (LOT-125); nil hides those entries.
    var open: ((TopicSummary, TopicOpening) -> Void)?
    /// The sub-forum menu and the Tous / Favoris / Suivis / Lus filter of a forum list; nil on flags and favourites.
    var scope: ForumScope?
    /// Favoris: opens the category a section title names (legacy `headerTitleView`, `Favorites.swift:344-372` @ 87fe0d1c).
    var openCategory: ((TopicSource) -> Void)?
    /// How the title shows: a large title that becomes the pill on Favoris, the pill on the lists a forum row pushes (#977, #978).
    var titleStyle: ScreenTitleStyle = .pill
    /// The account button after the back button of a pushed list (`MainWindow.swift:803-818` @ 87fe0d1c, #425); off on the Favoris root.
    var showsAccountMenu = false
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?
    @State private var titleVisibility = TitleVisibility()
    @State private var newTopic: ReplyComposerModel?
    /// The row whose "Page numéro…" prompt is shown.
    @State private var pagePrompt: TopicSummary?
    @State private var pageText = ""

    var body: some View {
        let loader = counting(.body, model.loader, title: titleVisibility)
        List(selection: $selection) {
            // #1107: every row of the list takes its look, once for the whole content.
            Group {
                if titleStyle == .largeThenPill {
                    ScreenLargeTitle(title: model.source.navigationTitle, visibility: titleVisibility)
                }
                if let scope { ForumScopeBar(model: model, scope: scope) }
                if loader.value != nil {
                    ForEach(model.displayedGroups) { group in
                        if let title = group.title {
                            Section {
                                if !group.isCollapsed { rows(group.topics) }
                            } header: {
                                header(group, title: title).themedSectionHeader()
                            }
                        } else {
                            rows(group.topics)
                        }
                    }
                }
            }
            .listLookRows()
        }
        .listLook() // explicit: the automatic style is a plain list in an iPad column (#1073)
        .screenTitle(model.source.navigationTitle, style: titleStyle, visibility: titleVisibility)
        .seasonalScrollTracking()
        .overlay { overlay(loader) }
        .safeAreaBar(edge: .top) {
            if let problem = model.favorites?.storeProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .safeAreaInset(edge: .top) {
            // Content-layer cards: they push the list down, so they stay materials in an inset (LOT-185).
            VStack(spacing: 8) {
                if let confirmation = model.sentConfirmation {
                    TopicSentBanner(text: confirmation, close: model.clearSentConfirmation)
                }
                if let error = loader.error, loader.value != nil {
                    LoadFailureBanner(error: error, retry: model.retry)
                }
            }
        }
        .pagerBar(PageBar.isShown(for: loader.value, source: model.source) ? PageBar(model: model).pager : nil)
        .toolbar {
            if showsAccountMenu { ToolbarItem(placement: AccountMenuButton.placement) { AccountMenuButton() } }
            // Legacy trailing group: "+" then refresh (`MainWindow.swift:835-846` @ 87fe0d1c). SwiftHFR has no cover-screen layout,
            // so the refresh never moves to the bottom bar (`:849-851`).
            ToolbarItemGroup(placement: .topBarTrailing) {
                // « Non lus / Tous » (#1058): a deliberate addition, only on the Favoris lists.
                if let favorites = model.favorites { FavoritesUnreadFilterButton(options: favorites) }
                if let composer, let target = model.newTopicTarget {
                    Button { newTopic = ReplyComposerModel(composing: .newTopic(target), services: composer) } label: {
                        Label("Nouveau sujet", systemImage: "plus")
                    }
                }
                Button { Task { await model.refresh() } } label: {
                    Label { Text("Actualiser") } icon: { ToolbarRefreshIcon(isLoading: model.loader.isLoading) }
                }
                .disabled(!model.canRefresh)
            }
        }
        .sheet(item: $newTopic) { composer in
            ReplyComposerView(model: composer) { reason in
                Task { await model.newTopicDidClose(reason) }
            }
        }
        .onChange(of: model.sentConfirmation) { _, text in
            // The banner is not on the focused element: say what HFR confirmed, once, when it arrives.
            if let text { AccessibilityNotification.Announcement(text).post() }
        }
        .refreshable { await model.refresh() }
        .task(id: model.wantedFilter) { await model.onAppear() }
        .alert(
            "Action impossible", isPresented: Binding(get: { model.actionFailure != nil }, set: { if !$0 { model.clearActionFailure() } })
        ) {
            // The row is captured here: the alert clears the model's state before a button's action runs (LOT-087).
            if let topic = model.retryableRemoval {
                Button("Réessayer") { Task { await model.removeFlag(topic) } }
                Button("Annuler", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(model.actionFailure ?? "")
        }
        .alert(
            "Page numéro", isPresented: Binding(get: { pagePrompt != nil }, set: { if !$0 { pagePrompt = nil } }),
            presenting: pagePrompt
        ) { topic in
            TextField("Page", text: $pageText).keyboardType(.numberPad)
            Button("Annuler", role: .cancel) {}
            Button("Aller") {
                let number = Int(pageText.trimmingCharacters(in: .whitespaces)) ?? 0
                if let opening = TopicQuickActions.page(number, of: topic) { open?(topic, opening) }
            }
        } message: { topic in
            Text("Entre 1 et \(topic.pageCount)")
        }
    }

    /// Whether a flagged row is a pill: not in Favoris and Drapeaux, legacy's one Favoris view (`Favorites.swift:1134` @ 87fe0d1c).
    static func flagPills(for source: TopicSource) -> Bool { !source.isFavoritesList }

    /// The tint of a row: the super favourite's orange or the flag's colour, nil on the selected row so the iPad selection shows.
    /// `flagPills` false (Favoris) leaves only the super favourite a pill: legacy tints no other row there (`Favorites.swift:1134`
    /// @ 87fe0d1c); the default row shows no flag colour there.
    static func rowTint(
        topic: TopicSummary, showsFlag: Bool = true, isSuperFavorite: Bool, isSelected: Bool, flagPills: Bool = true
    ) -> RowTint? {
        let flag = showsFlag && flagPills ? topic.flag : nil
        guard let accent = TopicRowCues.accent(flag: flag, isSuperFavorite: isSuperFavorite, isSelected: isSelected) else {
            return nil
        }
        return RowTint(tint: accent.color, weight: accent.weight)
    }

    private func rows(_ topics: [TopicSummary]) -> some View {
        ForEach(topics) { topic in
            let isSuper = counting(.row(topic.id), model.isSuperFavorite(topic))
            TopicRowView(
                topic: topic, isSuperFavorite: isSuper, markedRead: model.isMarkedRead(topic), showsFlag: model.hasFlag(topic),
                flagIsTinted: TopicListView.flagPills(for: model.source)
            )
                .themedRowText().listLookRow(isSelected: selection == topic)
                .tag(topic)
                .rowPill(
                    TopicListView.rowTint(
                        topic: topic, showsFlag: model.hasFlag(topic), isSuperFavorite: isSuper, isSelected: selection == topic,
                        flagPills: TopicListView.flagPills(for: model.source)
                    ),
                    isSuperFavorite: isSuper
                )
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if model.canMarkRead(topic) {
                        Button { model.markRead(topic) } label: { Label("Lu", systemImage: "checkmark") }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if model.canRemoveFlag(topic) { removeButton(topic) }
                }
                .accessibilityActions {
                    // The swipes, for VoiceOver (a swipe is not reachable there).
                    if model.canMarkRead(topic) { Button("Lu") { model.markRead(topic) } }
                    if model.canRemoveFlag(topic), !model.isRemovingFlag(topic) {
                        Button("Supprimer") { Task { await model.removeFlag(topic) } }
                    }
                }
                .contextMenu { menu(topic, isSuper: isSuper) }
        }
    }

    /// "Supprimer" (legacy trailing swipe and menu entry): "Suppression…" and disabled while the removal is in flight.
    private func removeButton(_ topic: TopicSummary) -> some View {
        let removing = model.isRemovingFlag(topic)
        return Button(role: .destructive) {
            Task { await model.removeFlag(topic) }
        } label: {
            Label(removing ? "Suppression…" : "Supprimer", systemImage: removing ? "hourglass" : "trash")
        }
        .disabled(removing)
    }

    /// The row menu, in legacy order: the quick actions, then Lu, super favourite, Supprimer and the post filter.
    @ViewBuilder
    private func menu(_ topic: TopicSummary, isSuper: Bool) -> some View {
        if let open {
            if let opening = TopicQuickActions.firstPage(of: topic) {
                Button("Première page", systemImage: "backward.end") { open(topic, opening) }
            }
            if let opening = TopicQuickActions.lastPage(of: topic) {
                Button("Dernière page", systemImage: "forward.end") { open(topic, opening) }
            }
            if let opening = TopicQuickActions.lastReply(of: topic, in: model.source) {
                Button("Dernière réponse", systemImage: "text.append") { open(topic, opening) }
            }
            Button("Page numéro…", systemImage: "number") {
                pageText = "\(TopicQuickActions.suggestedPage(of: topic))"
                pagePrompt = topic
            }
        }
        if let link = TopicQuickActions.link(of: topic) {
            Button("Copier le lien", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = link.absoluteString
                AccessibilityNotification.Announcement("Lien copié").post()
            }
        }
        Divider()
        if model.canMarkRead(topic) {
            Button("Lu", systemImage: "checkmark") { model.markRead(topic) }
        }
        if let favorites = model.favorites, favorites.canMarkSuperFavorites, topic.topicID != nil {
            Button(isSuper ? "Retirer des super favoris" : "Ajouter aux super favoris", systemImage: "star.circle") {
                Task { await favorites.toggleSuperFavorite(topic) }
            }
        }
        if model.canRemoveFlag(topic) { removeButton(topic) }
        if model.source == .favorites, let filtering, topic.topicID != nil {
            Divider()
            Button { filtering.start(opening: topic) } label: {
                Label("Filtrer les posts", systemImage: "line.3.horizontal.decrease.circle")
            }
            .disabled(filtering.isBusy)
        }
    }

    /// EXPERIMENTAL(denseRows, #905 F): bold section titles in the dense view; nil keeps the default weight.
    private var titleWeight: Font.Weight? { DenseRowFormat.titleWeight(experimental) }

    /// A category header with its topic count and, when the section has topics, the fold chevron (legacy `sectionHeader`).
    private func header(_ group: TopicGroup, title: String) -> some View {
        counting(.header(group.id), HStack {
            if let source = group.opens, let openCategory {
                let speech = TopicRowCues.sectionTitleSpeech(title)
                Button { openCategory(source) } label: { Text(title).foregroundStyle(.primary).sectionTitleWeight(titleWeight) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(speech.label)
                    .accessibilityHint(speech.hint)
                    .accessibilityAddTraits(.isButton)
            } else {
                Text(title).sectionTitleWeight(titleWeight)
            }
            Spacer()
            Text("\(group.topics.count)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityLabel(TopicRowCues.topicCountLabel(group.topics.count))
            if group.isCollapsible, let favorites = model.favorites {
                Button {
                    Task { await favorites.toggleCollapsed(group.id) }
                } label: {
                    Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.isCollapsed ? "Déplier \(title)" : "Plier \(title)")
            }
        }
        .densityHeaderMargin())
    }
}

extension TopicListView {
    @ViewBuilder
    private func overlay(_ loader: ContentLoader<TopicListContent>) -> some View {
        if let content = loader.value {
            if content.isEmpty, let reason = content.emptyReason {
                EmptyListView(reason: reason, refresh: model.refresh)
            } else if model.showsNoUnreadFavorites, let favorites = model.favorites {
                // Nothing unread only when no row is: an unread row inside a folded section is hidden, not absent.
                NoUnreadTopicsView(options: favorites)
            } else if model.allSectionsHidden, let favorites = model.favorites {
                AllSectionsCollapsedView(options: favorites)
            }
        } else if let error = loader.error {
            LoadFailureView(error: error, retry: model.retry)
        } else if loader.isLoading {
            ProgressView("Chargement des sujets")
        }
    }
}

/// Every section is folded and the options hide folded sections (legacy `allSectionsCollapsedState`).
private struct AllSectionsCollapsedView: View {
    let options: FavoritesOptionsModel

    var body: some View {
        ContentUnavailableView {
            Label("Toutes les sections sont repliées", systemImage: "list.bullet.circle")
        } description: {
            Text("La vue filtrée masque les sections repliées.")
        } actions: {
            Button("Afficher les sections repliées") { options.showsCollapsedSections = true }
            Button("Tout déplier") { Task { await options.expandAll() } }
        }
    }
}

private struct EmptyListView: View {
    let reason: EmptyReason
    let refresh: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "tray")
        } description: {
            if let message { Text(message) }
        } actions: {
            Button("Actualiser") { Task { await refresh() } }
        }
    }

    private var title: String {
        switch reason {
        case .nothing: "Aucun sujet"
        case .signInRequired: "Connexion requise"
        case .notice: "Rien à afficher"
        }
    }

    private var message: String? {
        switch reason {
        case .nothing: nil
        case .signInRequired(let notice): notice ?? "Connectez-vous pour voir cette liste."
        case .notice(let notice): notice
        }
    }
}

/// « page x / y » (y+ when HFR's pager gives only a lower bound) with its menu, and the ‹ › pills (#980, as the MP list's). Shown on a
/// paged list of more than one page (legacy `shouldShowPagination`, `MainWindow.swift:407-409` @ 87fe0d1c).
@MainActor private struct PageBar {
    let model: TopicListModel
    static func isShown(for content: TopicListContent?, source: TopicSource) -> Bool {
        source.isPaged && content.map { $0.page > 1 || $0.hasNext } == true
    }
    var pager: PagerToolbar {
        PagerToolbar(
            first: .init(enabled: model.canGoToPrevious) { Task { await model.goToFirstPage() } },
            previous: .init(enabled: model.canGoToPrevious) { Task { await model.goToPreviousPage() } },
            next: .init(enabled: model.canGoToNext) { Task { await model.goToNextPage() } },
            last: .init(enabled: model.canGoToLast) { Task { await model.goToLastPage() } },
            status: .pageOf(model.currentPage, model.pageCount, isExact: model.pageCountIsExact),
            jump: { jump in Task { await model.perform(jump) } }, isLoading: model.loader.isLoading
        )
    }
}

/// HFR's confirmation of a new topic, above the list.
private struct TopicSentBanner: View {
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

/// `arrow.clockwise` that spins while loading (legacy `ToolbarRefreshIcon`, `Common.swift:393-404` @ 87fe0d1c). The button's label is
/// never swapped for a `ProgressView`: legacy found that makes the Liquid Glass toolbar morph balloon on the Duo inner display.
struct ToolbarRefreshIcon: View {
    let isLoading: Bool

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .symbolEffect(.rotate, options: .repeating, isActive: isLoading)
    }
}
