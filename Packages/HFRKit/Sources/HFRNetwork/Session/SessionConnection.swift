import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization

/// One `URLSession` with its own in-memory cookie jar, as an `HFRSession` sends through it.
///
/// `@unchecked Sendable`: the stored properties are immutable or behind a `Mutex`, `URLSession` and `URLSessionTransport`
/// are Sendable, and `HTTPCookieStorage` is documented thread-safe; the jar is only written by the one `HFRSession` that
/// holds the connection at a time, and by the pool while no session holds it (`ProbeConnectionPool`).
final class SessionConnection: @unchecked Sendable {
    let urlSession: URLSession
    let cookieStorage: HTTPCookieStorage
    let transport: URLSessionTransport
    private let invalidated = Mutex(false)

    /// Whether `invalidate()` ran (tests).
    var isInvalidated: Bool { invalidated.withLock { $0 } }

    /// A new connection from a copy of `base` (the caller's configuration is never changed), with cookies on, its own
    /// jar, no shared cache or credential store, and redirects limited to `hosts`.
    init(configuration base: URLSessionConfiguration, hosts: SessionHostPolicy) {
        // `URLSession.configuration` is one stored object on Linux (a copy per read on Darwin): write a copy, so the
        // configuration a caller passes, another session's included (`probe`), is never changed.
        guard let configuration = base.copy() as? URLSessionConfiguration else {
            preconditionFailure("URLSessionConfiguration.copy() returned another type")
        }
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
        urlSession = URLSession(
            configuration: configuration, delegate: HostPolicyRedirectDelegate(policy: hosts), delegateQueue: nil
        )
        cookieStorage = storage
        transport = URLSessionTransport(session: urlSession)
    }

    /// Ends the session once its running tasks finish; the connection is never used again.
    func invalidate() {
        invalidated.withLock { $0 = true }
        urlSession.finishTasksAndInvalidate()
    }

    /// Empties the jar (a recycled connection starts a probe with nothing of the previous one).
    func emptyJar() {
        for cookie in cookieStorage.cookies ?? [] { cookieStorage.deleteCookie(cookie) }
    }
}

/// The connections the probes of one account session send through, recycled between probes (#1398).
///
/// A probe (`HFRSession.probe(cookies:now:)`) used to open a new `URLSession`, so every session check, MP poll and
/// gated write's check paid a new TCP + TLS handshake. Recycling the `URLSession` lets a probe reuse a connection a
/// previous one left open (intent: the count of `URLSession`s is tested, the handshakes saved are to be measured on a
/// device, #893). A probe now takes an idle connection from here (or a new one),
/// with its jar emptied before the probe's seed is installed, and gives it back when the probe is released. Two probes
/// alive at the same time never share a connection, so never a jar; a connection whose last exchange threw (timeout,
/// cancellation, transport failure) is not given back, so a late answer can never write into the next probe's jar.
package final class ProbeConnectionPool: Sendable {
    /// Idle connections kept; a probe released while this many wait is invalidated instead.
    static let idleLimit = 2

    private struct State {
        var configuration: URLSessionConfiguration
        var idle: [SessionConnection] = []
        var created = 0
    }

    private let state: Mutex<State>
    let hosts: SessionHostPolicy

    /// A pool whose connections copy `configuration` (copied here too, so later changes to it are not seen).
    init(configuration: URLSessionConfiguration, hosts: SessionHostPolicy) {
        guard let copy = configuration.copy() as? URLSessionConfiguration else {
            preconditionFailure("URLSessionConfiguration.copy() returned another type")
        }
        state = Mutex(State(configuration: copy))
        self.hosts = hosts
    }

    deinit {
        state.withLock { state in
            for connection in state.idle { connection.invalidate() }
            state.idle.removeAll()
        }
    }

    /// How many connections the pool opened since it was created (tests: a probe that reuses one opens none).
    package var connectionsCreated: Int { state.withLock { $0.created } }

    /// How many connections wait for a probe.
    var idleCount: Int { state.withLock { $0.idle.count } }

    /// An idle connection with an empty jar, or a new one.
    func checkOut() -> SessionConnection {
        let reused: SessionConnection? = state.withLock { state in state.idle.popLast() }
        if let reused {
            reused.emptyJar()
            return reused
        }
        return state.withLock { state in
            state.created += 1
            return SessionConnection(configuration: state.configuration, hosts: hosts)
        }
    }

    /// Takes `connection` back for the next probe, or invalidates it when `reusable` is false or the pool is full.
    func checkIn(_ connection: SessionConnection, reusable: Bool) {
        // Emptied before it is idle: once in `idle`, another thread may take it and seed it at once.
        if reusable { connection.emptyJar() }
        let kept = reusable && state.withLock { state in
            guard state.idle.count < Self.idleLimit else { return false }
            state.idle.append(connection)
            return true
        }
        if !kept { connection.invalidate() }
    }
}
