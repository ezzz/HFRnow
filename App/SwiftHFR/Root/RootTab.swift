import HFRModels

// Port of HFRswift/Swift/Common.swift (RootTabIdentifier) and HFRswift/Swift/PlusTab.swift (PlusHomeView rows) @ 2440d79. Differences:
// none in the order; `init(startup:)` and the start-screen setting come from master (GAP-002).
/// The root tabs of the iPhone tab bar: legacy's four, in legacy order (`RootTabIdentifier`, `Common.swift:25-30`), and the
/// experimental Recherche.
enum RootTab: Int, CaseIterable, Hashable, Sendable {
    case categories
    case favorites
    case messages
    case more
    // EXPERIMENTAL(searchTab, #896): the fifth tab, in the bar only while the option is on; the sidebar shows Plus › Rechercher.
    case search

    /// The tabs of the iPhone tab bar from the left, as `RootTabsView` lists them: Recherche, when on, sits before Plus.
    static func barOrder(hasSearch: Bool) -> [RootTab] {
        hasSearch ? [.categories, .favorites, .messages, .search, .more] : [.categories, .favorites, .messages, .more]
    }

    /// The tab at `index` of the bar, nil for an index the bar does not have.
    static func atBarIndex(_ index: Int, hasSearch: Bool) -> RootTab? {
        let order = barOrder(hasSearch: hasSearch)
        return order.indices.contains(index) ? order[index] : nil
    }

    /// Tab title (legacy `MainWindow.swift:1698-1725`).
    var title: String {
        switch self {
        case .categories: "Catégories"
        case .favorites: "Favoris"
        case .messages: "Messages"
        case .more: "Plus"
        case .search: "Recherche"
        }
    }

    /// SF Symbol of the tab (legacy `MainWindow.swift:1698-1725`).
    var symbol: String {
        switch self {
        case .categories: "folder.fill"
        case .favorites: "star.fill"
        case .messages: "envelope"
        case .more: "ellipsis"
        case .search: "magnifyingglass"
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

    /// Destructive entries are drawn in red, as legacy.
    var isDestructive: Bool { self == .deleteAccount }

    /// Whether the regular-width iPad shows the entry as a list of topics beside the topic a row opens (three columns, as
    /// Favoris); the others take a two-column split (legacy `IPadSidebarDestination.usesTopicList`, `MainWindow.swift:1326-1333`
    /// @ 87fe0d1c, #685).
    var usesTopicList: Bool { self == .bookmarks || self == .qualityAlerts }

    /// What the detail column of a topic-list entry shows before a row is opened (legacy `detailPlaceholderTitle`,
    /// `detailPlaceholderSystemImage`, `detailPlaceholderDescription`, `MainWindow.swift:2048-2089` @ 87fe0d1c); nil for the others.
    var detailPlaceholder: DetailPlaceholder? {
        switch self {
        case .bookmarks:
            DetailPlaceholder(title: "Aucun bookmark sélectionné", symbol: "pin", description: "Choisis un bookmark dans la liste.")
        case .qualityAlerts:
            DetailPlaceholder(title: "Aucune alerte sélectionnée", symbol: "bell", description: "Choisis une alerte dans la liste.")
        case .settings, .search, .credits, .charter, .deleteAccount:
            nil
        }
    }
}

/// The empty detail column of a topic-list destination.
struct DetailPlaceholder: Hashable, Sendable {
    let title: String
    let symbol: String
    let description: String
}

/// A titled section of the regular-width iPad sidebar.
struct SidebarSection: Hashable, Sendable {
    let title: String
    let destinations: [SidebarDestination]
}

/// A destination of the regular-width iPad sidebar (legacy `IPadSidebarDestination`, `MainWindow.swift:1280-1316`).
enum SidebarDestination: Hashable, Sendable {
    case tab(RootTab)
    case plus(PlusEntry)

    /// Sidebar sections, in legacy order and with legacy titles (`MainWindow.swift:1878-1901`, `:2384-2401` @ 87fe0d1c): the
    /// lists, the tools, then the Plus entries.
    static let sections: [SidebarSection] = [
        SidebarSection(title: "Forum", destinations: [.tab(.categories), .tab(.favorites), .tab(.messages)]),
        SidebarSection(title: "Outils", destinations: [.plus(.bookmarks), .plus(.qualityAlerts)]),
        SidebarSection(
            title: "Plus", destinations: [.plus(.settings), .plus(.search), .plus(.credits), .plus(.charter), .plus(.deleteAccount)]
        )
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
