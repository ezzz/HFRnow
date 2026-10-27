import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// A login jar with scripted answers: each step returns its reply and stores the cookies the server would have set.
///
/// The cookies go into a real `HFRSession` that never sends anything, so `userKey(now:)` is the production rule.
actor ScriptedLoginJar: LoginJar {
    /// One scripted exchange.
    struct Step: Sendable {
        var reply: Result<HTTPResponse, NetworkError>
        var setCookies: [StoredCookie] = []
        /// Cancels the calling task while answering (the actor method runs in the caller's task).
        var cancelsCaller = false
    }

    private var steps: [Step]
    private let jar = HFRSession()
    /// Every request received, in order.
    private(set) var requests: [HTTPRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw .unscripted }
        let step = steps.removeFirst()
        await jar.mergeCookies(step.setCookies)
        if step.cancelsCaller { withUnsafeCurrentTask { $0?.cancel() } }
        return try step.reply.get()
    }

    func cookies(now: Date) async -> [StoredCookie] {
        await jar.cookies(now: now)
    }

    func userKey(now: Date) async -> String? {
        await jar.userKey(now: now)
    }
}

/// Hands out one prepared jar and counts how many the flow asked for.
final class JarFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let jar: ScriptedLoginJar
    private var made = 0

    init(_ jar: ScriptedLoginJar) {
        self.jar = jar
    }

    /// Number of jars the flow created.
    var jarsMade: Int {
        lock.lock()
        defer { lock.unlock() }
        return made
    }

    func make() -> any LoginJar {
        lock.lock()
        defer { lock.unlock() }
        made += 1
        return jar
    }
}
