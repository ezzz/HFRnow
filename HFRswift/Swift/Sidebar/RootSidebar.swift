//
//  RootSidebar.swift
//  HFRswift
//
//  Sidebar of the regular-width layout: Rechercher, Messages (with each private message),
//  Favoris, Catégories (with the forums by family) and Plus. "Messages" and "Catégories" open
//  their screen when tapped and unfold with their chevron.
//

import SwiftUI

struct RootSidebar: View {
    let forums: [Forum]
    let privateMessages: [SidebarPrivateMessageItem]
    let isLoggedIn: Bool
    let messagesBadge: Int
    let moreBadge: Int
    let selectedItem: RootSidebarItem?
    let onSelect: (RootSidebarItem) -> Void

    @Environment(\.natif) private var natif
    /// Unfolded entries ("messages", "categories" and the forum families), kept across launches.
    @AppStorage("root_sidebar_expanded") private var expandedRawValue = "categories"

    var body: some View {
        // Its own navigation bar puts "HFR" at the height of the content title, whatever the
        // orientation and top safe area.
        NavigationStack {
            List {
                RootSidebarRow(title: "Rechercher", systemImage: "magnifyingglass", isSelected: selectedItem == .search) {
                    onSelect(.search)
                }

                RootSidebarRow(
                    title: "Messages",
                    systemImage: "envelope.fill",
                    badge: messagesBadge,
                    isSelected: selectedItem == .messages,
                    isExpanded: expansion("messages")
                ) {
                    onSelect(.messages)
                }
                if expansion("messages").wrappedValue {
                    if privateMessages.isEmpty {
                        Text(isLoggedIn ? "Aucun message" : "Connexion requise")
                            .font(.subheadline)
                            .foregroundStyle(natif.text2)
                            .padding(.leading, RootSidebarRow.indentWidth + 38)
                            .rootSidebarRowStyle(isSelected: false)
                    }
                    ForEach(privateMessages) { item in
                        RootSidebarRow(
                            title: item.title,
                            systemImage: item.isUnread ? "envelope.badge.fill" : "envelope",
                            isSelected: selectedItem == .privateMessage(item.id),
                            isEmphasized: item.isUnread,
                            level: 1
                        ) {
                            onSelect(.privateMessage(item.id))
                        }
                    }
                }

                RootSidebarRow(title: "Favoris", systemImage: "flag.fill", isSelected: selectedItem == .favorites) {
                    onSelect(.favorites)
                }

                RootSidebarRow(
                    title: "Catégories",
                    systemImage: "square.grid.2x2.fill",
                    isSelected: selectedItem == .categories,
                    isExpanded: expansion("categories")
                ) {
                    onSelect(.categories)
                }
                if expansion("categories").wrappedValue {
                    ForEach(forumGroups, id: \.group) { entry in
                        let groupExpansion = expansion("group-\(entry.group.rawValue)")
                        RootSidebarGroupRow(title: entry.group.title, isExpanded: groupExpansion)
                        if groupExpansion.wrappedValue {
                            ForEach(entry.forums, id: \.self) { route in
                                RootSidebarRow(
                                    title: route.forum.aTitle ?? "Forum",
                                    systemImage: NatifForumCatalog.systemImage(for: route.forum.aTitle),
                                    isSelected: selectedItem == .forum(route.id),
                                    level: 2
                                ) {
                                    onSelect(.forum(route.id))
                                }
                            }
                        }
                    }
                }

                RootSidebarRow(title: "Plus", systemImage: "ellipsis", badge: moreBadge, isSelected: selectedItem == .more) {
                    onSelect(.more)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 44)
            .background(natif.bgGrouped.ignoresSafeArea())
            .navigationTitle("HFR")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var forumGroups: [(group: NatifForumGroup, forums: [ForumRoute])] {
        let routes = forums.map(ForumRoute.init(forum:))
        let grouped = Dictionary(grouping: routes) { NatifForumCatalog.group(for: $0.forum.aTitle) }
        return NatifForumGroup.allCases.compactMap { group in
            guard let routes = grouped[group], !routes.isEmpty else { return nil }
            return (group, routes)
        }
    }

    private var expandedKeys: Set<String> {
        Set(expandedRawValue.split(separator: ",").map(String.init))
    }

    private func expansion(_ key: String) -> Binding<Bool> {
        Binding {
            expandedKeys.contains(key)
        } set: { isExpanded in
            var keys = expandedKeys
            if isExpanded {
                keys.insert(key)
            } else {
                keys.remove(key)
            }
            expandedRawValue = keys.sorted().joined(separator: ",")
        }
    }
}

/// A sidebar entry: accent symbol, title, optional red badge, rounded highlight when selected.
private struct RootSidebarRow: View {
    let title: String
    let systemImage: String
    var badge = 0
    let isSelected: Bool
    var isEmphasized = false
    /// Shows a chevron that folds / unfolds the entries below.
    var isExpanded: Binding<Bool>?
    /// Indentation: 1 for private messages and forum families, 2 for forums.
    var level = 0
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.natif) private var natif

    static let indentWidth: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if let isExpanded {
                RootSidebarChevron(title: title, isExpanded: isExpanded)
            }
        }
        .rootSidebarRowStyle(isSelected: isSelected)
    }

    private var label: some View {
        HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(natif.accent)
                    .frame(width: 26)
                Text(title)
                    .fontWeight(isEmphasized ? .semibold : .regular)
                    .foregroundStyle(natif.text)
                    // Accessibility sizes: two lines rather than "Ordinateur…".
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Spacer(minLength: 4)
                if badge > 0 {
                    NatifRedBadge(count: badge)
                }
        }
        .padding(.leading, CGFloat(level) * Self.indentWidth)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

/// Forum family (Matériel, Multimédia…): the whole row folds / unfolds its forums.
private struct RootSidebarGroupRow: View {
    let title: String
    @Binding var isExpanded: Bool
    @Environment(\.natif) private var natif

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(natif.text2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(natif.text3)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 32, height: 32)
            }
            .padding(.leading, RootSidebarRow.indentWidth)
            .frame(minHeight: 36)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Déplié" : "Replié")
        .rootSidebarRowStyle(isSelected: false)
    }
}

private struct RootSidebarChevron: View {
    let title: String
    @Binding var isExpanded: Bool
    @Environment(\.natif) private var natif

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
        } label: {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(natif.text3)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 32, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Replier \(title)" : "Déplier \(title)")
    }
}

private struct RootSidebarRowStyle: ViewModifier {
    let isSelected: Bool
    @Environment(\.natif) private var natif

    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? natif.surface2 : .clear)
                    .padding(.horizontal, 8)
            )
    }
}

private extension View {
    func rootSidebarRowStyle(isSelected: Bool) -> some View {
        modifier(RootSidebarRowStyle(isSelected: isSelected))
    }
}
