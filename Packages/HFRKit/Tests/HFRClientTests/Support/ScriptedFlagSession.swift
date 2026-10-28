import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// A flag session with scripted answers and a preset token: records every request and every token the flow stores.
actor ScriptedFlagSession: FlagSession {
    private let transport: MockTransport
    /// The token the session starts with; `updateHashCheck` replaces it like `HFRSession` does.
    private(set) var hashCheck: String?
    /// Tokens passed to `updateHashCheck`, in order.
    private(set) var hashChecks: [String?] = []

    init(_ replies: [Result<HTTPResponse, NetworkError>], hashCheck: String? = nil) {
        transport = MockTransport(replies: replies)
        self.hashCheck = hashCheck
    }

    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        try await transport.perform(request)
    }

    func updateHashCheck(_ value: String?) {
        hashChecks.append(value)
        if let value, !value.isEmpty { hashCheck = value }
    }

    /// Every request received, in order.
    var requests: [HTTPRequest] {
        get async { await transport.requests }
    }
}

/// The flag pages of the capture corpus, at the URLs they were captured from.
enum FlagCapture {
    /// Capture id → file name, for the pages the flag tests serve.
    static let files: [String: String] = [
        "P03a": "P03a-addflag-success", "P03b": "P03b-addflag-again", "P03d": "P03d-delflag-favourite-success",
        "W18": "W18-mp-mark-unread-success", "W15": "W15-mp-edit-success", "W17b": "W17b-mp-reply-bad-token-rejected",
        "W17c": "W17c-mp-reply-logged-out-rejected", "W20a": "W20a-mp-reply-flood", "W01": "W01-login-failure",
        "R12": "R12-favourites-anon", "R20": "R20-topic-p1-anon", "R21": "R21-topic-p1-logged-in"
    ]

    /// The page `id` as HFR served it, at its final URL.
    static func page(_ id: String) throws -> Result<HTTPResponse, NetworkError> {
        .success(try response(id))
    }

    /// The page `id` as HFR served it, at its final URL.
    static func response(_ id: String) throws -> HTTPResponse {
        guard let file = files[id] else { throw Capture.Missing(name: id) }
        return try Capture.response(file, url: try finalURL(id))
    }

    /// The URL the capture `id` requested.
    static func requestURL(_ id: String) throws -> URL {
        try url(Capture.meta(id).url)
    }

    /// The URL the capture `id` was finally served from.
    static func finalURL(_ id: String) throws -> URL {
        let meta = try Capture.meta(id)
        return try url(meta.finalURL ?? meta.url)
    }

    static func url(_ raw: String) throws -> URL {
        guard let url = URL(string: raw) else { throw Capture.Missing(name: raw) }
        return url
    }

    /// Every `href` of the page `file` whose path is `path`, `&amp;` decoded, made absolute on the forum.
    static func links(in file: String, path: String) throws -> [URL] {
        let html = try Capture.page(file)
        return html.matches(of: /href="([^"]*)"/).compactMap { match -> URL? in
            let raw = String(match.output.1).replacing("&amp;", with: "&")
            guard raw.hasPrefix(path + "?") else { return nil }
            return URL(string: "https://forum.hardware.fr" + raw)
        }
    }
}
