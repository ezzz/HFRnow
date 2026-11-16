import SwiftUI

/// What the « page x / y » pill's menu offers (#968, #980): the four steps and the typed entry, with the bounds that disable them.
/// Pure and list-agnostic, so every list's pager gets the same rules. Port of the page picker of `HFRswift/Swift/MainWindow.swift`
/// (`TopicPagePickerSheet`, `:923-930` @ 87fe0d1c); differences: a menu with the four steps above the typed entry, not a sheet alone.
struct PagerPageMenu: Equatable {
    /// The page on screen (1-based).
    let current: Int
    /// The last page (at least `current`).
    let total: Int
    /// Whether `total` is the real last page; false when it is only the last page HFR's pager window links to (a lower bound).
    let isExact: Bool

    /// Creates the menu rules; a `total` below `current` or below 1 is raised to it.
    init(current: Int, total: Int, isExact: Bool = true) {
        self.current = max(current, 1)
        self.total = max(total, self.current)
        self.isExact = isExact
    }

    var canGoFirst: Bool { current > 1 }
    var canGoPrevious: Bool { current > 1 }
    var canGoNext: Bool { current < total }
    /// Not offered while the last page is only a lower bound.
    var canGoLast: Bool { isExact && current < total }
    /// The typed entry is offered when there is another page to go to.
    var canEnterPage: Bool { total > 1 || !isExact }

    var firstPage: Int { 1 }
    var previousPage: Int { max(current - 1, 1) }
    var nextPage: Int { min(current + 1, total) }
    var lastPage: Int { total }

    /// The page a typed entry names: digits (surrounding spaces ignored) within 1...`total` (1 or more when `total` is only a
    /// lower bound), else nil (the entry is refused).
    func page(fromEntry text: String) -> Int? {
        guard let page = Int(text.trimmingCharacters(in: .whitespaces)), page >= 1, !isExact || page <= total else { return nil }
        return page
    }

    /// « page x / y », « page x / y+ » when `total` is a lower bound.
    var label: String { "page \(current) / \(total)" + (isExact ? "" : "+") }
}

/// The « page x / y » pill: a glass capsule that opens the page menu, or a plain capsule when the list cannot jump.
struct PagerPageMenuPill: View {
    let current: Int
    let total: Int
    var isExact = true
    /// Called with the page chosen in the menu or typed; nil makes the pill a plain label.
    let onPage: ((Int) -> Void)?
    @State private var isEntering = false
    @State private var entry = ""

    var body: some View {
        let menu = PagerPageMenu(current: current, total: total, isExact: isExact)
        if let onPage {
            Menu {
                Button("Première page", systemImage: "backward.end") { onPage(menu.firstPage) }.disabled(!menu.canGoFirst)
                Button("Page précédente", systemImage: "chevron.left") { onPage(menu.previousPage) }.disabled(!menu.canGoPrevious)
                Button("Page suivante", systemImage: "chevron.right") { onPage(menu.nextPage) }.disabled(!menu.canGoNext)
                Button("Dernière page", systemImage: "forward.end") { onPage(menu.lastPage) }.disabled(!menu.canGoLast)
                Button("Aller à la page…", systemImage: "number") {
                    entry = ""
                    isEntering = true
                }
                .disabled(!menu.canEnterPage)
            } label: {
                pill(menu)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ouvre le menu des pages")
            .alert("Aller à la page", isPresented: $isEntering) {
                TextField(menu.isExact ? "1 à \(menu.total)" : "Numéro", text: $entry).keyboardType(.numberPad)
                Button("Annuler", role: .cancel) {}
                Button("Aller") { if let page = menu.page(fromEntry: entry) { onPage(page) } }
            }
        } else {
            pill(menu)
        }
    }

    private func pill(_ menu: PagerPageMenu) -> some View {
        Text(menu.label).monospacedDigit()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .accessibilityLabel(
                menu.isExact ? "Page \(menu.current) sur \(menu.total)" : "Page \(menu.current), au moins \(menu.total) pages"
            )
    }
}
