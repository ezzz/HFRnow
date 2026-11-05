import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// The captured pages of the storage flows, at the URLs they were captured from.
enum MPStorageCapture {
    static let post = 3_157_083
    static let numreponse = 1_980_164_061

    /// The MP list page `id` (`R13a` without the thread, `R13u1` with it).
    static func list(_ id: String) throws -> Result<HTTPResponse, NetworkError> {
        let files = ["R13a": "R13a-mp-list", "R13u1": "R13u1-mp-list-recipient-unread"]
        guard let file = files[id] else { throw Capture.Missing(name: id) }
        return .success(try Capture.response(file, url: PostingCapture.url(try Capture.meta(id).url)))
    }

    /// The storage thread's first page (`R60a`).
    static func threadPage() throws -> Result<HTTPResponse, NetworkError> {
        .success(try Capture.response("R60a-mpstorage-thread-first-post", url: PostingCapture.url(try Capture.meta("R60a").url)))
    }

    /// The first message's edit form (`R60b`), holding `text` instead of the captured document when given.
    ///
    /// The replaced text stands for what HFR stores after an edit: the text as sent, byte for byte (`R43a`, X11).
    static func editForm(holding text: String? = nil) throws -> Result<HTTPResponse, NetworkError> {
        var page = try Capture.page("R60b-mpstorage-edit-form-first-post")
        if let text {
            let pattern = /(<textarea[^>]*name="content_form"[^>]*>)[^<]*(<\/textarea>)/
            page = page.replacing(pattern) { match in "\(match.1)\(escaped(text))\(match.2)" }
        }
        return .success(
            HTTPResponse(
                statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"],
                url: try editURL(), body: Data(page.utf8)
            )
        )
    }

    /// The URL `R60b` was captured from.
    static func editURL() throws -> URL {
        PostingCapture.url(try Capture.meta("R60b").url)
    }

    /// The document `R60b` holds, as the LOT-004 oracle read it.
    static let storedText = """
        {"data":[{"version":"0.1","blacklist":{"list":[],"sourceName":"iOS","lastUpdate":1745779603553},\
        "mpFlags":{"list":[],"sourceName":"iOS","lastUpdate":1745779603553},\
        "bookmarks":{"list":[],"sourceName":"iOS","lastUpdate":1745779603553},\
        "sourceName":"iOS","lastUpdate":1745779603553}],"sourceName":"iOS","lastUpdate":1745779603553}
        """

    /// A page answered with `status` and no body, at `url`.
    static func status(_ status: Int, url: URL) -> Result<HTTPResponse, NetworkError> {
        .success(HTTPResponse(statusCode: status, headers: ["Location": "/"], url: url, body: Data()))
    }

    private static func escaped(_ text: String) -> String {
        text.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing("\"", with: "&#034;")
    }
}

/// Runs one transport operation against scripted answers.
enum MPStorageHarness {
    struct Outcome<Value> {
        let result: Result<Value, MPStorageTransportError>
        let requests: [HTTPRequest]

        var error: MPStorageTransportError? {
            if case let .failure(error) = result { return error }
            return nil
        }
        var value: Value? { try? result.get() }
        var posts: [HTTPRequest] { requests.filter { $0.method == .post } }

        /// Name/value pairs of the only POST.
        var postFields: [(name: String, value: String)] {
            guard posts.count == 1, let body = posts[0].body.flatMap({ String(bytes: $0, encoding: .utf8) }) else { return [] }
            return PostingHarness.pairs(of: body)
        }

        func postField(_ name: String) -> String? {
            postFields.first { $0.name == name }?.value
        }
    }

    static func run<Value>(
        _ replies: [Result<HTTPResponse, NetworkError>],
        _ operation: (MPStorageTransport, ScriptedPostingSession) async throws(MPStorageTransportError) -> Value
    ) async -> Outcome<Value> {
        let session = ScriptedPostingSession(replies)
        let result: Result<Value, MPStorageTransportError>
        do throws(MPStorageTransportError) {
            result = .success(try await operation(MPStorageTransport(), session))
        } catch {
            result = .failure(error)
        }
        return Outcome(result: result, requests: await session.requests)
    }
}
