import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Reads the AQ ("Alerte Qualitay") service: the RSS feed behind the badge and the per-topic "already reported" check.
///
/// Replaces legacy `AQBadgeCheckService` and `AQPlusViewModel` (`AQPlusView.swift:60-92, 248-322` @ 2440d79) and
/// `isAQAlreadySignaled` (`MessagesView.swift:325-338` @ 2440d79). AQ is a third party (HFR-PROTOCOL §8, LOT-071 T1, T2):
/// the default transport is `AnonymousTransport`, so no forum cookie is ever sent (R1), requests go only to the configured
/// host and a redirect is never followed. `create(_:)` writes to that third party: one POST, never retried.
public struct AQClient: Sendable {
    /// Time limit of each request, in seconds (legacy feed request, `AQPlusView.swift:73, 278` @ 2440d79).
    public static let timeout: Double = 20
    /// Largest answer read, in bytes: `T01` (25 items) is 31 KB and `T02` (123 alerts) 13 KB.
    public static let maximumResponseBytes = 1_048_576

    private let configuration: AQConfiguration
    let transport: any HTTPTransport

    /// Creates a client; the transport is an injection point for tests.
    public init(configuration: AQConfiguration, transport: any HTTPTransport = AnonymousTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Every feed item, in document order and with its category (hiding category 25 is app policy, Q-7).
    public func feed() async throws(AQError) -> [AQFeedItem] {
        let text = try await fetch(configuration.feedURL())
        do {
            return try AQFeedParser.parse(text)
        } catch {
            throw .invalidResponse(error)
        }
    }

    /// The AQs already raised on `topicID`, newest first as served.
    public func alerts(topicID: Int) async throws(AQError) -> [AQAlert] {
        let text = try await fetch(configuration.alertsURL(topicID: topicID))
        do {
            return try AQAlertListParser.parse(text)
        } catch {
            throw .invalidResponse(error)
        }
    }

    /// Whether message `postID` of `topicID` is already in an AQ (legacy `isAQAlreadySignaled`, whole-number match).
    public func isReported(postID: Int, topicID: Int) async throws(AQError) -> Bool {
        AQAlertListParser.isReported(postID: postID, in: try await alerts(topicID: topicID))
    }

    /// Number of `items` published at or after `lastCheck`, the "new since" badge (legacy `aqDate >= lastCheckDate`,
    /// `AQPlusView.swift:202-204` @ 2440d79). An item without a readable date is not counted: legacy dated it "now", so it
    /// stayed new on every check and the badge never cleared. Filter the items first when the app hides a category.
    public static func newCount(in items: [AQFeedItem], since lastCheck: Date) -> Int {
        items.count { isNew($0, since: lastCheck) }
    }

    /// Whether `item` is new since `lastCheck` (see `newCount(in:since:)`).
    public static func isNew(_ item: AQFeedItem, since lastCheck: Date) -> Bool {
        guard let publishedAt = item.publishedAt else { return false }
        return publishedAt >= lastCheck
    }

    /// Timeout of the create (legacy `createAQ`, `MessagesView.swift:340-376` @ 2440d79).
    public static let createTimeout: Double = 5
    /// Largest create answer read: the captured one is the single byte `1`.
    static let maximumCreateAnswerBytes = 4096

    /// Reports a message to AQ (a new AQ, or an addition when `report.existingAlertID` is set).
    ///
    /// The report is validated first (`AQCreateError.invalidReport`, nothing sent). Success is only status 200 with the body `1`
    /// (`T50`, `T51`); every other answer, a redirect and any failure after the request left is `unconfirmed`: refusals are
    /// not captured on the live host (and some ban the client), so none is read as a refusal and none as a success. Never
    /// retried, never followed; the app sends one create at a time and tells the user first (LOT-071 N1).
    public func create(_ report: AQNewReport) async throws(AQCreateError) {
        let form = try AQReportEncoder.form(for: report)
        let url: URL
        do { url = try configuration.createURL() } catch { throw .invalidBaseURL }
        var request = HTTPRequest.post(url, form: form, timeout: Self.createTimeout, redirectPolicy: .doNotFollow)
        request.maximumBodyBytes = Self.maximumCreateAnswerBytes
        // Nothing has left the device yet: a cancellation here is a plain failure, not an unknown outcome (LOT-048).
        if Task.isCancelled { throw .cancelled }
        let response: HTTPResponse
        do {
            response = try await transport.perform(request)
        } catch {
            throw .unconfirmed(.transport(error))
        }
        if response.isRedirect || (300...399).contains(response.statusCode) {
            throw .unconfirmed(.redirected(statusCode: response.statusCode))
        }
        let answer = response.decodedText().text.trimmingCharacters(in: .whitespacesAndNewlines)
        if response.statusCode == 200, answer == "1" { return }
        let isCode = !answer.isEmpty && answer.count <= 4 && answer.allSatisfy { $0 == "-" || $0.isASCII && $0.isNumber }
        throw .unconfirmed(.unrecognizedAnswer(statusCode: response.statusCode, code: isCode ? answer : nil))
    }

    private func fetch(_ url: URL) async throws(AQError) -> String {
        let request = HTTPRequest(
            url: url, timeout: Self.timeout, redirectPolicy: .doNotFollow, maximumBodyBytes: Self.maximumResponseBytes
        )
        let response: HTTPResponse
        do {
            response = try await transport.perform(request)
        } catch {
            throw .network(error)
        }
        if response.isRedirect || (300...399).contains(response.statusCode) {
            throw .redirected(statusCode: response.statusCode)
        }
        guard (200...299).contains(response.statusCode) else { throw .http(statusCode: response.statusCode) }
        return response.decodedText().text
    }
}
