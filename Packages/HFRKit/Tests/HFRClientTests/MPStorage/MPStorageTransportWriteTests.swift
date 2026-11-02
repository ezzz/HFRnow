import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// Saving and creating the storage document: merge against the copy re-read just before the write, the edit POST
/// (`R60b` → `W15`), the read-back, and the creation through the new-MP form (`R45b` → `W10`).
struct MPStorageTransportWriteTests {
    static let stamp = MPStorageStamp(date: Date(timeIntervalSince1970: 1_800_000_000))

    static let location = MPStorageLocation(
        post: MPStorageCapture.post, numreponse: MPStorageCapture.numreponse,
        editURL: (try? MPStorageCapture.editURL()) ?? URL(fileURLWithPath: "/")
    )

    static func stored() throws -> MPStorageDocument {
        try MPStorageCodec.decode(MPStorageCapture.storedText)
    }

    /// `base` plus one blocked pseudo.
    static func withBlockedPseudo(_ name: String, on base: MPStorageDocument) throws -> MPStorageDocument {
        var ours = base
        _ = try ours.addBlocklistEntry(username: name, stamp: stamp)
        return ours
    }

    /// The text the transport must post for these three copies.
    static func expectedText(base: MPStorageDocument?, ours: MPStorageDocument, theirs: MPStorageDocument) throws -> String {
        try MPStorageCodec.encodeForWriting(MPStorageMerge.merge(base: base, ours: ours, theirs: theirs, stamp: stamp).document)
    }

    @Test func nothingToWriteSendsNothing() async throws {
        let base = try Self.stored()
        let outcome = await MPStorageHarness.run([try MPStorageCapture.editForm()]) { transport, session throws(MPStorageTransportError) in
            try await transport.save(base, base: base, at: Self.location, stamp: Self.stamp, through: session)
        }
        let result = try #require(outcome.value, "\(outcome.result)")
        #expect(!result.wrote)
        #expect(result.snapshot.text == MPStorageCapture.storedText)
        #expect(outcome.requests.count == 1)
        #expect(outcome.posts.isEmpty)
    }

    @Test func anEditIsPostedThroughTheEditFormAndReadBack() async throws {
        let base = try Self.stored()
        let ours = try Self.withBlockedPseudo("user9", on: base)
        let text = try Self.expectedText(base: base, ours: ours, theirs: base)
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.editForm(), try PostingCapture.answer("W15"), try MPStorageCapture.editForm(holding: text)]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.save(ours, base: base, at: Self.location, stamp: Self.stamp, through: session)
        }
        let result = try #require(outcome.value, "\(outcome.result)")
        #expect(result.wrote)
        #expect(result.snapshot.text == text)
        #expect(result.snapshot.document.data.first?.blocklist?.list.map(\.username) == ["user9"])
        let post = try #require(outcome.posts.first)
        #expect(post.url.absoluteString == "https://forum.hardware.fr/bdd.php?config=hfr.inc")
        #expect(outcome.postField("content_form") == text)
        #expect(outcome.postField("post") == String(MPStorageCapture.post))
        #expect(outcome.postField("numreponse") == String(MPStorageCapture.numreponse))
        #expect(outcome.postField("sujet") == MPStorageDocument.subject)
        #expect(outcome.postField("delete") == nil)
        // Form, POST, read-back: the read-back is a GET of the same edit form.
        #expect(outcome.requests.map(\.method) == [.get, .post, .get])
        #expect(outcome.requests.last?.url == (try MPStorageCapture.editURL()))
    }

    @Test func aConcurrentWriteIsMergedNotOverwritten() async throws {
        let base = try Self.stored()
        let ours = try Self.withBlockedPseudo("user9", on: base)
        // Another client blocked someone since our read: the forum copy is no longer `base`.
        let theirs = try Self.withBlockedPseudo("user8", on: base)
        let theirsText = try MPStorageCodec.encodeForWriting(theirs)
        let text = try Self.expectedText(base: base, ours: ours, theirs: theirs)
        let outcome = await MPStorageHarness.run(
            [
                try MPStorageCapture.editForm(holding: theirsText), try PostingCapture.answer("W15"),
                try MPStorageCapture.editForm(holding: text)
            ]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.save(ours, base: base, at: Self.location, stamp: Self.stamp, through: session)
        }
        #expect(outcome.error == nil)
        let posted = try MPStorageCodec.decode(try #require(outcome.postField("content_form")))
        #expect(Set(posted.data.first?.blocklist?.list.map(\.username) ?? []) == ["user8", "user9"])
    }

    @Test func aDocumentTheGuardsRefuseIsNeverPosted() async throws {
        let base = try Self.stored()
        var ours = base
        ours.extra["otherClient"] = .string("\u{1F600}")
        let outcome = await MPStorageHarness.run([try MPStorageCapture.editForm()]) { transport, session throws(MPStorageTransportError) in
            try await transport.save(ours, base: base, at: Self.location, stamp: Self.stamp, through: session)
        }
        guard case .document(.nonBMPCharacter) = outcome.error else {
            Issue.record("expected a non-BMP refusal, got \(String(describing: outcome.result))")
            return
        }
        #expect(outcome.posts.isEmpty)
    }

    @Test func aStoredCopyThatIsNotTheTextSentIsNotVerified() async throws {
        let base = try Self.stored()
        let ours = try Self.withBlockedPseudo("user9", on: base)
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.editForm(), try PostingCapture.answer("W15"), try MPStorageCapture.editForm()]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.save(ours, base: base, at: Self.location, stamp: Self.stamp, through: session)
        }
        #expect(outcome.error == .notVerified(readBack: nil))
        #expect(outcome.posts.count == 1)
    }

    @Test func anUnreadableReadBackIsNotVerified() async throws {
        let base = try Self.stored()
        let ours = try Self.withBlockedPseudo("user9", on: base)
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.editForm(), try PostingCapture.answer("W15"), .failure(.offline)]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.save(ours, base: base, at: Self.location, stamp: Self.stamp, through: session)
        }
        #expect(outcome.error == .notVerified(readBack: .posting(.network(.offline))))
    }

    @Test func aLostAnswerIsUnconfirmed() async throws {
        let base = try Self.stored()
        let ours = try Self.withBlockedPseudo("user9", on: base)
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.editForm(), .failure(.timedOut)]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.save(ours, base: base, at: Self.location, stamp: Self.stamp, through: session)
        }
        #expect(outcome.error == .posting(.unconfirmed(.transport(.timedOut))))
        #expect(outcome.posts.count == 1)
    }

    @Test func aRefusedEditIsReportedWithHFRsSentence() async throws {
        let base = try Self.stored()
        let ours = try Self.withBlockedPseudo("user9", on: base)
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.editForm(), try PostingCapture.answer("W17a")]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.save(ours, base: base, at: Self.location, stamp: Self.stamp, through: session)
        }
        guard case .posting(.rejected) = outcome.error else {
            Issue.record("expected a refusal, got \(String(describing: outcome.result))")
            return
        }
    }

    // MARK: - Create

    @Test func anExistingThreadIsReadNotCreated() async throws {
        let outcome = await MPStorageHarness.run(
            [try MPStorageCapture.list("R13u1"), try MPStorageCapture.threadPage(), try MPStorageCapture.editForm()]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.create(stamp: Self.stamp, through: session)
        }
        guard case .existing(let snapshot) = outcome.value else {
            Issue.record("expected the existing thread, got \(outcome.result)")
            return
        }
        #expect(snapshot.text == MPStorageCapture.storedText)
        #expect(outcome.posts.isEmpty)
    }

    @Test func aMissingThreadIsCreatedThroughTheNewMPForm() async throws {
        let outcome = await MPStorageHarness.run(
            [
                try MPStorageCapture.list("R13a"), try PostingCapture.form("R45b"), try PostingCapture.answer("W10"),
                try MPStorageCapture.list("R13u1"), try MPStorageCapture.threadPage(), try MPStorageCapture.editForm()
            ]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.create(stamp: Self.stamp, through: session)
        }
        guard case .created(let snapshot) = outcome.value else {
            Issue.record("expected a created thread, got \(outcome.result)")
            return
        }
        #expect(snapshot.location.post == MPStorageCapture.post)
        // Search, form, POST, search again, thread page, edit form: never a POST before the first search.
        #expect(outcome.requests.map(\.method) == [.get, .get, .post, .get, .get, .get])
        #expect(outcome.requests[1].url == (try HFREndpoint.newPrivateMessageForm(to: MPStorageDocument.recipient).url))
        #expect(outcome.posts.first?.url.absoluteString == "https://forum.hardware.fr/bddpost.php?config=hfr.inc")
        #expect(outcome.postField("dest") == MPStorageDocument.recipient)
        #expect(outcome.postField("sujet") == MPStorageDocument.subject)
        let posted = try #require(outcome.postField("content_form"))
        #expect(posted == (try MPStorageCodec.encodeForWriting(MPStorageTransport.emptyDocument(stamp: Self.stamp))))
    }

    @Test func aConfirmedCreationTheListDoesNotShowIsReported() async throws {
        let outcome = await MPStorageHarness.run(
            [
                try MPStorageCapture.list("R13a"), try PostingCapture.form("R45b"), try PostingCapture.answer("W10"),
                try MPStorageCapture.list("R13a")
            ]
        ) { transport, session throws(MPStorageTransportError) in
            try await transport.create(stamp: Self.stamp, through: session)
        }
        #expect(outcome.error == .notFoundAfterCreation)
        #expect(outcome.posts.count == 1)
    }

    @Test func theEmptyDocumentIsLegacysTemplate() throws {
        // `R60b` holds the document legacy's template created (`MPStorage.m:740`), every level stamped at one instant.
        let legacy = try Self.stored()
        let instant = try #require(legacy.lastUpdate)
        let ours = MPStorageTransport.emptyDocument(stamp: MPStorageStamp(date: instant))
        #expect(ours == legacy)
    }
}
