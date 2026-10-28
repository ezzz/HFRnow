import Foundation
import HFRModels
import HFRNetwork
@testable import HFRClient

/// Runs one write against scripted pages: the form page, then (when the flow gets that far) the answer.
enum PostingHarness {
    typealias Write = @Sendable (PostingFlow, PostingForm) async throws(PostingError) -> PostingResult

    /// What a run produced.
    struct Outcome {
        let result: Result<PostingResult, PostingError>
        let requests: [HTTPRequest]
        let hashChecks: [String?]

        /// The POST, when one was sent.
        var post: HTTPRequest? { requests.first { $0.method == .post } }
        /// The POST body as sent.
        var body: String? { post?.body.flatMap { String(bytes: $0, encoding: .utf8) } }
        /// The error, when the run failed.
        var error: PostingError? {
            if case let .failure(error) = result { return error }
            return nil
        }
    }

    /// Loads `formPage` from `formURL` and runs `write` with it; `answer` is served to the POST.
    static func run(
        formPage: Result<HTTPResponse, NetworkError>,
        formURL: URL,
        answer: Result<HTTPResponse, NetworkError>? = nil,
        write: Write
    ) async -> Outcome {
        let session = ScriptedPostingSession([formPage] + (answer.map { [$0] } ?? []))
        let flow = PostingFlow()
        let result: Result<PostingResult, PostingError>
        do {
            let form = try await flow.loadForm(at: formURL, through: session)
            result = .success(try await write(flow, form))
        } catch {
            result = .failure(error)
        }
        return Outcome(result: result, requests: await session.requests, hashChecks: await session.hashChecks)
    }

    /// Runs `write` on the captured form `formID`, answered by the captured `answerID`.
    static func run(form formID: String, answer answerID: String? = nil, write: Write) async throws -> Outcome {
        let answer = try answerID.map { try PostingCapture.answer($0) }
        return await run(
            formPage: try PostingCapture.form(formID), formURL: try PostingCapture.pageURL(formID), answer: answer, write: write
        )
    }

    /// The captured page `formID` with `edit` applied: for structural edges only (a removed attribute, an added one).
    static func editedForm(_ formID: String, _ edit: (String) -> String) throws -> Result<HTTPResponse, NetworkError> {
        guard let file = PostingCapture.forms[formID] else { throw Capture.Missing(name: formID) }
        let page = edit(try Capture.page(file))
        return .success(
            HTTPResponse(
                statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"],
                url: try PostingCapture.pageURL(formID), body: Data(page.utf8)
            )
        )
    }

    /// Name/value pairs of a captured `request_body` (`+` is a space, `%XX` a UTF-8 byte).
    static func pairs(of body: String) -> [(name: String, value: String)] {
        body.split(separator: "&", omittingEmptySubsequences: false).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            func decode(_ part: Substring?) -> String {
                String(part ?? "").replacing("+", with: " ").removingPercentEncoding ?? ""
            }
            return (decode(parts.first), decode(parts.count > 1 ? parts[1] : nil))
        }
    }

    /// The captured body of `answerID` as a browser would have sent it: the legacy `"0"` of unchecked boxes dropped
    /// (a browser sends nothing for them) and every line break written CRLF.
    static func browserBody(of answerID: String, checkboxes: Set<String>) throws -> String {
        guard let raw = try Capture.meta(answerID).requestBody else { throw Capture.Missing(name: answerID + " body") }
        let kept = pairs(of: raw).filter { !(checkboxes.contains($0.name) && $0.value == "0") }
        return FormBody(kept, newlines: .crlf).encodedString
    }
}
