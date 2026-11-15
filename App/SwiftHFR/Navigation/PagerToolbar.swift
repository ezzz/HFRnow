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

private struct PagerBarModifier: ViewModifier {
    @Environment(\.rootHasTabBar) private var rootHasTabBar
    let pager: PagerToolbar?
    let hidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch PagerPlacement(rootHasTabBar: rootHasTabBar) {
        case .bottomBar:
            content.toolbar {
                if let pager { pager.toolbarContent }
            }
        case .inset:
            // Always attached, with empty content when there is nothing to show: attaching it only when a pager exists would change
            // the identity of `content` (search focus, list scroll) each time the results or the focus change.
            content.safeAreaBar(edge: .bottom) {
                if let pager, !hidden { pager.strip.padding(.vertical, 4) }
            }
        }
    }
}

extension View {
    /// Shows `pager` (nil hides it) in the placement that fits the root; see `PagerPlacement`. `hidden` hides the strip
    /// (a focused text field: the inset would float over the form above the keyboard).
    func pagerBar(_ pager: PagerToolbar?, hidden: Bool = false) -> some View {
        modifier(PagerBarModifier(pager: pager, hidden: hidden))
    }
}
