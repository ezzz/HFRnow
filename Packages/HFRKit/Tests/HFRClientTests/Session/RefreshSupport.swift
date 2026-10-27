import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// A probe with one scripted answer. Its jar is a real `HFRSession` that never sends anything, so `userKey(now:)` and
/// cookie merging are the production rules.
actor ScriptedProbe: SessionJar {
    /// The scripted exchange.
    struct Step: Sendable {
        var reply: Result<HTTPResponse, NetworkError>
        /// Cookies the answer sets; an expired one deletes its match, as a server's removal does.
        var setCookies: [StoredCookie] = []
        /// Runs while the request is in flight (a concurrent change of the account session).
        var during: (@Sendable () async -> Void)?
        /// Cancels the calling task while answering.
        var cancelsCaller = false
    }

    private var step: Step?
    private let jar: HFRSession
    /// The cookies the probe was seeded with.
    let seed: [StoredCookie]
    private let now: Date
    /// Every request received.
    private(set) var requests: [HTTPRequest] = []

    init(seed: [StoredCookie], now: Date, step: Step) {
        self.seed = seed
        self.now = now
        self.step = step
        self.jar = HFRSession(cookies: seed, now: now)
    }

    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        requests.append(request)
        guard let current = step else { throw .unscripted }
        step = nil
        await jar.mergeCookies(current.setCookies, now: now)
        if let during = current.during { await during() }
        if current.cancelsCaller { withUnsafeCurrentTask { $0?.cancel() } }
        return try current.reply.get()
    }

    func cookies(now: Date) async -> [StoredCookie] {
        await jar.cookies(now: now)
    }

    func userKey(now: Date) async -> String? {
        await jar.userKey(now: now)
    }
}

/// Makes the scripted probes a flow asks for and keeps them for inspection.
final class ProbeFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let step: ScriptedProbe.Step
    private var made: [ScriptedProbe] = []

    init(_ step: ScriptedProbe.Step) {
        self.step = step
    }

    /// The probes created so far.
    var probes: [ScriptedProbe] {
        lock.lock()
        defer { lock.unlock() }
        return made
    }

    func make(cookies: [StoredCookie], now: Date) -> any SessionJar {
        let probe = ScriptedProbe(seed: cookies, now: now, step: step)
        lock.lock()
        defer { lock.unlock() }
        made.append(probe)
        return probe
    }
}
