import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Issue #342: a form loaded before a logout, or before a login of another account in the same session, is refused
/// locally (`sessionChanged`, no POST); a re-login of the same account still sends it, for HFR to judge (#315).
@Suite("Posting flow: a form is submitted only by the account that loaded it")
struct PostingSessionChangeTests {
    typealias Write = @Sendable (PostingFlow, PostingForm) async throws(PostingError) -> PostingResult

    /// A fake token, read with the new cookies.
    static let fresher = "fresher-token-0456"

    /// One write entry point and a captured form it accepts.
    struct Entry: Sendable, CustomTestStringConvertible {
        let name: String
        let formID: String
        let write: Write

        var testDescription: String { "\(name) (\(formID))" }
    }

    /// Every write entry point; each one ends in `submit`.
    static let writes: [Entry] = [
        Entry(name: "reply", formID: "R40a") { flow, form async throws(PostingError) in try await flow.reply("Texte", with: form) },
        Entry(name: "newTopic", formID: "R45a") { flow, form async throws(PostingError) in
            try await flow.newTopic(subject: "Sujet", text: "Texte", with: form)
        },
        Entry(name: "newPrivateMessage", formID: "R45b") { flow, form async throws(PostingError) in
            try await flow.newPrivateMessage(to: "dest", subject: "Sujet", text: "Texte", with: form)
        },
        Entry(name: "edit", formID: "R43b") { flow, form async throws(PostingError) in try await flow.edit("Texte", with: form) },
        Entry(name: "delete", formID: "R43b") { flow, form async throws(PostingError) in try await flow.delete(with: form) }
    ]

    /// What a run left: the write's error, every request, the session's login generation.
    struct Outcome {
        let error: PostingError?
        let requests: [HTTPRequest]
        let generation: Int
    }

    /// Loads `formID`, runs `between` on the session, then `write`; `answer` is served to a POST.
    private func run(
        formID: String,
        answer: String? = nil,
        duringLoad: ConcurrentLogin? = nil,
        between: ConcurrentLogin? = nil,
        write: Write
    ) async throws -> Outcome {
        let replies = [try PostingCapture.form(formID)] + (try answer.map { [try PostingCapture.answer($0)] } ?? [])
        let session = ScriptedPostingSession(replies)
        if let duringLoad { await session.adoptLoginDuringNextRequest(duringLoad) }
        let flow = PostingFlow()
        let form = try await flow.loadForm(at: try PostingCapture.pageURL(formID), through: session)
        if let between { await session.adoptLogin(between) }
        var error: PostingError?
        do {
            _ = try await write(flow, form)
        } catch let thrown {
            error = thrown
        }
        return Outcome(error: error, requests: await session.requests, generation: await session.loginGeneration)
    }

    @Test(
        "A login of another account or a logout after the form was loaded refuses every write, nothing sent",
        arguments: [ConcurrentLogin(identity: "user2", hashCheck: fresher), ConcurrentLogin(identity: nil, hashCheck: "")],
        writes
    )
    func changeAfterLoad(change: ConcurrentLogin, entry: Entry) async throws {
        let outcome = try await run(formID: entry.formID, between: change, write: entry.write)
        #expect(outcome.error == .sessionChanged, "\(entry.name)")
        #expect(outcome.requests.count == 1)
        #expect(outcome.requests.allSatisfy { $0.method == .get })
    }

    @Test("A login of another account during the form's GET refuses the write, nothing sent (R40a)")
    func switchDuringLoad() async throws {
        let outcome = try await run(
            formID: "R40a", duringLoad: ConcurrentLogin(identity: "user2", hashCheck: Self.fresher), write: Self.writes[0].write
        )
        #expect(outcome.error == .sessionChanged)
        #expect(outcome.requests.count == 1)
    }

    @Test(
        "A re-login of the same account, after or during the load, still sends the write; HFR judges the token (R40a, W17b)",
        arguments: [true, false]
    )
    func sameAccountRelogin(duringLoad: Bool) async throws {
        let relogin = ConcurrentLogin(identity: "user1", hashCheck: Self.fresher)
        let outcome = try await run(
            formID: "R40a", answer: "W17b", duringLoad: duringLoad ? relogin : nil, between: duringLoad ? nil : relogin,
            write: Self.writes[0].write
        )
        #expect(outcome.generation == 1)
        #expect(outcome.requests.count == 2)
        #expect(outcome.requests.last?.method == .post)
        guard case .rejected = outcome.error else {
            Issue.record("expected HFR's refusal, got \(String(describing: outcome.error))")
            return
        }
    }

    @Test("A cancellation during the identity lookup sends nothing and is a plain cancellation (R40a)")
    func cancelledDuringIdentityLookup() async throws {
        let session = ScriptedPostingSession([try PostingCapture.form("R40a"), try PostingCapture.answer("W17b")])
        let flow = PostingFlow()
        let form = try await flow.loadForm(at: try PostingCapture.pageURL("R40a"), through: session)
        await session.cancelCallerOnIdentityRead()
        let result = await Task { () async -> Result<PostingResult, PostingError> in
            do throws(PostingError) {
                return .success(try await flow.reply("Texte", with: form))
            } catch {
                return .failure(error)
            }
        }.value
        guard case .failure(.network(.cancelled)) = result else {
            Issue.record("expected a plain cancellation, got \(result)")
            return
        }
        #expect(await session.requests.count == 1)
    }

    @Test("Without a change, the write is sent (R40a)")
    func noChange() async throws {
        let outcome = try await run(formID: "R40a", answer: "W17b", write: Self.writes[0].write)
        #expect(outcome.requests.last?.method == .post)
    }
}
