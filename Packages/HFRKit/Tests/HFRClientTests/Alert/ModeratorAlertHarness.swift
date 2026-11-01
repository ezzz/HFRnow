import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// Runs an alert against scripted pages: the alert page, then (when the flow gets that far) the answer to the POST.
enum ModeratorAlertHarness {
    /// `R46`'s request: the alert link of message 2666649 on `R21`.
    static let link = PostingCapture.url(
        "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649&page=1&ref=1"
    )

    /// What a run produced.
    struct Outcome {
        let page: Result<ModeratorAlertPage, ModeratorAlertError>
        let answer: Result<ModeratorAlertAnswer, ModeratorAlertError>?
        let requests: [HTTPRequest]
        let hashChecks: [String?]

        /// The POST, when one was sent.
        var post: HTTPRequest? { requests.first { $0.method == .post } }
        /// The POST body as name/value pairs, decoded.
        var pairs: [[String]] {
            guard let body = post?.body.flatMap({ String(bytes: $0, encoding: .utf8) }) else { return [] }
            return body.split(separator: "&").map { pair in
                pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map {
                    String($0).replacing("+", with: " ").removingPercentEncoding ?? ""
                }
            }
        }
        /// The error of the step that failed.
        var error: ModeratorAlertError? {
            if case let .failure(error) = page { return error }
            if case let .failure(error)? = answer { return error }
            return nil
        }
    }

    /// `R46` as HFR served it at its URL.
    static func formPage() throws -> Result<HTTPResponse, NetworkError> {
        .success(try Capture.response("R46-modo-alert-form", url: link))
    }

    /// A small alert page whose body is `html` (the rule's inputs, not a page state), served at `R46`'s URL.
    static func fragment(_ html: String) -> Result<HTTPResponse, NetworkError> {
        .success(HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: link, body: Data(html.utf8)))
    }

    /// Prepares `link` against `page`; when it gives the form and `reason` is set, submits it, answered by `answer`.
    static func run(
        link: URL = link,
        page: Result<HTTPResponse, NetworkError>,
        reason: String? = nil,
        answer: Result<HTTPResponse, NetworkError>? = nil
    ) async -> Outcome {
        let session = ScriptedPostingSession([page] + (answer.map { [$0] } ?? []))
        let flow = ModeratorAlertFlow()
        let prepared: Result<ModeratorAlertPage, ModeratorAlertError>
        do {
            prepared = .success(try await flow.prepare(link: link, through: session))
        } catch {
            prepared = .failure(error)
        }
        var submitted: Result<ModeratorAlertAnswer, ModeratorAlertError>?
        if let reason, case let .success(.form(form)) = prepared {
            do {
                submitted = .success(try await flow.submit(reason: reason, with: form))
            } catch {
                submitted = .failure(error)
            }
        }
        return Outcome(page: prepared, answer: submitted, requests: await session.requests, hashChecks: await session.hashChecks)
    }
}
