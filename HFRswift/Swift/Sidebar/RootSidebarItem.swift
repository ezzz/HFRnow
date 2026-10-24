//
//  RootSidebarItem.swift
//  HFRswift
//
//  Entries of the regular-width sidebar (iPhone Duo inner display, iPad).
//

import Foundation

enum RootSidebarItem: Hashable {
    case search
    case messages
    case privateMessage(String)
    case favorites
    case categories
    case forum(String)
    case more
}

/// A forum pushed on the Catégories stack, compared by its stable identifier.
struct ForumRoute: Hashable {
    let forum: Forum

    var id: String { Self.id(for: forum) }

    static func id(for forum: Forum) -> String {
        [forum.aURL, forum.aID, forum.aTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "forum-\(ObjectIdentifier(forum).hashValue)"
    }

    static func == (lhs: ForumRoute, rhs: ForumRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A private message pushed on the Messages stack from the sidebar.
struct PrivateMessageRoute: Hashable {
    let item: SidebarPrivateMessageItem

    static func == (lhs: PrivateMessageRoute, rhs: PrivateMessageRoute) -> Bool {
        lhs.item.id == rhs.item.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(item.id)
    }
}
