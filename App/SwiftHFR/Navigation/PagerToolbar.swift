import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsPaginationBar, `:926-981`) and of the pager of HFRswift/Swift/ForumSearchView.swift
// (`:395-432`) @ 2440d79. Differences: legacy drew its own glass capsule, this is the system bottom bar; GAP row pending #545 (LOT-185).
/// The page controls of a list, as system bottom-bar items (Liquid Glass; on iPhone Duo's cover screen the system moves them
/// to the side) instead of a hand-built strip with an opaque fill.
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

    /// The system bottom-bar items (regular width: no tab bar, nothing to overlap).
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

    /// The same controls as a strip, for the compact layout.
    fileprivate var strip: some View {
        HStack {
            Button("Première page", systemImage: "backward.end", action: first.action).disabled(!first.enabled)
            Button("Page précédente", systemImage: "chevron.left", action: previous.action).disabled(!previous.enabled)
            Spacer()
            statusView
            Spacer()
            Button("Page suivante", systemImage: "chevron.right", action: next.action).disabled(!next.enabled)
            if let last {
                Button("Dernière page", systemImage: "forward.end", action: last.action).disabled(!last.enabled)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .padding(.horizontal)
    }
}

/// Where a list's pager goes (#565): the system bottom bar of a list inside the iPhone tab bar's TabView lands in the floating
/// tab bar's frame and cannot be used, so compact width (the tab bar root, `RootNavigationView.usesSidebarRoot`) gets an inset above it.
enum PagerPlacement: Equatable {
    case bottomBar
    case inset

    /// An unknown size class takes the inset: a duplicated pager is better than a hidden one.
    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        self = horizontalSizeClass == .regular ? .bottomBar : .inset
    }
}

private struct PagerBarModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let pager: PagerToolbar?

    func body(content: Content) -> some View {
        let placement = PagerPlacement(horizontalSizeClass: sizeClass)
        content
            .toolbar {
                if placement == .bottomBar, let pager { pager.toolbarContent }
            }
            .safeAreaBar(edge: .bottom) {
                if placement == .inset, let pager { pager.strip.padding(.vertical, 4) }
            }
    }
}

extension View {
    /// Shows `pager` (nil hides it) in the placement that fits the layout; see `PagerPlacement`.
    func pagerBar(_ pager: PagerToolbar?) -> some View {
        modifier(PagerBarModifier(pager: pager))
    }
}
