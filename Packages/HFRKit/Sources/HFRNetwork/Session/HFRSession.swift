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

    private let urlSession: URLSession
    private let cookieStorage: HTTPCookieStorage
    private let transport: URLSessionTransport
    private let hosts: SessionHostPolicy

    /// The anti-CSRF token every POST needs (HFR-PROTOCOL §5); nil until known.
    public private(set) var hashCheck: String?

    /// Creates a session with its own jar holding `cookies` (expired ones skipped) and the last known `hashCheck`.
    public init(cookies: [StoredCookie] = [], hashCheck: String? = nil, now: Date = Date()) {
        self.init(cookies: cookies, hashCheck: hashCheck, now: now, configuration: .ephemeral, hosts: .forum)
    }

    /// Same, from a base configuration and host policy (tests use no proxy and the loopback host); the configuration's
    /// cookie settings are always overridden.
    init(
        cookies: [StoredCookie], hashCheck: String?, now: Date,
        configuration: URLSessionConfiguration, hosts: SessionHostPolicy
    ) {
        // A fresh ephemeral configuration gets its own in-memory jar on every platform (never `.shared`), and it is the
        // only public way to obtain one: corelibs has no public `HTTPCookieStorage` initializer.
        guard let storage = URLSessionConfiguration.ephemeral.httpCookieStorage else {
            preconditionFailure("URLSessionConfiguration.ephemeral provides no cookie storage")
        }
        storage.cookieAcceptPolicy = HTTPCookie.AcceptPolicy.always
        configuration.httpCookieStorage = storage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        // Pages and credentials of one account must not be reused for another: no shared cache or credential store.
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        let urlSession = URLSession(
            configuration: configuration, delegate: HostPolicyRedirectDelegate(policy: hosts), delegateQueue: nil
        )
        self.urlSession = urlSession
        self.hosts = hosts
        self.cookieStorage = storage
        self.transport = URLSessionTransport(session: urlSession)
        self.hashCheck = Self.normalizedHashCheck(hashCheck)
        Self.install(cookies, in: storage, now: now)
    }

    deinit {
        urlSession.finishTasksAndInvalidate()
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
        return try await transport.perform(request)
    }

    // MARK: - hash_check

    /// Records the latest `hash_check` read from a page; an empty or blank value is ignored and the previous one kept.
    public func updateHashCheck(_ value: String?) {
        if let normalized = Self.normalizedHashCheck(value) { hashCheck = normalized }
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
