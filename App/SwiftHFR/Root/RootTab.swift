import HFRModels

/// The four root tabs of the iPhone tab bar, in legacy order (`RootTabIdentifier`, `Common.swift:25-30`).
enum RootTab: Int, CaseIterable, Hashable, Sendable {
    case categories
    case favorites
    case messages
    case more

    /// Tab title (legacy `MainWindow.swift:1698-1725`).
    var title: String {
        switch self {
        case .categories: "Catégories"
        case .favorites: "Favoris"
        case .messages: "Messages"
        case .more: "Plus"
        }
    }

    /// SF Symbol of the tab (legacy `MainWindow.swift:1698-1725`).
    var symbol: String {
        switch self {
        case .categories: "folder.fill"
        case .favorites: "star.fill"
        case .messages: "envelope"
        case .more: "ellipsis"
        }
    }

    /// The tab the app opens on for the start-screen setting (legacy `AppStartupScreen.rootTab`, `Common.swift:31-45`).
    init(startup: StartupScreen) {
        switch startup {
        case .categories: self = .categories
        case .favorites: self = .favorites
        case .messages: self = .messages
        }
    }
}

/// The entries of the Plus tab, in legacy order (`PlusTab.swift:11-60`).
enum PlusEntry: CaseIterable, Hashable, Sendable {
    case settings
    case search
    case bookmarks
    case qualityAlerts
    case credits
    case charter
    case deleteAccount

    /// Row title.
    var title: String {
        switch self {
        case .settings: "Réglages"
        case .search: "Rechercher sur le forum"
        case .bookmarks: "Bookmarks"
        case .qualityAlerts: "Alertes Qualitay"
        case .credits: "Crédits"
        case .charter: "Charte du forum"
        case .deleteAccount: "Supprimer mon compte"
        }
    }

    /// SF Symbol of the row (legacy `PlusTab.swift`, iPad sidebar `MainWindow.swift:2227-2245`).
    var symbol: String {
        switch self {
        case .settings: "gearshape"
        case .search: "magnifyingglass"
        case .bookmarks: "pin"
        case .qualityAlerts: "bell"
        case .credits: "info.circle"
        case .charter: "doc.text"
        case .deleteAccount: "trash"
        }
    }

    /// The lot that builds the screen behind the entry; until it lands the entry shows a placeholder, never a dead row.
    var owningLot: String? {
        switch self {
        case .settings: nil
        case .search: "LOT-115"
        case .bookmarks: "LOT-132"
        case .qualityAlerts: "LOT-133"
        case .credits, .charter: "LOT-120"
        case .deleteAccount: "LOT-157"
        }
    }

    /// Whether the entry leads to a built screen.
    var isBuilt: Bool { owningLot == nil }

    /// Destructive entries are drawn in red, as legacy.
    var isDestructive: Bool { self == .deleteAccount }
}

/// A destination of the regular-width iPad sidebar (legacy `IPadSidebarDestination`, `MainWindow.swift:1280-1316`).
enum SidebarDestination: Hashable, Sendable {
    case tab(RootTab)
    case plus(PlusEntry)

    /// Sidebar sections, in legacy order (`MainWindow.swift:2205-2225`): the lists, the tools, then the Plus entries.
    static let sections: [[SidebarDestination]] = [
        [.tab(.categories), .tab(.favorites), .tab(.messages)],
        [.plus(.bookmarks), .plus(.qualityAlerts)],
        [.plus(.settings), .plus(.search), .plus(.credits), .plus(.charter), .plus(.deleteAccount)]
    ]

    /// Row title.
    var title: String {
        switch self {
        case .tab(let tab): tab.title
        case .plus(let entry): entry.title
        }
    }

    /// Row symbol.
    var symbol: String {
        switch self {
        case .tab(let tab): tab.symbol
        case .plus(let entry): entry.symbol
        }
    }
}
