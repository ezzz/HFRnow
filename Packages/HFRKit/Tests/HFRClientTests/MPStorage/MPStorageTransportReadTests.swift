import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// Finding and reading the storage thread on the captured pages (`R13a`, `R13u1`, `R60a`, `R60b`, `RA5`).
struct MPStorageTransportReadTests {
    @Test func findsTheThreadOnTheFirstListPage() async throws {
        let replies = [try MPStorageCapture.list("R13u1")]
        let outcome = await MPStorageHarness.run(replies) { transport, session throws(MPStorageTransportError) in
            try await transport.findThread(through: session)
        }
        #expect(outcome.value == MPStorageCapture.post)
        #expect(outcome.requests.map(\.url) == [try HFREndpoint.privateMessages(page: 1).url])
    }

    @Test func aListWithoutTheThreadAndNoNextPageIsNotFound() async throws {
        let replies = [try MPStorageCapture.list("R13a")]
        let outcome = await MPStorageHarness.run(replies) { transport, session throws(MPStorageTransportError) in
            try await transport.findThread(through: session)
        }
        #expect(outcome.error == nil)
        #expect(outcome.value == .some(nil))
        #expect(outcome.requests.count == 1)
    }

    @Test func aListPageThatIsNotTheMPListIsAListFailure() async throws {
        // `R60a` is a thread page: the MP list parser refuses it, the search does not say "not found".
        let page = try Capture.response("R60a-mpstorage-thread-first-post", url: try HFREndpoint.privateMessages().url)
        let outcome = await MPStorageHarness.run([.success(page)]) { transport, session throws(MPStorageTransportError) in
            try await transport.findThread(through: session)
        }
        guard case .list = outcome.error else {
            Issue.record("expected a list failure, got \(String(describing: outcome.result))")
            return
        }
    }

    @Test func aListAnsweredFromAnotherHostIsRefused() async throws {
        let elsewhere = try #require(URL(string: "https://www.hardware.fr/"))
        let page = try Capture.response("R13u1-mp-list-recipient-unread", url: elsewhere)
        let outcome = await MPStorageHarness.run([.success(page)]) { transport, session throws(MPStorageTransportError) in
            try await transport.findThread(through: session)
        }
        #expect(outcome.error == .unexpectedPage)
    }

    @Test func readsTheDocumentFromTheEditForm() async throws {
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.threadPage(), try MPStorageCapture.editForm()]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: MPStorageCapture.post, through: session)
        }
        let snapshot = try #require(outcome.value, "\(outcome.result)")
        #expect(snapshot.location.post == MPStorageCapture.post)
        #expect(snapshot.location.numreponse == MPStorageCapture.numreponse)
        #expect(snapshot.text == MPStorageCapture.storedText)
        #expect(snapshot.document == (try MPStorageCodec.decode(MPStorageCapture.storedText)))
        let urls = outcome.requests.map(\.url)
        #expect(urls.first == (try HFREndpoint.privateThreadFirstPage(post: MPStorageCapture.post).url))
        #expect(outcome.requests.first?.redirectPolicy == .doNotFollow)
        // The edit link is the one the toolbar prints, the URL `R60b` was captured from.
        let edit = try #require(URLComponents(url: snapshot.location.editURL, resolvingAgainstBaseURL: false))
        let captured = try #require(URLComponents(url: try MPStorageCapture.editURL(), resolvingAgainstBaseURL: false))
        #expect(edit.path == captured.path)
        #expect(edit.queryItems == captured.queryItems)
        #expect(outcome.posts.isEmpty)
    }

    @Test func aRenderedTextThatIsNotJSONStillReadsFromTheForm() async throws {
        // Structural edge: `R60a` with its paragraph text broken, as HFR would render a stored block tag (not captured,
        // #272). The document comes from the edit form, so the page only has to locate the message.
        let page = try Capture.page("R60a-mpstorage-thread-first-post")
            .replacing("{&#034;data&#034;:", with: "<b>rendered</b>:")
        let url = try HFREndpoint.privateThreadFirstPage(post: MPStorageCapture.post).url
        let thread = HTTPResponse(
            statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: url, body: Data(page.utf8)
        )
        #expect(throws: MPStoragePageError.invalidDocument) { try MPStoragePageParser.readDocument(in: page) }
        let outcome = await MPStorageHarness.run(
            [.success(thread), try MPStorageCapture.editForm()]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: MPStorageCapture.post, through: session)
        }
        #expect(outcome.value?.text == MPStorageCapture.storedText)
    }

    @Test func aThreadPageAnsweredFromAnotherHostIsRefused() async throws {
        let elsewhere = try #require(URL(string: "https://www.hardware.fr/forum2.php"))
        let page = try Capture.response("R60a-mpstorage-thread-first-post", url: elsewhere)
        let outcome = await MPStorageHarness.run([.success(page)]) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: MPStorageCapture.post, through: session)
        }
        #expect(outcome.error == .unexpectedPage)
        #expect(outcome.requests.count == 1)
    }

    @Test func aThreadNotForThisAccountIsStale() async throws {
        let page = try Capture.response("RA5-mp-thread-after-delete-owner", url: try HFREndpoint.privateThreadFirstPage(post: 1).url)
        let outcome = await MPStorageHarness.run([.success(page)]) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: 1, through: session)
        }
        #expect(outcome.error == .notAddressed)
        #expect(outcome.requests.count == 1)
    }

    @Test func anotherThreadIsNotTheStorage() async throws {
        let page = try Capture.response("RA1-mp-thread-after-create", url: try HFREndpoint.privateThreadFirstPage(post: 1).url)
        let outcome = await MPStorageHarness.run([.success(page)]) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: 1, through: session)
        }
        #expect(outcome.error == .threadPage(.notStorageThread))
        #expect(outcome.requests.count == 1)
    }

    @Test func aRedirectedThreadPageIsRefused() async throws {
        let url = try HFREndpoint.privateThreadFirstPage(post: MPStorageCapture.post).url
        let replies = [MPStorageCapture.status(301, url: url)]
        let outcome = await MPStorageHarness.run(replies) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: MPStorageCapture.post, through: session)
        }
        #expect(outcome.error == .unexpectedPage)
    }

    @Test func anEditFormOfAnotherMessageIsRefused() async throws {
        // `R43a` is the edit form of another conversation's first post: right shape, wrong thread and subject.
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.threadPage(), try PostingCapture.form("R43a")]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: MPStorageCapture.post, through: session)
        }
        #expect(outcome.error == .notStorageForm)
    }

    @Test func anEditFormOfThisMessageWithAnotherSubjectIsRefused() async throws {
        // Structural edge: `R60b` with its `sujet` renamed; thread and message are the expected ones.
        let page = try Capture.page("R60b-mpstorage-edit-form-first-post")
            .replacing("name=\"sujet\" value=\"\(MPStorageDocument.subject)\"", with: "name=\"sujet\" value=\"renamed\"")
        let form = HTTPResponse(
            statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: try MPStorageCapture.editURL(),
            body: Data(page.utf8)
        )
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.threadPage(), .success(form)]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: MPStorageCapture.post, through: session)
        }
        #expect(outcome.error == .notStorageForm)
    }

    @Test func anUnreadableStoredDocumentIsReported() async throws {
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.threadPage(), try MPStorageCapture.editForm(holding: "{\"data\":")]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: MPStorageCapture.post, through: session)
        }
        #expect(outcome.error == .invalidDocument)
    }

    @Test func aFailedRequestIsANetworkError() async throws {
        let outcome = await MPStorageHarness.run([.failure(.timedOut)]) { transport, session throws(MPStorageTransportError) in
            try await transport.read(post: MPStorageCapture.post, through: session)
        }
        #expect(outcome.error == .network(.timedOut))
    }

    @Test(arguments: [
        ("https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=3157083&numreponse=1980164061&page=1", true),
        ("https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=3157083&numreponse=1980164062&page=1", false),
        ("https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=3157084&numreponse=1980164061&page=1", false),
        ("https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=3157083&numreponse=1980164061&page=1", false),
        ("https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=prive&post=3157083&numreponse=1980164061", false),
        ("http://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=3157083&numreponse=1980164061", false),
        ("https://forum.hardware.fr/message.php?cat=prive&post=3157083&numreponse=1980164061&post=1", false)
    ])
    func editLinksMustNameThisMessage(link: String, accepted: Bool) throws {
        let url = try #require(URL(string: link))
        #expect(MPStorageTransport.isEditLink(url, post: MPStorageCapture.post, numreponse: MPStorageCapture.numreponse) == accepted)
    }
}
