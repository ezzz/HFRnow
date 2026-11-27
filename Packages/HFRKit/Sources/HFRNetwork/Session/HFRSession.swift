import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HFRModels

/// The HTTP session of one forum account: its own `URLSession` and cookie jar, and its `hash_check`.
///
/// Replaces the legacy global jar that was wiped and refilled on every account switch and before every list load
/// (audit A §4.3-4.4, `AccountSessionService.swift:77-110`): two sessions never see each other's cookies, so several
/// accounts can work at the same time. The app passes the stored cookies in and reads them back with `cookies(now:)`;
/// persistence is not done here (LOT-065). Requests sent through it carry the jar's cookies and store the answer's
/// `Set-Cookie`. For requests that must not be authenticated (prefetch, images) use `AnonymousTransport`:
/// an authenticated topic GET marks flags read (HFR-PROTOCOL §7, E25).
public actor HFRSession: HTTPTransport {
    /// Name of the identity cookie; its value is the account's pseudo key (audit A §4.1).
    public static let identityCookieName = "md_user"
    /// Value of `md_user` with which the server says the session is logged out (`MultisManager.m:55`).
    public static let loggedOutMarker = "deleted"

    private let connection: SessionConnection
    private var urlSession: URLSession { connection.urlSession }
    private var cookieStorage: HTTPCookieStorage { connection.cookieStorage }
    private var transport: URLSessionTransport { connection.transport }
    /// Where requests may go: the forum in production, one host in tests.
    let hosts: SessionHostPolicy
    /// The connections this session's probes send through (#1398); a probe shares its source's pool.
    package nonisolated let probeConnections: ProbeConnectionPool
    /// Whether `connection` came from `probeConnections` and goes back there when this session is released.
    private let isProbe: Bool
    /// Set once an exchange threw: its task may still answer, so the connection is never given to another probe.
    private var exchangeFailed = false

    /// The anti-CSRF token every POST needs (HFR-PROTOCOL §5); nil until known.
    public private(set) var hashCheck: String?

    /// Moves once per login this session installed; a request that reads it before and after knows whether a login landed
    /// in between, even one of the same account with the same token (issue #340).
    public private(set) var loginGeneration = 0

    /// Creates a session with its own jar holding `cookies` (expired ones skipped) and the last known `hashCheck`.
    public init(cookies: [StoredCookie] = [], hashCheck: String? = nil, now: Date = Date()) {
        self.init(cookies: cookies, hashCheck: hashCheck, now: now, configuration: .ephemeral, hosts: .forum)
    }

    /// Same, from a base configuration and host policy (tests use no proxy and the loopback host); the configuration's
    /// cookie settings are always overridden.
    init(
        cookies: [StoredCookie], hashCheck: String?, now: Date,
        configuration base: URLSessionConfiguration, hosts: SessionHostPolicy
    ) {
        connection = SessionConnection(configuration: base, hosts: hosts)
        probeConnections = ProbeConnectionPool(configuration: base, hosts: hosts)
        isProbe = false
        self.hosts = hosts
        self.hashCheck = Self.normalizedHashCheck(hashCheck)
        Self.install(cookies, in: connection.cookieStorage, now: now)
    }

    /// A probe of `pool`: a connection taken from it (jar emptied), seeded with `cookies`, no `hash_check`.
    private init(probeOf pool: ProbeConnectionPool, cookies: [StoredCookie], now: Date) {
        connection = pool.checkOut()
        probeConnections = pool
        isProbe = true
        hosts = pool.hosts
        hashCheck = nil
        Self.install(cookies, in: connection.cookieStorage, now: now)
    }

    deinit {
        // Nothing can send through this session any more: a probe's connection serves the next probe, unless an
        // exchange threw (its task may still be running).
        if isProbe {
            probeConnections.checkIn(connection, reusable: !exchangeFailed)
        } else {
            connection.invalidate()
        }
    }

    /// Whether this session's configuration still names its own jar (tests: a probe must not change it, #320).
    func configurationHoldsItsOwnJar() -> Bool {
        urlSession.configuration.httpCookieStorage === cookieStorage
    }

    /// A fresh session holding `cookies`, with this session's host policy and network settings but its own jar and no
    /// `hash_check`: what a session check sends its request through, so a test session restricted to the loopback host
    /// never yields a probe that may reach the forum (#320). Its `URLSession` is recycled from earlier probes of this
    /// account once they are released, with an emptied jar, so that a check can reuse a connection an earlier probe left open
    /// (#1398; the handshakes saved are to be measured on a device, #893).
    package nonisolated func probe(cookies: [StoredCookie], now: Date) -> HFRSession {
        HFRSession(probeOf: probeConnections, cookies: cookies, now: now)
    }

    // MARK: - Transport

    /// Sends `request` with this account's cookies and stores the cookies of the answer.
    ///
    /// Only `hardware.fr` hosts are accepted (`NetworkError.invalidRequest` otherwise), so the jar holds forum cookies
    /// only. A redirect leaving the forum, or from HTTPS to HTTP, is not followed: the 3xx answer is returned and the
    /// caller decides (for example by fetching the target through `AnonymousTransport`).
    public func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        guard hosts.allows(request.url) else {
            throw .invalidRequest(reason: "An account session only contacts hardware.fr")
        }
        do {
            return try await transport.perform(request)
        } catch {
            exchangeFailed = true
            throw error
        }
    }

    // MARK: - hash_check

    /// Records the latest `hash_check` read from a page; an empty or blank value is ignored and the previous one kept.
    public func updateHashCheck(_ value: String?) {
        if let normalized = Self.normalizedHashCheck(value) { hashCheck = normalized }
    }

    // MARK: - Login generation

    /// Records that a login was installed: called once per login, after its cookies and token (`adoptLogin`).
    public func advanceLoginGeneration() {
        // Wrapping: the fences only compare generations for equality, the count itself is never used.
        loginGeneration &+= 1
    }

    // MARK: - Cookies

    /// Every cookie of the jar not expired at `now`, sorted by name, domain and path: what the app persists.
    public func cookies(now: Date = Date()) -> [StoredCookie] {
        (cookieStorage.cookies ?? [])
            .compactMap(StoredCookie.init)
            .filter { !$0.isExpired(at: now) }
            .sorted { $0.jarKey < $1.jarKey }
    }

    /// Adds or replaces cookies by name, domain and path; an already-expired one deletes its match. Returns how many
    /// cookies were installed (Foundation rejects malformed ones).
    @discardableResult
    public func mergeCookies(_ cookies: [StoredCookie], now: Date = Date()) -> Int {
        Self.install(cookies, in: cookieStorage, now: now)
    }

    /// Empties the jar, then installs `cookies`. Returns how many were installed.
    @discardableResult
    public func replaceCookies(with cookies: [StoredCookie], now: Date = Date()) -> Int {
        removeAllCookies()
        return Self.install(cookies, in: cookieStorage, now: now)
    }

    /// Empties the jar (the `hash_check` is kept; it is replaced at the next login).
    public func removeAllCookies() {
        for cookie in cookieStorage.cookies ?? [] { cookieStorage.deleteCookie(cookie) }
    }

    // MARK: - Identity

    /// The account's pseudo key from `md_user`; nil when absent, empty, expired or `deleted` (logged out).
    ///
    /// A `deleted` marker wins over any other `md_user` in the jar: it is the server's explicit logout.
    public func userKey(now: Date = Date()) -> String? {
        let values = cookies(now: now).filter { $0.name == Self.identityCookieName }.map(\.value)
        if values.contains(Self.loggedOutMarker) { return nil }
        return values.first { !$0.isEmpty }
    }

    /// True when the jar holds a usable `md_user` (see `userKey(now:)`).
    public func isLoggedIn(now: Date = Date()) -> Bool {
        userKey(now: now) != nil
    }

    // MARK: - Multi-quote

    /// The multi-quote selection of `token`'s topic, empty when the cookie is absent or expired at `now`.
    public func multiQuote(for token: QuoteSelectionToken, now: Date = Date()) -> MultiQuoteCookie {
        let name = MultiQuoteCookie.name(for: token)
        guard let stored = storedQuoteCookie(named: name, now: now) else { return MultiQuoteCookie(token: token) }
        return MultiQuoteCookie(name: name, value: stored.value)
    }

    /// True when `token`'s message is in its topic's multi-quote selection.
    public func isQuoteSelected(_ token: QuoteSelectionToken, now: Date = Date()) -> Bool {
        multiQuote(for: token, now: now).contains(token.numreponse)
    }

    /// Selects or unselects `token`'s message, rewrites the cookie for one more hour (or deletes it when the selection
    /// becomes empty) and returns the new state.
    @discardableResult
    public func toggleQuote(_ token: QuoteSelectionToken, now: Date = Date()) -> Bool {
        var selection = multiQuote(for: token, now: now)
        let selected = selection.toggle(token.numreponse)
        write(selection, now: now)
        return selected
    }

    /// Unselects the messages `numbers` of `token`'s topic in one actor turn, so a toggle made meanwhile is never reversed; the
    /// cookie goes once nothing is left. A number not selected is left alone (a toggle would select it).
    public func unselectQuotes(_ numbers: [Int], of token: QuoteSelectionToken, now: Date = Date()) {
        var selection = multiQuote(for: token, now: now)
        var changed = false
        for number in numbers where selection.contains(number) {
            _ = selection.toggle(number)
            changed = true
        }
        // Only a change renews the cookie's hour, as a toggle does: a send that released nothing leaves its life alone.
        if changed { write(selection, now: now) }
    }

    /// Deletes the multi-quote selection of `token`'s topic (for example once the quoting reply is posted).
    public func clearQuotes(for token: QuoteSelectionToken) {
        write(MultiQuoteCookie(token: token), now: Date())
    }

    /// Names of the cookies the jar would send to `url` (tests; values stay inside the jar).
    func cookieNames(for url: URL) -> [String] {
        (cookieStorage.cookies(for: url) ?? []).map(\.name).sorted()
    }

    // MARK: - Private

    private func storedQuoteCookie(named name: String, now: Date) -> StoredCookie? {
        let key = StoredCookie(name: name, value: "", domain: MultiQuoteCookie.domain, path: MultiQuoteCookie.path).jarKey
        return cookies(now: now).first { $0.jarKey == key }
    }

    private func write(_ selection: MultiQuoteCookie, now: Date) {
        let key = StoredCookie(name: selection.name, value: "", domain: MultiQuoteCookie.domain, path: MultiQuoteCookie.path)
            .jarKey
        for cookie in cookieStorage.cookies ?? [] where StoredCookie(cookie)?.jarKey == key {
            cookieStorage.deleteCookie(cookie)
        }
        if let cookie = selection.storedCookie(now: now)?.makeHTTPCookie() {
            cookieStorage.setCookie(cookie)
        }
    }

    @discardableResult
    private static func install(_ cookies: [StoredCookie], in storage: HTTPCookieStorage, now: Date) -> Int {
        var installed = 0
        for var stored in cookies {
            // Foundation stores an empty path as `/`; match on that so the key comparison below finds it.
            if stored.path.isEmpty { stored.path = "/" }
            let expired = stored.isExpired(at: now)
            let cookie = expired ? nil : stored.makeHTTPCookie()
            // A malformed cookie is skipped without touching the jar.
            guard expired || cookie != nil else { continue }
            // `StoredCookie.jarKey` ignores a leading dot but Foundation keeps `.hardware.fr` and `hardware.fr` apart:
            // remove every match first so one key never holds two values. An expired import only deletes.
            for existing in storage.cookies ?? [] where StoredCookie(existing)?.jarKey == stored.jarKey {
                storage.deleteCookie(existing)
            }
            guard let cookie else { continue }
            storage.setCookie(cookie)
            installed += 1
        }
        return installed
    }

    private static func normalizedHashCheck(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
