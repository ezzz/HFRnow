import HFRModels
import SwiftUI

/// The entries of a message menu under its title, as a list in a popover.
struct MessageMenuList: View {
    let menu: MessageMenu
    let pick: (MessageMenuAction) -> Void

    var body: some View {
        // Scrolls when the popover is shorter than the list (landscape, a button near an edge).
        ViewThatFits(in: .vertical) {
            list
            ScrollView { list }
        }
        // Labels wrap at large Dynamic Type sizes instead of overflowing a narrow screen.
        .frame(minWidth: 220, maxWidth: 360)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(menu.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityAddTraits(.isHeader)
            ForEach(menu.entries, id: \.kind) { action in
                Divider()
                Button(role: action.isDestructive ? .destructive : nil) { pick(action) } label: {
                    Label(action.title, systemImage: action.systemImageName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Port of HFRswift/Swift/MessagesView.swift (presentPopupMenu, popupAnchor, popupMenuTitle) @ 2440d79. Differences: legacy opens
// the author's actions as a sheet (`onPopupAvatarSheetRequest`, :2016-2027 @ 87fe0d1c), SwiftHFR as a popover at the author;
// the message menu ("+") is the edit-menu callout (`ReaderMessageEditMenu`, #594). GAP-064.
/// The author menu of the reader, a popover anchored at the tapped author. A confirmation dialog hangs from the whole reader:
/// since iOS 26 it opens at the top centre, far from the button.
struct ReaderMessageMenuAnchor: View {
    let model: TopicReaderModel

    /// The author menu on screen; the message menu is the callout's (#594).
    private var menu: MessageMenu? {
        model.presentedMenu.flatMap { $0.source == .avatar ? $0 : nil }
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = menu?.anchor.flatMap { $0.isEmpty ? nil : $0 }
                ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 1, height: 1)
            Color.clear
                .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                .position(x: rect.midX, y: rect.midY)
                .popover(
                    item: Binding(get: { menu }, set: { if $0 == nil, menu != nil { model.dismissMenu() } }),
                    attachmentAnchor: .rect(.bounds)
                ) { menu in
                    MessageMenuList(menu: menu) { action in Task { await model.perform(action, in: menu) } }
                        .presentationCompactAdaptation(.popover)
                }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .vertical)
    }
}
