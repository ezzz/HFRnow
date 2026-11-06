import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Runs one group roster change on scripted pages, with a scripted session check (LOT-058).
enum GroupRosterHarness {
    typealias Reply = Result<HTTPResponse, NetworkError>

    /// What one change did.
    struct Run {
        var result: Result<GroupRosterChange, GroupRosterError>
        var requests: [HTTPRequest]
        var checks: Int

        var posts: [HTTPRequest] { requests.filter { $0.method == .post } }
        var error: GroupRosterError? {
            if case .failure(let error) = result { return error }
            return nil
        }
        /// `newdest` as sent, each occurrence.
        var newdest: [String] {
            posts.compactMap { $0.body.flatMap { String(bytes: $0, encoding: .utf8) } }
                .flatMap(PostingHarness.pairs(of:)).filter { $0.name == "newdest" }.map(\.value)
        }
    }

    static let text = "Private message content removed."

    /// Loads the form `id`, then asks for `members`; `replies` answer what follows the form.
    static func run(
        form id: String, members: [String], text: String = text, replies: [Reply] = [],
        check: Result<SessionHealth, NetworkError> = .success(.valid)
    ) async throws -> Run {
        let session = ScriptedPostingSession([try PostingCapture.form(id)] + replies)
        let form = try await PostingFlow().loadForm(at: try PostingCapture.pageURL(id), through: session)
        return await run(form, session, members: members, text: text, check: check)
    }

    static func run(
        _ form: PostingForm, _ session: ScriptedPostingSession, members: [String], text: String = text,
        check: Result<SessionHealth, NetworkError> = .success(.valid)
    ) async -> Run {
        var checks = 0
        var result: Result<GroupRosterChange, GroupRosterError>
        do throws(GroupRosterError) {
            result = .success(
                try await GroupRosterFlow().changeMembers(
                    to: members, text: text, options: [:], with: form
                ) { () async throws(NetworkError) in
                    checks += 1
                    return try check.get()
                }
            )
        } catch {
            result = .failure(error)
        }
        return Run(result: result, requests: await session.requests, checks: checks)
    }

    static func sentNothing(_ run: Run) {
        #expect(run.requests.count == 1)
        #expect(run.posts.isEmpty)
    }
}
