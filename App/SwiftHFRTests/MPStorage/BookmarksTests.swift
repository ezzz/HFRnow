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

func sampleBookmark(
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
        let saved = sampleBookmark()
        #expect(BookmarkList.link(of: saved) == "/forum2.php?config=hfr.inc&cat=13&post=96827&numreponse=59533822#t59533822")
        let target = try #require(BookmarkList.target(of: saved))
        #expect(target.source == .topic(TopicID(category: .forum(13), topic: 96_827)))
        #expect(target.numreponse == 59_533_822)
        #expect(target.anchor == 59_533_822)
    }

    @Test func aPrivateBookmarkRoutesAndAnUnreadableCategoryOpensNothing() {
        #expect(BookmarkList.target(of: sampleBookmark(category: "prive")) != nil)
        #expect(BookmarkList.target(of: sampleBookmark(category: "1&post=2")) == nil)
        #expect(BookmarkList.target(of: sampleBookmark(category: "")) == nil)
    }

    @Test func theListIsNewestFirstUndatedLast() throws {
        let old = sampleBookmark(message: 1, date: 1_600_000_000)
        let new = sampleBookmark(message: 2, date: 1_700_000_000)
        let undatedA = sampleBookmark(message: 3, date: nil)
        let undatedB = sampleBookmark(message: 4, date: nil)
        let text = try bookmarkDocumentText([undatedA, old, undatedB, new])
        let listed = BookmarkList.bookmarks(in: try MPStorageCodec.decode(text))
        #expect(listed.map(\.numreponse) == [2, 1, 3, 4])
        // Another client's duplicate shows once, the newest copy.
        let twice = try bookmarkDocumentText([old, sampleBookmark(message: 1, label: "Copie", date: 1_650_000_000)])
        #expect(BookmarkList.bookmarks(in: try MPStorageCodec.decode(twice)).map(\.label) == ["Copie"])
        #expect(BookmarkList.bookmarks(in: nil).isEmpty)
    }

    @Test func aBlankLabelReadsBookmark() {
        #expect(BookmarkList.title(of: sampleBookmark(label: "  \n")) == "Bookmark")
        #expect(BookmarkList.title(of: sampleBookmark(label: " Carafe ")) == "Carafe")
    }

    @Test func theDateReadsAsLegacy() throws {
        let paris = try #require(TimeZone(identifier: "Europe/Paris"))
        #expect(BookmarkList.dateText(of: sampleBookmark(date: 1_700_000_000), timeZone: paris) == "14/11/2023 à 23:13")
        #expect(BookmarkList.dateText(of: sampleBookmark(date: nil), timeZone: paris) == "-")
    }
}

@MainActor
struct BookmarksModelTests {
    private func fixture(state: MPStorageSyncState?, bookmarks: [MPStorageBookmark] = []) async throws -> MPStorageSyncModelTests.Fixture {
        let text = try bookmarkDocumentText(bookmarks)
        return try await MPStorageSyncModelTests.make(thread: 7, state: state, copy: MPStorageCopy(post: 7, base: text), text: text)
    }

    @Test func theListFollowsTheDocument() async throws {
        let older = sampleBookmark(message: 1, date: 1_600_000_000)
        let fixture = try await fixture(state: .on, bookmarks: [older])
        let model = BookmarksModel(mpStorage: fixture.model)
        await model.load()
        #expect(model.state == .syncing)
        #expect(model.bookmarks.map(\.numreponse) == [1])

        await fixture.remote.replaceText(try bookmarkDocumentText([older, sampleBookmark(message: 2)]))
        await model.refresh()
        #expect(model.bookmarks.map(\.numreponse) == [2, 1])
        #expect(model.errorMessage == nil)
    }

    @Test func nothingIsListedWhileTheAccountDoesNotSync() async throws {
        for state in [MPStorageSyncState.declined, .off] {
            let fixture = try await fixture(state: state, bookmarks: [sampleBookmark()])
            let model = BookmarksModel(mpStorage: fixture.model)
            await model.load()
            #expect(model.state == .notSyncing)
            #expect(model.bookmarks.isEmpty)
            #expect(await fixture.remote.calls.isEmpty)
        }
        #expect(BookmarksModel(mpStorage: nil).state == .signedOut)
    }

    @Test func aDeletionIsWrittenAndClosesTheBookmarkOpenBesideTheList() async throws {
        let kept = sampleBookmark(message: 1), removed = sampleBookmark(message: 2)
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

    @Test func aDeletionIsNotWrittenOnceAnotherWindowSwitchedTheAccountOff() async throws {
        let shown = sampleBookmark()
        let fixture = try await fixture(state: .on, bookmarks: [shown])
        let model = BookmarksModel(mpStorage: fixture.model)
        await model.load()
        model.didOpen(shown)
        fixture.states.set(.off, for: MPStorageSyncModelTests.account, at: MPStorageSyncModelTests.now)

        #expect(await model.delete(shown) == false)
        #expect(model.selectedID == shown.id)
        #expect(await fixture.remote.calls == [.read(7)])
        #expect(try await fixture.remote.bookmarks() == [shown])
    }

    @Test func aDeletionThatRemovesNothingKeepsTheDetail() async throws {
        let shown = sampleBookmark()
        let fixture = try await fixture(state: .on)
        let model = BookmarksModel(mpStorage: fixture.model)
        await model.load()
        model.didOpen(shown)
        #expect(await model.delete(shown) == false)
        #expect(model.selectedID == shown.id)
    }

    @Test func aFailureIsNotShownWhileTheAccountDoesNotSync() async throws {
        let fixture = try await fixture(state: .on)
        let model = BookmarksModel(mpStorage: fixture.model)
        await fixture.remote.fail(with: .network(.offline))
        await model.refresh()
        await fixture.model.setEnabled(false)
        #expect(model.state == .notSyncing)
        #expect(model.errorMessage == nil)
    }

    // Fable round 2, finding 1: a swiped row leaves the list at once, before the forum exchange ends.
    @Test func aDeletionShowsBeforeTheForumAnswers() async throws {
        let shown = sampleBookmark()
        let gated = try await GatedBookmarks.make(state: .on, base: try bookmarkDocumentText([shown]))
        await gated.sync.loadCopyIfNeeded()
        let model = BookmarksModel(mpStorage: gated.sync)
        #expect(model.bookmarks == [shown])

        let deletion = Task { await model.delete(shown) }
        await gated.readIsHeld()
        #expect(model.bookmarks.isEmpty)
        await gated.gate.release()
        await deletion.value
        #expect(model.bookmarks.isEmpty)
        #expect(try await gated.remote.bookmarks().isEmpty)
    }

    // Fable round 2, finding 2: the selection is the window's, so a list built again finds the bookmark still open.
    @Test func theSelectionOutlivesTheListScreen() async throws {
        let shown = sampleBookmark()
        let fixture = try await fixture(state: .on, bookmarks: [shown])
        let selection = BookmarkSelection()
        BookmarksModel(mpStorage: fixture.model, selection: selection).didOpen(shown)
        let again = BookmarksModel(mpStorage: fixture.model, selection: selection)
        #expect(again.selectedID == shown.id)
        await again.load()
        #expect(await again.delete(shown))
        #expect(selection.id == nil)
    }

    @Test func aFailedRefreshSaysWhy() async throws {
        let fixture = try await fixture(state: .on)
        let model = BookmarksModel(mpStorage: fixture.model)
        await fixture.remote.fail(with: .network(.offline))
        await model.refresh()
        #expect(model.errorMessage == "Réseau indisponible : la synchronisation reprendra plus tard.")
    }
}
