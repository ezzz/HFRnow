import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// Reads the shared LOT-001 capture corpus in place (a test bundle cannot read `HFRParsingTests` resources).
enum RefreshCapture {
    /// A capture file that could not be read.
    struct Missing: Error, CustomStringConvertible {
        let name: String
        var description: String { "Missing capture \(name)" }
    }

    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Session
        .deletingLastPathComponent() // HFRClientTests
        .deletingLastPathComponent() // Tests
        .appendingPathComponent("HFRParsingTests/Fixtures/captures", isDirectory: true)

    static let profilePage1 = URL(string: "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1")
        ?? URL(fileURLWithPath: "/")

    /// Text of `<file>.html`.
    static func page(_ file: String) throws -> String {
        let url = directory.appendingPathComponent(file + ".html")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw Missing(name: file) }
        return text
    }

    /// The fields of a capture's `<id>.meta.json` the tests use.
    struct Meta {
        let method: String
        let status: Int
        let setCookieNames: [String]
    }

    /// `method`, `status` and `set_cookie_names` of `<id>.meta.json`.
    static func meta(_ id: String) throws -> Meta {
        let url = directory.appendingPathComponent(id + ".meta.json")
        guard
            let data = try? Data(contentsOf: url),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let method = object["method"] as? String,
            let status = object["status"] as? Int,
            let names = object["set_cookie_names"] as? [String]
        else { throw Missing(name: id) }
        return Meta(method: method, status: status, setCookieNames: names)
    }

    /// `file` served as HFR served the captures: 200, UTF-8 HTML, at `url` (profile page 1 by default).
    static func response(_ file: String, url: URL = profilePage1, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            url: url,
            body: Data(try page(file).utf8)
        )
    }
}

/// A probe with one scripted answer. Its jar is a real `HFRSession` that never sends anything, so `userKey(now:)` and
/// cookie merging are the production rules.
actor ScriptedProbe: RefreshProbe {
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

    func make(cookies: [StoredCookie], now: Date) -> any RefreshProbe {
        let probe = ScriptedProbe(seed: cookies, now: now, step: step)
        lock.lock()
        defer { lock.unlock() }
        made.append(probe)
        return probe
    }
}
