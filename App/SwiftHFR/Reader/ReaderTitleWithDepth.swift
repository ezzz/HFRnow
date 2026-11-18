import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (`toolbarStackIndicatorView`, `toolbarTitleView`) @ 87fe0d1c (`3476-3488`; `3410-3440`
// @ 2fe43da3, `602b900e`). Differences: the capsule is filled and labelled with the app's badge colours (4.5:1, a theme's `unread` /
// `onUnread`), not legacy's palette tint with white text; its sizes follow the app's type scale; the title keeps the system inline
// title's size (legacy sets it in caption2 bold); legacy's loading spinner stays in the reader's own state overlay; the "back to root"
// button legacy dropped at `602b900e` is not ported (#682).
/// The title of a reader a followed link pushed: a capsule with the stack depth, then the topic title.
struct ReaderTitleWithDepth: View {
    let depth: Int
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            ReaderStackDepthCapsule(depth: depth)
            Text(title).scaledFont(.headline).lineLimit(1).truncationMode(.tail)
        }
    }
}

/// The principal toolbar item of a pushed reader: no glass capsule behind the custom title (as `ScreenTitle`).
struct ReaderDepthTitleToolbar: ToolbarContent {
    let depth: Int
    let title: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) { ReaderTitleWithDepth(depth: depth, title: title) }
            .sharedBackgroundVisibility(.hidden)
    }
}

/// The small capsule « ‹ N », shown from depth 1.
struct ReaderStackDepthCapsule: View {
    let depth: Int
    @Environment(\.themeAppearance) private var appearance

    /// What VoiceOver says for `depth`; nil when no capsule shows (legacy `"\(navigationDepth) affichage de messages empilé"`).
    static func accessibilityLabel(depth: Int) -> String? {
        depth > 0 ? "\(depth) affichage de messages empilé" : nil
    }

    var body: some View {
        if let label = Self.accessibilityLabel(depth: depth) {
            let fill = appearance.themeColor(\.unread).map { Color(uiColor: $0) } ?? AccessibleColors.color(.badgeFill)
            let onFill = appearance.themeColor(\.onUnread).map { Color(uiColor: $0) } ?? AccessibleColors.color(.badgeText)
            HStack(spacing: 2) {
                Image(systemName: "chevron.backward").imageScale(.small).fontWeight(.bold)
                Text("\(depth)").fontWeight(.bold).monospacedDigit()
            }
            .scaledFont(.caption2)
            .foregroundStyle(onFill)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(fill, in: Capsule())
            .accessibilityLabel(label)
        }
    }
}
