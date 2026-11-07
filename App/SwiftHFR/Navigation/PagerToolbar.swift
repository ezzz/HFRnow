import SwiftUI

/// The page controls of a list, as system bottom-bar items (Liquid Glass, and on iPhone Duo's cover screen the system
/// moves them to the side) instead of a hand-built strip with an opaque fill. Port of the list pagers of
/// HFRswift/Swift/MainWindow.swift:977-981 @ 2440d79. Differences: the legacy drew its own glass capsule; the bar is the
/// system's (LOT-185).
struct PagerToolbar: ToolbarContent {
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

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Première page", systemImage: "backward.end", action: first.action).disabled(!first.enabled)
            Button("Page précédente", systemImage: "chevron.left", action: previous.action).disabled(!previous.enabled)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            switch status {
            case .page(let number): Text("Page \(number)").monospacedDigit()
            case .loading: ProgressView()
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Page suivante", systemImage: "chevron.right", action: next.action).disabled(!next.enabled)
            if let last {
                Button("Dernière page", systemImage: "forward.end", action: last.action).disabled(!last.enabled)
            }
        }
    }
}
