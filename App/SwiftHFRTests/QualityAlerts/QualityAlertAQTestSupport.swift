import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// A scripted AQ host serving the captured answers by path, and counting what reached it.
actor AQScriptedHost {
    private(set) var gets = 0
    private(set) var posts = 0
    private(set) var lastPostBody: String?
    private let alerts: Data?
    private let create: Data?

    init(alerts: Data?, create: Data?) {
        self.alerts = alerts
        self.create = create
    }

    /// While set, a GET waits (after being counted) until `release()`: a check still in flight.
    private var held: CheckedContinuation<Void, Never>?
    private var holds = false

    func holdGets() { holds = true }

    func release() {
        holds = false
        held?.resume()
        held = nil
    }

    func handle(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        if request.method == .post {
            posts += 1
            lastPostBody = request.body.flatMap { String(data: $0, encoding: .utf8) }
            // Without a capture of the answer, the exchange fails: an unconfirmed create, never a hand-built refusal.
            guard let create else { throw .timedOut }
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/plain;charset=UTF-8"], url: request.url, body: create)
        }
        gets += 1
        if holds { await withCheckedContinuation { held = $0 } }
        guard let alerts else { throw .timedOut }
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/xml;charset=UTF-8"], url: request.url, body: alerts)
    }
}

/// The outcomes the model announced.
@MainActor
final class AQAnnouncements {
    private(set) var messages: [String] = []
    func announce(_ text: String) { messages.append(text) }
}

/// What a test drives: the model, the host it talks to, and the outcomes it announced.
@MainActor
struct AQRig {
    let model: QualityAlertActionModel
    let transport: AQRigTransport
    let announcements: AQAnnouncements

    var messages: [String] { announcements.messages }
}

/// The counters of the scripted host, read by the tests.
struct AQRigTransport {
    let host: AQScriptedHost
    var posts: Int { get async { await host.posts } }
    var gets: Int { get async { await host.gets } }
    var lastPostBody: String? { get async { await host.lastPostBody } }
}

enum QualityAlertAQTestSupport {
    static let captures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures")

    static func capture(_ name: String?) throws -> Data? {
        try name.map { try Data(contentsOf: captures.appending(path: $0)) }
    }

    @MainActor
    static func rig(
        alerts: String?, create: String?, accepted: Bool = false, pseudo: String = "user4"
    ) throws -> AQRig {
        let host = AQScriptedHost(alerts: try capture(alerts), create: try capture(create))
        let transport = MockTransport { request async throws(NetworkError) -> HTTPResponse in try await host.handle(request) }
        let base = try #require(URL(string: "https://aq.super-h.fr"))
        let client = AQClient(configuration: try AQConfiguration(baseURL: base), transport: transport)
        let store = InMemorySettingsStore()
        if accepted { store.setRawValue(.bool(true), forKey: QualityAlertActionModel.noticeKey) }
        let services = QualityAlertServices(service: client, pseudo: pseudo, hostName: "aq.super-h.fr", settings: store)
        let announcements = AQAnnouncements()
        let model = QualityAlertActionModel(
            services: services, topicTitle: { "AQ local topic" }, confirm: { announcements.announce($0) }
        )
        return AQRig(model: model, transport: AQRigTransport(host: host), announcements: announcements)
    }

    /// The alerts of a capture, parsed by the real parser.
    static func alerts(_ name: String) async throws -> [AQAlert] {
        let data = try #require(try capture(name))
        return try AQAlertListParser.parse(try #require(String(bytes: data, encoding: .utf8)))
    }

    static let permalink = URL(string: "https://forum.hardware.fr/hfr/Discussions/Societe/aq-local-topic-sujet_700001_1.htm#t700102")

    static func context(
        numreponse: Int = 700_102, topic: TopicID? = TopicID(category: .forum(13), topic: 700_001),
        permalink: URL? = QualityAlertAQTestSupport.permalink
    ) -> MessageMenuContext {
        MessageMenuContext(numreponse: numreponse, author: "user4", actions: MessageActions(), permalinkURL: permalink, topic: topic)
    }

    static func draft(
        topic: Int = 700_001, numreponse: Int = 700_102, permalink: URL? = QualityAlertAQTestSupport.permalink
    ) -> QualityAlertActionModel.Draft {
        QualityAlertActionModel.Draft(
            topic: TopicID(category: .forum(13), topic: topic), topicTitle: "AQ local topic", numreponse: numreponse,
            permalink: permalink ?? URL(fileURLWithPath: "/"), author: "user4", existing: nil
        )
    }
}
