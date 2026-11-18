import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct BookmarkActionModelTests {
    final class Said {
        var lines: [String] = []
    }

    struct Setup {
        let model: BookmarkActionModel
        let fixture: MPStorageSyncModelTests.Fixture
        let said: Said
    }

    static let topic = TopicID(category: .forum(13), topic: 96_827)

    static func context(topic: TopicID? = Self.topic, message: Int = 59_533_822) -> MessageMenuContext {
        MessageMenuContext(numreponse: message, author: "user1", actions: MessageActions(), topic: topic)
    }

    private func make(
        state: MPStorageSyncState?, thread: Int? = 7, bookmarks: [MPStorageBookmark] = [], read: Bool = true
    ) async throws -> Setup {
        let text = try bookmarkDocumentText(bookmarks)
        let copy = read ? MPStorageCopy(post: thread, base: text) : MPStorageCopy(post: thread)
        let fixture = try await MPStorageSyncModelTests.make(thread: thread, state: state, copy: copy, text: text)
        let said = Said()
        return Setup(model: BookmarkActionModel(mpStorage: fixture.model, confirm: { said.lines.append($0) }), fixture: fixture, said: said)
    }

    @Test func theEntryIsOfferedOnAPublicTopicOfAnAccountThatSyncsOrNeverChose() async throws {
        for (state, offered) in [(MPStorageSyncState.on, true), (.unasked, true), (.declined, false), (.off, false)] {
            let setup = try await make(state: state)
            let model = setup.model
            #expect(model.canBookmark(Self.context()) == offered, "\(state)")
        }
        let setup = try await make(state: .on)
        let model = setup.model
        #expect(!model.canBookmark(Self.context(topic: TopicID(category: .privateMessages, topic: 5))))
        #expect(!model.canBookmark(Self.context(topic: nil)))
        #expect(!model.canBookmark(Self.context(message: 0)))
        #expect(!model.canBookmark(Self.context(topic: TopicID(category: .forum(13), topic: 0))))
        #expect(!BookmarkActionModel(mpStorage: nil, confirm: { _ in }).canBookmark(Self.context()))
    }

    @Test func aBookmarkIsCreatedWithTheTrimmedTitleAndWrittenToTheForum() async throws {
        let setup = try await make(state: .on)
        let model = setup.model
        let fixture = setup.fixture
        let said = setup.said
        await model.start(Self.context())
        let draft = try #require(model.prompt)
        await model.create(draft, title: "  Carafe ")
        #expect(model.prompt == nil)
        #expect(said.lines == ["Bookmark créé"])
        let written = try #require(try await fixture.remote.bookmarks().first)
        #expect(written.topic == 96_827)
        #expect(written.category == "13")
        #expect(written.numreponse == 59_533_822)
        #expect(written.author == "user1")
        #expect(written.label == "Carafe")
        #expect(written.createdAt == MPStorageSyncModelTests.now)
    }

    @Test func aBlankTitleCreatesNothing() async throws {
        let setup = try await make(state: .on)
        let model = setup.model
        let fixture = setup.fixture
        let said = setup.said
        await model.start(Self.context())
        await model.create(try #require(model.prompt), title: " \n ")
        #expect(said.lines.isEmpty)
        #expect(await fixture.remote.calls.isEmpty)
    }

    @Test func aMessageAlreadyBookmarkedIsRefused() async throws {
        let setup = try await make(state: .on, bookmarks: [sampleBookmark()])
        let model = setup.model
        let fixture = setup.fixture
        let said = setup.said
        await model.start(Self.context())
        #expect(model.prompt == nil)
        #expect(said.lines == ["Post déjà dans les bookmarks"])
        #expect(await fixture.remote.calls.isEmpty)
        // The same message number in another category is another bookmark.
        await model.start(Self.context(topic: TopicID(category: .forum(5), topic: 96_827)))
        #expect(model.prompt != nil)
    }

    @Test func aDocumentNeverReadIsReadBeforeTheDuplicateCheck() async throws {
        let setup = try await make(state: .on, bookmarks: [sampleBookmark()], read: false)
        let model = setup.model
        let fixture = setup.fixture
        let said = setup.said
        await model.start(Self.context())
        #expect(await fixture.remote.calls == [.read(7)])
        #expect(said.lines == ["Post déjà dans les bookmarks"])
    }

    @Test func aFailedWriteKeepsTheBookmarkAndSaysSo() async throws {
        let setup = try await make(state: .on)
        let model = setup.model
        let fixture = setup.fixture
        let said = setup.said
        await model.start(Self.context())
        let draft = try #require(model.prompt)
        await fixture.remote.fail(with: .network(.offline))
        await model.create(draft, title: "Carafe")
        #expect(said.lines == ["Bookmark créé sur cet appareil. Réseau indisponible : la synchronisation reprendra plus tard."])
        #expect(BookmarkList.contains(draft.id, in: fixture.model.document(for: .bookmarks)))
        #expect(await fixture.copies.copy(for: MPStorageSyncModelTests.account)?.pending != nil)
    }

    @Test func anAccountThatNeverChoseIsAskedThenPromptedOnceOn() async throws {
        let setup = try await make(state: nil)
        let model = setup.model
        let fixture = setup.fixture
        let said = setup.said
        await model.start(Self.context())
        let draft = try #require(model.pendingConsent)
        #expect(model.prompt == nil)
        #expect(await fixture.remote.calls.isEmpty)

        await model.answerConsent(true, for: draft)
        #expect(fixture.model.isOn)
        #expect(model.pendingConsent == nil)
        #expect(model.prompt == draft)
        #expect(said.lines.isEmpty)
    }

    @Test func activatingWithoutAThreadAsksTheCreationQuestionAndNoTitle() async throws {
        let setup = try await make(state: nil, thread: nil)
        let model = setup.model
        let fixture = setup.fixture
        await model.start(Self.context())
        await model.answerConsent(true, for: try #require(model.pendingConsent))
        #expect(fixture.model.asksCreation)
        #expect(fixture.model.creationPrompt == .write)
        #expect(model.prompt == nil)
        // The creation question speaks for itself: nothing more is said.
        #expect(setup.said.lines.isEmpty)
    }

    @Test func cancellingTheQuestionRecordsNothing() async throws {
        let setup = try await make(state: nil)
        let model = setup.model
        let fixture = setup.fixture
        await model.start(Self.context())
        await model.answerConsent(false, for: try #require(model.pendingConsent))
        #expect(fixture.model.record == .unasked)
        #expect(model.prompt == nil)
        #expect(await fixture.remote.calls.isEmpty)
    }

    @Test func aDecisionTakenElsewhereMeanwhileStands() async throws {
        let setup = try await make(state: nil)
        let model = setup.model
        let fixture = setup.fixture
        let said = setup.said
        await model.start(Self.context())
        let draft = try #require(model.pendingConsent)
        fixture.states.set(.off, for: MPStorageSyncModelTests.account, at: MPStorageSyncModelTests.now)
        await model.answerConsent(true, for: draft)
        #expect(fixture.model.record?.state == .off)
        #expect(model.prompt == nil)
        #expect(said.lines == [BookmarkActionModel.notSyncing])
    }

    @Test func aSecondPickWhileTheFirstRunsDoesNothing() async throws {
        let setup = try await make(state: .on)
        await setup.model.start(Self.context())
        let first = try #require(setup.model.prompt)
        await setup.model.start(Self.context(topic: TopicID(category: .forum(5), topic: 1)))
        #expect(setup.model.prompt == first)
        #expect(!setup.model.isIdle)
    }

    @Test func aPickWithoutTopicSaysTheDataIsIncomplete() async throws {
        let setup = try await make(state: .on)
        await setup.model.start(Self.context(topic: nil))
        #expect(setup.said.lines == ["Données bookmark incomplètes"])
        #expect(setup.model.prompt == nil)
        #expect(setup.model.isIdle)
    }

    @Test func aPickAfterAnotherWindowSwitchedOffSaysSo() async throws {
        let setup = try await make(state: .on)
        #expect(setup.model.canBookmark(Self.context()))
        setup.fixture.states.set(.off, for: MPStorageSyncModelTests.account, at: MPStorageSyncModelTests.now)
        await setup.model.start(Self.context())
        #expect(setup.said.lines == [BookmarkActionModel.notSyncing])
        #expect(setup.model.prompt == nil)
    }

    @Test func switchedOffBetweenThePromptAndCreateSaysSo() async throws {
        let setup = try await make(state: .on)
        await setup.model.start(Self.context())
        let draft = try #require(setup.model.prompt)
        setup.fixture.states.set(.off, for: MPStorageSyncModelTests.account, at: MPStorageSyncModelTests.now)
        setup.fixture.model.reloadRecord()
        await setup.model.create(draft, title: "Carafe")
        #expect(setup.said.lines == [BookmarkActionModel.notSyncing])
        #expect(await setup.fixture.remote.calls.isEmpty)
    }

    @Test func aBookmarkAddedMeanwhileIsSaidToExist() async throws {
        let setup = try await make(state: .on)
        await setup.model.start(Self.context())
        let draft = try #require(setup.model.prompt)
        await setup.fixture.model.edit(.bookmarks) { document, stamp in try document.addBookmark(sampleBookmark(), stamp: stamp) }
        await setup.model.create(draft, title: "Carafe")
        #expect(setup.said.lines == ["Post déjà dans les bookmarks"])
    }

    @Test func anEmojiTitleIsRefusedBeforeCreating() async throws {
        #expect(BookmarkActionModel.titleProblem("Pizza 🍕") == "Les emoji ne peuvent pas être enregistrés dans le stockage MP.")
        #expect(BookmarkActionModel.titleProblem("  ") == "")
        #expect(BookmarkActionModel.titleProblem("Café ★") == nil)
        let setup = try await make(state: .on)
        await setup.model.start(Self.context())
        await setup.model.create(try #require(setup.model.prompt), title: "Pizza 🍕")
        #expect(setup.said.lines.isEmpty)
        #expect(await setup.fixture.remote.calls.isEmpty)
    }

    @Test func aRefusedWriteSaysWhy() async throws {
        let setup = try await make(state: .on)
        await setup.model.start(Self.context())
        let draft = try #require(setup.model.prompt)
        // A label the codec refuses (a lone surrogate cannot be built in Swift: a too-large document stands in for it).
        let huge = String(repeating: "a", count: 70_000)
        await setup.model.create(draft, title: huge)
        #expect(setup.said.lines == [MPStorageSyncModel.message(for: .document(.tooLarge(byteCount: 0, limit: 0)))])
    }

    @Test func aDocumentThatCannotBeReadOpensNoPrompt() async throws {
        let setup = try await make(state: .on, read: false)
        await setup.fixture.remote.fail(with: .network(.offline))
        await setup.model.start(Self.context())
        #expect(setup.model.prompt == nil)
        #expect(setup.said.lines == ["Réseau indisponible : la synchronisation reprendra plus tard."])
    }

    @Test func activatingOfflineSaysWhy() async throws {
        let setup = try await make(state: nil)
        await setup.model.start(Self.context())
        let draft = try #require(setup.model.pendingConsent)
        await setup.fixture.remote.fail(with: .network(.offline))
        await setup.model.answerConsent(true, for: draft)
        #expect(setup.fixture.model.record?.state == .unasked)
        #expect(setup.model.prompt == nil)
        #expect(setup.said.lines == ["Réseau indisponible : la synchronisation reprendra plus tard."])
    }

    @Test func theMenuEntryRunsTheModel() async throws {
        let setup = try await make(state: .on)
        let model = setup.model
        let registry = MessageActionRegistry([model.handler])
        #expect(registry.entries(for: Self.context(), source: .message).contains(.bookmark))
        #expect(await registry.perform(.bookmark, with: Self.context()))
        #expect(model.prompt != nil)
    }
}

/// An account's MPStorage sync whose forum reads wait at a gate (LOT-131's `ReadGate`).
struct GatedBookmarks {
    let sync: MPStorageSyncModel
    let remote: FakeMPStorageRemote
    let gate: ReadGate

    @MainActor
    static func make(state: MPStorageSyncState, thread: Int? = 7, base: String? = nil) async throws -> GatedBookmarks {
        let remote = FakeMPStorageRemote(thread: thread, text: try bookmarkDocumentText([]))
        let gate = ReadGate()
        let states = MPStorageSyncStateStore(settings: InMemorySettingsStore())
        states.set(state, for: MPStorageSyncModelTests.account, at: MPStorageSyncModelTests.now)
        let copies = MPStorageCopyStore(persistence: InMemorySmallStorePersistence<MPStorageCopyDocument>())
        try await copies.save(MPStorageCopy(post: thread, base: base), for: MPStorageSyncModelTests.account)
        let persistence = MPStorageCopyPersistence(store: copies, account: MPStorageSyncModelTests.account)
        let sync = MPStorageSyncModel(
            account: MPStorageSyncModelTests.account,
            sync: MPStorageSync(remote: GatedMPStorageRemote(inner: remote, gate: gate), persistence: persistence),
            states: states, isLoggedIn: { true }, clock: { MPStorageSyncModelTests.now }
        )
        return GatedBookmarks(sync: sync, remote: remote, gate: gate)
    }

    /// Waits until a read is held at the gate.
    func readIsHeld() async {
        while await gate.waiting == 0 { await Task.yield() }
    }
}

/// The concurrency cases, with LOT-131's read gate.
extension BookmarkActionModelTests {
    // Fable round 1, finding 5: while the first pick reads the document, a second does nothing and the model stays busy
    // (the reader keeps it, so the prompt it ends with is shown).
    @Test func aPickWhileTheDocumentIsReadIsIgnored() async throws {
        let gated = try await GatedBookmarks.make(state: .on)
        let sync = gated.sync, remote = gated.remote, gate = gated.gate
        let model = BookmarkActionModel(mpStorage: sync, confirm: { _ in })

        let first = Task { await model.start(Self.context()) }
        while await gate.waiting == 0 { await Task.yield() }
        #expect(!model.isIdle)
        // In a task of its own: were it to read too, it would wait at the gate like the first.
        let second = Task { await model.start(Self.context(topic: TopicID(category: .forum(5), topic: 1))) }
        for _ in 0..<50 { await Task.yield() }
        await gate.release()
        await first.value
        await second.value
        #expect(model.prompt?.topic == Self.topic)
        #expect(await remote.calls == [.read(7)])
    }

    // Fable round 2, finding 3: « Activer » keeps the model busy while it switches on, and a pick meanwhile does nothing.
    @Test func aPickWhileActivatingIsIgnored() async throws {
        let gated = try await GatedBookmarks.make(state: .unasked)
        let model = BookmarkActionModel(mpStorage: gated.sync, confirm: { _ in })
        await model.start(Self.context())
        let draft = try #require(model.pendingConsent)

        let answer = Task { await model.answerConsent(true, for: draft) }
        await gated.readIsHeld()
        #expect(!model.isIdle)
        let other = Task { await model.start(Self.context(topic: TopicID(category: .forum(5), topic: 1))) }
        for _ in 0..<50 { await Task.yield() }
        await gated.gate.release()
        await answer.value
        await other.value
        #expect(model.prompt == draft)
        #expect(model.pendingConsent == nil)
    }
}
