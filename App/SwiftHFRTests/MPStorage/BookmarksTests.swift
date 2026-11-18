import Foundation
import HFRClient
import HFRModels
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// A `0.1` document whose bookmarks are `bookmarks` (written as LOT-062 writes them).
func bookmarkDocumentText(_ bookmarks: [MPStorageBookmark]) throws -> String {
    var document = try MPStorageCodec.decode(FakeMPStorageRemote.emptyDocument)
    guard let index = document.writableEntryIndex else { throw MPStorageError.noWritableEntry }
    document.data[index].bookmarks = MPStorageSection(list: bookmarks)
    return try MPStorageCodec.encodeForWriting(document)
}

extension FakeMPStorageRemote {
    /// The bookmarks of the forum document as it stands.
    func bookmarks() throws -> [MPStorageBookmark] {
        let document = try MPStorageCodec.decode(text)
        return document.writableEntryIndex.flatMap { document.data[$0].bookmarks?.list } ?? []
    }
}

private func bookmark(
    topic: Int = 96_827, category: String = "13", message: Int = 59_533_822, label: String = "Carafe", date: TimeInterval? = 1_700_000_000
) -> MPStorageBookmark {
    MPStorageBookmark(
        topic: topic, category: category, numreponse: message, author: "user1", label: label,
        createdAt: date.map { Date(timeIntervalSince1970: $0) }
    )
}

struct BookmarkListTests {
    // Bug #106: a bookmark opens the page HFR serves for its message, at the message, never page 1 of the topic.
    @Test func aBookmarkOpensItsMessagePageAtTheMessage() throws {
        let saved = bookmark()
        #expect(BookmarkList.link(of: saved) == "/forum2.php?config=hfr.inc&cat=13&post=96827&numreponse=59533822#t59533822")
        let target = try #require(BookmarkList.target(of: saved))
        #expect(target.source == .topic(TopicID(category: .forum(13), topic: 96_827)))
        #expect(target.numreponse == 59_533_822)
        #expect(target.anchor == 59_533_822)
    }

    @Test func aPrivateBookmarkRoutesAndAnUnreadableCategoryOpensNothing() {
        #expect(BookmarkList.target(of: bookmark(category: "prive")) != nil)
        #expect(BookmarkList.target(of: bookmark(category: "1&post=2")) == nil)
        #expect(BookmarkList.target(of: bookmark(category: "")) == nil)
    }

    @Test func theListIsNewestFirstUndatedLast() throws {
        let old = bookmark(message: 1, date: 1_600_000_000)
        let new = bookmark(message: 2, date: 1_700_000_000)
        let undatedA = bookmark(message: 3, date: nil)
        let undatedB = bookmark(message: 4, date: nil)
        let text = try bookmarkDocumentText([undatedA, old, undatedB, new])
        let listed = BookmarkList.bookmarks(in: try MPStorageCodec.decode(text))
        #expect(listed.map(\.numreponse) == [2, 1, 3, 4])
        // Another client's duplicate shows once, the newest copy.
        let twice = try bookmarkDocumentText([old, bookmark(message: 1, label: "Copie", date: 1_650_000_000)])
        #expect(BookmarkList.bookmarks(in: try MPStorageCodec.decode(twice)).map(\.label) == ["Copie"])
        #expect(BookmarkList.bookmarks(in: nil).isEmpty)
    }

    @Test func aBlankLabelReadsBookmark() {
        #expect(BookmarkList.title(of: bookmark(label: "  \n")) == "Bookmark")
        #expect(BookmarkList.title(of: bookmark(label: " Carafe ")) == "Carafe")
    }

    @Test func theDateReadsAsLegacy() throws {
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))
        #expect(BookmarkList.dateText(of: bookmark(date: 1_700_000_000), timeZone: paris) == "14/11/2023 à 23:13")
        #expect(BookmarkList.dateText(of: bookmark(date: nil), timeZone: paris) == "-")
    }
}

@MainActor
struct BookmarksModelTests {
    private func fixture(state: MPStorageSyncState?, bookmarks: [MPStorageBookmark] = []) async throws -> MPStorageSyncModelTests.Fixture {
        let text = try bookmarkDocumentText(bookmarks)
        return try await MPStorageSyncModelTests.make(thread: 7, state: state, copy: MPStorageCopy(post: 7, base: text), text: text)
    }

    @Test func theListFollowsTheDocument() async throws {
        let older = bookmark(message: 1, date: 1_600_000_000)
        let fixture = try await fixture(state: .on, bookmarks: [older])
        let model = BookmarksModel(mpStorage: fixture.model)
        await model.load()
        #expect(model.state == .syncing)
        #expect(model.bookmarks.map(\.numreponse) == [1])

        await fixture.remote.replaceText(try bookmarkDocumentText([older, bookmark(message: 2)]))
        await model.refresh()
        #expect(model.bookmarks.map(\.numreponse) == [2, 1])
        #expect(model.errorMessage == nil)
    }

    @Test func nothingIsListedWhileTheAccountDoesNotSync() async throws {
        for state in [MPStorageSyncState.declined, .off] {
            let fixture = try await fixture(state: state, bookmarks: [bookmark()])
            let model = BookmarksModel(mpStorage: fixture.model)
            await model.load()
            #expect(model.state == .notSyncing)
            #expect(model.bookmarks.isEmpty)
            #expect(await fixture.remote.calls.isEmpty)
        }
        #expect(BookmarksModel(mpStorage: nil).state == .signedOut)
    }

    @Test func aDeletionIsWrittenAndClosesTheBookmarkOpenBesideTheList() async throws {
        let kept = bookmark(message: 1), removed = bookmark(message: 2)
        let fixture = try await fixture(state: .on, bookmarks: [kept, removed])
        let model = BookmarksModel(mpStorage: fixture.model)
        await model.load()
        model.didOpen(removed)

        #expect(await model.delete(kept) == false)
        #expect(await model.delete(removed))
        #expect(model.selectedID == nil)
        #expect(model.bookmarks.isEmpty)
        #expect(try await fixture.remote.bookmarks().isEmpty)
    }

    @Test func aFailedRefreshSaysWhy() async throws {
        let fixture = try await fixture(state: .on)
        let model = BookmarksModel(mpStorage: fixture.model)
        await fixture.remote.fail(with: .network(.offline))
        await model.refresh()
        #expect(model.errorMessage == "Réseau indisponible : la synchronisation reprendra plus tard.")
    }
}

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
        let setup = try await make(state: .on, bookmarks: [bookmark()])
        let model = setup.model
        let fixture = setup.fixture
        let said = setup.said
        await model.start(Self.context())
        #expect(model.prompt == nil)
        #expect(said.lines == ["Post déjà dans les bookmarks"])
        #expect(await fixture.remote.calls.isEmpty)
        // The same message number in another topic is another bookmark.
        await model.start(Self.context(topic: TopicID(category: .forum(13), topic: 1)))
        #expect(model.prompt != nil)
    }

    @Test func aDocumentNeverReadIsReadBeforeTheDuplicateCheck() async throws {
        let setup = try await make(state: .on, bookmarks: [bookmark()], read: false)
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
        #expect(said.lines == ["Bookmark créé ; il sera écrit sur le forum à la prochaine synchronisation."])
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
        #expect(said.lines.isEmpty)
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
