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
    /// "Page N", or a spinner while a page loads.
    let status: Status

    enum Status {
        case page(Int)
        case loading
    }

    /// The enabled page steps as named actions, for the list's accessibility actions (#898): the bar can be hidden, the pages stay reachable.
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
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Première page", systemImage: "backward.end", action: first.action).disabled(!first.enabled)
            Button("Page précédente", systemImage: "chevron.left", action: previous.action).disabled(!previous.enabled)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) { statusView }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Page suivante", systemImage: "chevron.right", action: next.action).disabled(!next.enabled)
            if let last {
                Button("Dernière page", systemImage: "forward.end", action: last.action).disabled(!last.enabled)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .page(let number): Text("Page \(number)").monospacedDigit()
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

    private func stripRow(full: Bool) -> some View {
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

    /// VoiceOver keeps the bar so the page actions never depend on a scroll position.
    static func isShown(distanceFromEnd: CGFloat, voiceOver: Bool) -> Bool {
        voiceOver || distanceFromEnd <= tolerance
    }

    /// The short appear/disappear animation; none under Reduce Motion.
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }
}

private struct PagerBarModifier: ViewModifier {
    @Environment(\.rootHasTabBar) private var rootHasTabBar
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True until the first geometry says otherwise: a list that has not been measured yet is not scrolled away from anything.
    @State private var distanceFromEnd: CGFloat = 0
    let pager: PagerToolbar?
    let hidden: Bool

    private var shown: Bool { PagerVisibility.isShown(distanceFromEnd: distanceFromEnd, voiceOver: voiceOver) }

    @ViewBuilder
    func body(content: Content) -> some View {
        let tracked = content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                PagerVisibility.distanceFromEnd(
                    offsetY: geometry.contentOffset.y, containerHeight: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height, bottomInset: geometry.contentInsets.bottom
                )
            } action: { _, distance in
                // Only the crossing matters: a state write per scroll frame would redraw the list for nothing.
                guard (distance <= PagerVisibility.tolerance) != (distanceFromEnd <= PagerVisibility.tolerance) else { return }
                withAnimation(PagerVisibility.animation(reduceMotion: reduceMotion)) { distanceFromEnd = distance }
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
                    pager.strip.padding(.vertical, 4).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

/// The page steps as accessibility actions of the list, so hiding the bar is visual only (#898).
private struct PagerActions: ViewModifier {
    let pager: PagerToolbar?

    func body(content: Content) -> some View {
        var view = AnyView(content)
        for step in pager?.pageActions ?? [] {
            view = AnyView(view.accessibilityAction(named: Text(step.name), step.action))
        }
        return view
    }
}

extension View {
    /// Shows `pager` (nil hides it) in the placement that fits the root; see `PagerPlacement`. `hidden` hides the strip
    /// (a focused text field: the inset would float over the form above the keyboard).
    func pagerBar(_ pager: PagerToolbar?, hidden: Bool = false) -> some View {
        modifier(PagerBarModifier(pager: pager, hidden: hidden))
    }
}
