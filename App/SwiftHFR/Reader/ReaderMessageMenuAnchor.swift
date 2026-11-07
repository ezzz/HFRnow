import HFRModels
import SwiftUI

/// What `installMenuActions` reads from the screen, compared to know when to rebuild the handlers.
struct MenuInstallKey: Equatable {
    let hasComposer: Bool
    let hasFlagActions: Bool
}

/// The entries of a message menu under its title, as a list in a popover.
struct MessageMenuList: View {
    let menu: MessageMenu
    let pick: (MessageMenuAction) -> Void

    var body: some View {
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
        .frame(minWidth: 220)
        .fixedSize(horizontal: true, vertical: true)
    }
}

/// The message menu of the reader, a popover anchored at the tapped "⋯" like legacy's edit menu at the tapped point
/// (issue #594). A confirmation dialog hangs from the whole reader: since iOS 26 it opens at the top centre, far from the button.
struct ReaderMessageMenuAnchor: View {
    let model: TopicReaderModel

    var body: some View {
        GeometryReader { proxy in
            let rect = model.presentedMenu?.anchor.flatMap { $0.isEmpty ? nil : $0 }
                ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 1, height: 1)
            Color.clear
                .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                .position(x: rect.midX, y: rect.midY)
                .popover(
                    item: Binding(get: { model.presentedMenu }, set: { if $0 == nil { model.dismissMenu() } }),
                    attachmentAnchor: .rect(.bounds), arrowEdge: .top
                ) { menu in
                    MessageMenuList(menu: menu) { action in Task { await model.perform(action, in: menu) } }
                        .presentationCompactAdaptation(.popover)
                }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .vertical)
    }
