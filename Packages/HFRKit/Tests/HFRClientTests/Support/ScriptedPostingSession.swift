import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// A posting session with scripted answers: records every request and every token the flow stores.
actor ScriptedPostingSession: PostingSession {
    private let transport: MockTransport
    /// Tokens passed to `updateHashCheck`, in order.
    private(set) var hashChecks: [String?] = []

    init(_ replies: [Result<HTTPResponse, NetworkError>]) {
        transport = MockTransport(replies: replies)
    }

    init(handler: @escaping MockTransport.Handler) {
        transport = MockTransport(handler: handler)
    }

    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        try await transport.perform(request)
    }

    func updateHashCheck(_ value: String?) {
        hashChecks.append(value)
    }

    /// Every request received, in order.
    var requests: [HTTPRequest] {
        get async { await transport.requests }
    }
}

/// Form pages and write answers of the capture corpus, at the URLs they were captured from.
enum PostingCapture {
    /// File name of each form capture used by the posting tests; the page URL is its meta's `url` (equal to `final_url`).
    static let forms: [String: String] = [
        "R40a": "R40a-reply-form-logged-in", "R40b": "R40b-reply-form-anon", "R41a": "R41a-quote-form",
        "R41b": "R41b-quote-form-of-quoting-post", "R42": "R42-multiquote-form-cookie", "R43a": "R43a-mp-edit-form-first-post",
        "R43b": "R43b-mp-edit-form-lf-post", "R43c": "R43c-mp-edit-form-nonbmp-post", "R44": "R44-mp-edit-form-other-account-message",
        "R45a": "R45a-new-topic-form", "R45b": "R45b-new-mp-form", "R47a": "R47a-mp-quote-form", "R47b": "R47b-mp-reply-composer",
        "R47c": "R47c-mp-composer-multiquote-cookie", "R47u1": "R47u1-mp-reply-composer-recipient",
        "R61b": "R61b-public-reply-composer", "R62a": "R62a-public-edit-form-later-post"
    ]

    /// The write answers, by capture id.
    static let answers: [String: String] = [
        "W10": "W10-mp-create-crlf-success", "W11": "W11-mp-reply-lf-legacy-success", "W11x": "W11x-mp-create-second-topic-flood",
        "W12": "W12-mp-reply-nonbmp-success", "W13b": "W13b-mp-reply-browser-semantics-success",
        "W13c": "W13c-mp-reply-recipient-success", "W13cx": "W13cx-mp-reply-flood-other-account",
        "W14": "W14-mp-reply-multiquote-success", "W14x": "W14x-mp-reply-flood-fourth-consecutive", "W15": "W15-mp-edit-success",
        "W16a": "W16a-mp-delete-post-success", "W16b": "W16b-mp-delete-post-again", "W17a": "W17a-mp-reply-empty-body-rejected",
        "W17b": "W17b-mp-reply-bad-token-rejected", "W17c": "W17c-mp-reply-logged-out-rejected",
        "W19": "W19-mp-delete-first-post-success", "W20a": "W20a-mp-reply-flood", "W20b": "W20b-mp-reply-flood-again"
    ]

    static func url(_ raw: String) -> URL {
        URL(string: raw) ?? URL(fileURLWithPath: "/")
    }

    /// The form page `id` as HFR served it.
    static func form(_ id: String) throws -> Result<HTTPResponse, NetworkError> {
        guard let file = forms[id] else { throw Capture.Missing(name: id) }
        return .success(try Capture.response(file, url: try pageURL(id)))
    }

    /// The answer `id` as HFR served it, at its POST URL.
    static func answer(_ id: String) throws -> Result<HTTPResponse, NetworkError> {
        guard let file = answers[id] else { throw Capture.Missing(name: id) }
        return .success(try Capture.response(file, url: url(try Capture.meta(id).url)))
    }

    /// The form's page URL.
    static func pageURL(_ id: String) throws -> URL {
        url(try Capture.meta(id).url)
    }
}
