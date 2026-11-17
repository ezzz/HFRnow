import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsPaginationBar, `:926-981`) and of the pager of HFRswift/Swift/ForumSearchView.swift
// (`:395-432`) @ 2440d79. Differences: legacy drew its own glass capsule; the iPad sidebar root uses the system bottom bar, the tab bar
/// root (every iPhone, compact iPad) a glass strip inset above the tab bar (#565); GAP row pending #545 (LOT-185).
/// The page controls of a list: system bottom-bar items under the iPad sidebar root (Liquid Glass), a glass strip above the tab bar
/// under the tab bar root (`PagerPlacement`), instead of a hand-built strip with an opaque fill.
struct PagerToolbar {
    /// The first / previous / next / last page actions; a nil action hides its button (the forum list has no "last").
    struct Step {
        let enabled: Bool
        let action: () -> Void
    }

    let first: Step
    let previous: Step
    let next: Step
    let last: Step?
    /// "Page N", « page x / y » with its menu, or a spinner while a page loads.
    let status: Status
    /// Goes to a page chosen in the « page x / y » menu (`Status.pageOf`); nil leaves that pill a plain label.
    var jump: (@MainActor (PagerJump) -> Void)?
    /// A page is loading: the `.pageOf` pill shows a spinner and keeps its place, so the bar does not change shape on each move.
    var isLoading = false

    enum Status {
        case page(Int)
        /// « page x / y » in its own glass pill, left of the ‹ › pills; a tap opens `PagerPageMenu` when `jump` is set (#968, #980).
        case pageOf(Int, Int, isExact: Bool = true)
        case loading
    }

    /// The enabled page steps as named actions, for the list's accessibility actions (#898):
    /// the bar can be hidden, the pages stay reachable.
    var pageActions: [(name: LocalizedStringKey, action: () -> Void)] {
        var actions: [(name: LocalizedStringKey, action: () -> Void)] = []
        if first.enabled { actions.append(("Première page", first.action)) }
        if previous.enabled { actions.append(("Page précédente", previous.action)) }
        if next.enabled { actions.append(("Page suivante", next.action)) }
        if let last, last.enabled { actions.append(("Dernière page", last.action)) }
        return actions
    }

    /// The system bottom-bar items, for the iPad sidebar root (no tab bar, nothing to overlap).
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        // « page x / y »: the pill on the left, then ‹ and › (first and last are in its menu); any other status keeps the
        // classic order. Same five items either way, so the content varies, never the structure.
        let isMenu = usesPageMenu
        ToolbarItemGroup(placement: .bottomBar) {
            if isMenu {
                statusView
            } else {
                Button("Première page", systemImage: "backward.end", action: first.action).disabled(!first.enabled)
                Button("Page précédente", systemImage: "chevron.left", action: previous.action).disabled(!previous.enabled)
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            if isMenu {
                Button("Page précédente", systemImage: "chevron.left", action: previous.action).disabled(!previous.enabled)
            } else {
                statusView
            }
        }
        ToolbarSpacer(isMenu ? .fixed : .flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Page suivante", systemImage: "chevron.right", action: next.action).disabled(!next.enabled)
            if let last, !isMenu {
                Button("Dernière page", systemImage: "forward.end", action: last.action).disabled(!last.enabled)
            }
        }
    }

    private var usesPageMenu: Bool {
        if case .pageOf = status { true } else { false }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .page(let number): Text("Page \(number)").monospacedDigit()
        case .pageOf(let number, let total, let isExact):
            PagerPageMenuPill(current: number, total: total, isExact: isExact, isLoading: isLoading, onJump: jump)
        case .loading: ProgressView().accessibilityLabel("Chargement")
        }
    }

    /// The same controls as a strip, for the layouts with a tab bar. The full row (first/last included) falls back to previous,
    /// status, next when it does not fit (Slide Over, accessibility sizes).
    fileprivate var strip: some View {
        ViewThatFits(in: .horizontal) {
            stripRow(full: true)
            stripRow(full: false)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func stripRow(full: Bool) -> some View {
        if usesPageMenu {
            // The menu carries first and last: the pill on the left, then the two arrow pills.
            HStack {
                statusView
                Spacer()
                Button("Page précédente", systemImage: "chevron.left", action: previous.action).disabled(!previous.enabled)
                Button("Page suivante", systemImage: "chevron.right", action: next.action).disabled(!next.enabled)
            }
        } else {
            classicRow(full: full)
        }
    }

    private func classicRow(full: Bool) -> some View {
        HStack {
            if full { Button("Première page", systemImage: "backward.end", action: first.action).disabled(!first.enabled) }
            Button("Page précédente", systemImage: "chevron.left", action: previous.action).disabled(!previous.enabled)
            Spacer()
            statusView
            Spacer()
            Button("Page suivante", systemImage: "chevron.right", action: next.action).disabled(!next.enabled)
            if full, let last {
                Button("Dernière page", systemImage: "forward.end", action: last.action).disabled(!last.enabled)
            }
        }
    }
}

/// Where a list's pager goes (#565): the system bottom bar of a list inside the iPhone tab bar's TabView lands in the floating
/// tab bar's frame and cannot be used, so the root with a tab bar gets an inset above it. The size class does not tell the roots
/// apart (a Plus or Pro Max iPhone in landscape is regular width WITH the tab bar): `RootNavigationView` says which root it built.
enum PagerPlacement: Equatable {
    case bottomBar
    case inset

    init(rootHasTabBar: Bool) {
        self = rootHasTabBar ? .inset : .bottomBar
    }
}

private struct RootHasTabBarKey: EnvironmentKey {
    /// A screen outside the two roots (a sheet, a preview) assumes the tab bar: a duplicated pager beats a hidden one.
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True under the tab bar root, false under the iPad sidebar root (`RootNavigationView`).
    var rootHasTabBar: Bool {
        get { self[RootHasTabBarKey.self] }
        set { self[RootHasTabBarKey.self] = newValue }
    }
}

/// When a list's pager shows (#898): only once the list is scrolled to its end, so it takes no room above where one reads. A pure
/// rule, so it is tested without a scroll view.
enum PagerVisibility {
    /// How far from the end still counts as the end (rubber band, a half-visible last row's separator).
    static let tolerance: CGFloat = 24

    /// Points left to scroll down. The bottom inset is part of the range on both sides, so the pager's own safe-area bar
    /// appearing does not move the end. Zero or negative: the end is visible (a list shorter than the screen is always there).
    static func distanceFromEnd(offsetY: CGFloat, containerHeight: CGFloat, contentHeight: CGFloat, bottomInset: CGFloat) -> CGFloat {
        contentHeight + bottomInset - containerHeight - offsetY
    }

    /// Whether the bar shows next, given whether it shows now and the bar's measured height: it appears within `tolerance` of the
    /// end and hides only beyond `tolerance + barHeight`, because its own bottom inset can push the distance up by that much
    /// without the offset moving (no height guessed: a taller bar at large text sizes gets a wider dead zone, no flicker).
    /// VoiceOver keeps the bar so the page actions never depend on a scroll position.
    static func isShown(distanceFromEnd: CGFloat, wasShown: Bool = false, barHeight: CGFloat = 0, voiceOver: Bool) -> Bool {
        voiceOver || distanceFromEnd <= tolerance + (wasShown ? barHeight : 0)
    }

    /// The height the bar adds: the larger of its measured strip (tab root) and the extra bottom inset seen while it shows
    /// compared with the last inset seen while it was hidden (system bottom bar, which cannot be measured as a view).
    static func measuredBarHeight(strip: CGFloat, inset: CGFloat, hiddenInset: CGFloat?) -> CGFloat {
        max(strip, hiddenInset.map { max(0, inset - $0) } ?? 0)
    }

    /// What the pager remembers between two scroll geometries.
    struct State: Equatable {
        var atEnd = true
        /// The bottom inset last seen while the bar was really hidden: the baseline its own inset is measured against.
        var hiddenInset: CGFloat?
    }

    /// One step: the new state after a scroll geometry (`distance`, bottom `inset`) and the measured `strip` height.
    static func step(_ state: State, distance: CGFloat, inset: CGFloat, strip: CGFloat) -> State {
        var next = state
        // The baseline only while the bar is really hidden, and before the height is computed: on the frame that decides to hide,
        // the bar is still on screen and its inset would be recorded as the baseline (the bar then shows and hides forever).
        if !next.atEnd, next.hiddenInset != inset { next.hiddenInset = inset }
        let height = measuredBarHeight(strip: strip, inset: inset, hiddenInset: next.hiddenInset)
        next.atEnd = isShown(distanceFromEnd: distance, wasShown: next.atEnd, barHeight: height, voiceOver: false)
        return next
    }

    /// The short appear/disappear animation; none under Reduce Motion.
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }
}

/// What the pager watches in the list's scroll geometry.
private struct ScrollEnd: Equatable {
    let distance: CGFloat
    let inset: CGFloat
}

private struct PagerBarModifier: ViewModifier {
    @Environment(\.rootHasTabBar) private var rootHasTabBar
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shown until the first geometry says otherwise (a list not measured yet is not scrolled away from anything).
    @State private var visibility = PagerVisibility.State()
    /// The strip's measured height (tab root); the sidebar bottom bar is measured by the inset it adds (`PagerVisibility.step`).
    @State private var stripHeight: CGFloat = 0
    let pager: PagerToolbar?
    let hidden: Bool

    private var shown: Bool { visibility.atEnd || voiceOver }

    @ViewBuilder
    func body(content: Content) -> some View {
        let tracked = content
            .onScrollGeometryChange(for: ScrollEnd.self) { geometry in
                ScrollEnd(
                    distance: PagerVisibility.distanceFromEnd(
                        offsetY: geometry.contentOffset.y, containerHeight: geometry.containerSize.height,
                        contentHeight: geometry.contentSize.height, bottomInset: geometry.contentInsets.bottom
                    ),
                    inset: geometry.contentInsets.bottom
                )
            } action: { _, end in
                // Only the crossing matters: a state write per scroll frame would redraw the list for nothing.
                let next = PagerVisibility.step(visibility, distance: end.distance, inset: end.inset, strip: stripHeight)
                guard next != visibility else { return }
                // The baseline alone changing needs no animation; the bar showing or hiding does.
                withAnimation(next.atEnd == visibility.atEnd ? nil : PagerVisibility.animation(reduceMotion: reduceMotion)) {
                    visibility = next
                }
            }
            .modifier(PagerActions(pager: pager))
        switch PagerPlacement(rootHasTabBar: rootHasTabBar) {
        case .bottomBar:
            tracked
                .toolbar {
                    if let pager { pager.toolbarContent }
                }
                .toolbar(shown ? .visible : .hidden, for: .bottomBar)
        case .inset:
            // Always attached, with empty content when there is nothing to show: attaching it only when a pager exists would change
            // the identity of `content` (search focus, list scroll) each time the results or the focus change.
            tracked.safeAreaBar(edge: .bottom) {
                if let pager, !hidden, shown {
                    pager.strip.padding(.vertical, 4)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

/// The page steps as accessibility actions of the list (#898). One stable modifier whose content varies, never a view type
/// that changes with the steps: the list's identity (scroll, selection, search focus) must survive a page change.
private struct PagerActions: ViewModifier {
    let pager: PagerToolbar?

    func body(content: Content) -> some View {
        content.accessibilityActions {
            ForEach(Array((pager?.pageActions ?? []).enumerated()), id: \.offset) { _, step in
                Button(step.name, action: step.action)
            }
        }
    }
}

extension View {
    /// Shows `pager` (nil hides it) in the placement that fits the root; see `PagerPlacement`. `hidden` hides the strip
    /// (a focused text field: the inset would float over the form above the keyboard). The bar shows only when the list is
    /// scrolled to its end (#898, `PagerVisibility`).
    func pagerBar(_ pager: PagerToolbar?, hidden: Bool = false) -> some View {
        modifier(PagerBarModifier(pager: pager, hidden: hidden))
    }
}
