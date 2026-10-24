//
//  NatifForumCatalog.swift
//  HFRswift
//
//  Groups and SF Symbols of the HFR categories (Natif "Catégories" screen).
//

import Foundation

enum NatifForumGroup: Int, CaseIterable, Identifiable {
    case hardware
    case multimedia
    case software
    case community

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .hardware: "Matériel"
        case .multimedia: "Multimédia"
        case .software: "Logiciels & réseaux"
        case .community: "Communauté"
        }
    }
}

enum NatifForumCatalog {
    private struct Entry {
        let keywords: [String]
        let group: NatifForumGroup
        let systemImage: String
    }

    /// Matched in order against the normalized forum title, so more specific names come first.
    private static let entries: [Entry] = [
        Entry(keywords: ["peripherique"], group: .hardware, systemImage: "keyboard"),
        Entry(keywords: ["portable"], group: .hardware, systemImage: "laptopcomputer"),
        Entry(keywords: ["overclocking", "cooling", "modding"], group: .hardware, systemImage: "fan"),
        Entry(keywords: ["electronique", "domotique", "diy"], group: .hardware, systemImage: "powerplug"),
        Entry(keywords: ["mobile"], group: .hardware, systemImage: "iphone"),
        Entry(keywords: ["apple"], group: .hardware, systemImage: "applelogo"),
        Entry(keywords: ["hardware"], group: .hardware, systemImage: "cpu"),
        Entry(keywords: ["video", "son"], group: .multimedia, systemImage: "tv"),
        Entry(keywords: ["photo"], group: .multimedia, systemImage: "camera"),
        Entry(keywords: ["jeux", "jeu video"], group: .multimedia, systemImage: "gamecontroller"),
        Entry(keywords: ["graphisme"], group: .multimedia, systemImage: "paintbrush.pointed"),
        Entry(keywords: ["windows", "software", "logiciel"], group: .software, systemImage: "macwindow"),
        Entry(keywords: ["reseaux pro", "systemes"], group: .software, systemImage: "server.rack"),
        Entry(keywords: ["reseau", "soho"], group: .software, systemImage: "wifi"),
        Entry(keywords: ["linux", "os alternatif"], group: .software, systemImage: "terminal"),
        Entry(keywords: ["programmation"], group: .software, systemImage: "chevron.left.forwardslash.chevron.right"),
        Entry(keywords: ["intelligence artificielle"], group: .software, systemImage: "sparkles"),
        Entry(keywords: ["achat", "vente"], group: .community, systemImage: "cart"),
        Entry(keywords: ["emploi", "etude"], group: .community, systemImage: "briefcase"),
        Entry(keywords: ["discussion"], group: .community, systemImage: "bubble.left.and.bubble.right"),
    ]

    private static func entry(for title: String?) -> Entry? {
        let normalized = (title ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        return entries.first { entry in
            entry.keywords.contains { normalized.contains($0) }
        }
    }

    static func group(for title: String?) -> NatifForumGroup {
        entry(for: title)?.group ?? .community
    }

    static func systemImage(for title: String?) -> String {
        entry(for: title)?.systemImage ?? "folder"
    }
}
