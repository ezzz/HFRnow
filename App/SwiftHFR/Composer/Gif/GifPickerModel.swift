import Foundation
import HFRNetwork
import HFRStorage
import Observation

// Port of HFRswift/Swift/AnswerView.swift (GiphyPanel, GiphyViewController delegate :2294-2340) @ 2440d79 (GAP-089). Differences: our own
// panel over Giphy's REST API instead of the closed SDK (LOT-098), the first-use notice N1 (LOT-071) before any request, no "recents".
/// State of the GIF panel of the composer (LOT-155): the notice, trending or search results, the page being loaded and the
/// choice. The panel only produces a snippet: inserting it at the caret is the composer's.
///
/// Nothing is requested before the notice N1 was accepted: `start`, `submitSearch` and `loadMore` all stop at that gate.
@MainActor
@Observable
final class GifPickerModel: Identifiable {
    /// Settings key of the first-use notice N1 (LOT-071): accepted once per device.
    nonisolated static let noticeKey = "giphy_notice_accepted"

    /// What the grid shows.
    enum Phase: Equatable {
        /// Nothing asked yet (notice pending).
        case idle
        /// The first page is on its way.
        case loading
        /// Results are shown (possibly none).
        case loaded
        /// The first page failed; the French reason.
        case failed(String)
    }

    private(set) var phase = Phase.idle
    /// The GIFs of the current list (trending, or the submitted search), without repeats, on Giphy's CDN only.
    private(set) var items: [GiphyGIF] = []
    /// A further page is being loaded.
    private(set) var isLoadingMore = false
    /// A further page failed; the grid keeps what it has and offers a retry.
    private(set) var moreFailed = false
    /// The text of the search field.
    var query = ""
    /// The search the list answers, nil for trending.
    private(set) var activeQuery: String?
    /// The GIF the member tapped, waiting for confirmation (legacy `showConfirmationScreen`, `AnswerView.swift:2307`).
    var selected: GiphyGIF?

    private let services: GifServices
    private var nextOffset = 0
    private var total: Int?
    /// The last page brought nothing new: no further request, whatever `total` says.
    private var ended = false
    private var generation = 0

    /// A panel over `services`.
    init(services: GifServices) {
        self.services = services
    }

    /// This build can search (a key was injected).
    var isAvailable: Bool { services.isAvailable }

    /// The notice N1 was accepted on this device.
    var isNoticeAccepted: Bool { services.settings.rawValue(forKey: Self.noticeKey) == .bool(true) }

    /// The notice is on screen: available, not yet accepted.
    var isAskingNotice: Bool { isAvailable && !isNoticeAccepted }

    /// The text of notice N1: who runs the host, what is sent, what becomes public (LOT-071 T5).
    var noticeMessage: String {
        let host = services.hostName.map { "le service Giphy (\($0))" } ?? "le service Giphy"
        return "La recherche de GIF passe par \(host), un service tiers qui n'est ni HFR ni cette application. "
            + "Seuls vos mots de recherche sont envoyés, sans votre pseudo ni vos cookies. "
            + "Le GIF choisi est publié par son adresse : chaque lecteur du message le chargera depuis ce service. "
            + "Les conditions du service s'appliquent."
    }

    /// Opens the panel: loads trending when the notice was already accepted, else waits for it. Never contacts anyone before.
    func start() async {
        guard phase == .idle, isAvailable, isNoticeAccepted else { return }
        await reload(query: nil)
    }

    /// The member accepted N1: it is remembered, then trending loads.
    func acceptNotice() async {
        guard isAskingNotice else { return }
        services.settings.setRawValue(.bool(true), forKey: Self.noticeKey)
        await reload(query: nil)
    }

    /// Submits the search field: an empty text goes back to trending.
    func submitSearch() async {
        guard isNoticeAccepted else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        await reload(query: text.isEmpty ? nil : text)
    }

    /// Asks the first page again (after a failure).
    func retry() async {
        await reload(query: activeQuery)
    }

    /// The grid reached `gif`: loads the next page when it is near the end.
    func loadMoreIfNeeded(after gif: GiphyGIF) async {
        guard let index = items.firstIndex(of: gif), index >= items.count - 5 else { return }
        await loadMore()
    }

    /// Loads the next page; a failure keeps the list and sets `moreFailed`.
    func loadMore() async {
        guard phase == .loaded, !isLoadingMore, isNoticeAccepted, hasMore, let client = services.client else { return }
        let (stamp, text, offset) = (generation, activeQuery, nextOffset)
        isLoadingMore = true
        moreFailed = false
        defer { if stamp == generation { isLoadingMore = false } }
        do throws(GiphyError) {
            let page = try await Self.fetch(client, query: text, offset: offset)
            guard stamp == generation else { return }
            append(page)
        } catch {
            guard stamp == generation else { return }
            moreFailed = true
        }
    }

    /// The text to insert for `gif`, nil when its URL is not on Giphy's CDN. Legacy: `[img]<url>[/img]` and a line break
    /// (`AnswerView.swift:2333` @ 2440d79), the URL as served (`images.original`), which is the form the captures verify.
    func snippet(for gif: GiphyGIF) -> String? {
        Self.snippet(forOriginal: gif.originalURL)
    }

    /// The snippet for an original URL, nil off Giphy's CDN.
    nonisolated static func snippet(forOriginal url: URL) -> String? {
        GifMediaPolicy.isAllowed(url) ? "[img]\(url.absoluteString)[/img]\n" : nil
    }

    /// The grid's small rendition of `gif`, nil unless it is on Giphy's CDN.
    func previewURL(of gif: GiphyGIF) -> URL? {
        gif.previewURL.flatMap { GifMediaPolicy.isAllowed($0) ? $0 : nil }
    }

    private var hasMore: Bool {
        !ended && (total.map { nextOffset < $0 } ?? !items.isEmpty)
    }

    private func reload(query text: String?) async {
        guard isNoticeAccepted, let client = services.client else { return }
        generation += 1
        let stamp = generation
        activeQuery = text
        items = []
        nextOffset = 0
        total = nil
        ended = false
        isLoadingMore = false
        moreFailed = false
        phase = .loading
        do throws(GiphyError) {
            let page = try await Self.fetch(client, query: text, offset: 0)
            guard stamp == generation else { return }
            append(page)
            phase = .loaded
        } catch {
            guard stamp == generation else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    private func append(_ page: GiphyPage) {
        var known = Set(items.map(\.id))
        let fresh = page.items.filter { GifMediaPolicy.isAllowed($0.originalURL) }.filter { known.insert($0.id).inserted }
        items += fresh
        nextOffset += GiphyClient.defaultLimit
        total = page.totalCount
        // A page with nothing new ends the list, whatever the total says (Giphy repeats items near its offset cap).
        if fresh.isEmpty { ended = true }
    }

    /// Rating R as legacy (`AnswerView.swift:2305` @ 2440d79), the client's default page size.
    nonisolated private static func fetch(_ client: GiphyClient, query: String?, offset: Int) async throws(GiphyError) -> GiphyPage {
        if let query { return try await client.search(query, offset: offset, rating: .restricted) }
        return try await client.trending(offset: offset, rating: .restricted)
    }

    /// The French reason a page failed.
    nonisolated static func message(for error: GiphyError) -> String {
        switch error {
        case .network: "Impossible de joindre le service de GIF. Vérifiez votre connexion."
        case .http(let code) where code == 429: "Trop de recherches de GIF pour le moment. Réessayez dans un instant."
        case .http, .invalidResponse: "Le service de GIF a répondu de façon inattendue."
        case .notConfigured, .invalidBaseURL: "La recherche de GIF n'est pas disponible dans cette version."
        case .emptyQuery: "Saisissez un mot à chercher."
        }
    }
}
