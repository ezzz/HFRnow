import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// `AvatarStore` (#569): the avatar cache is filled from the pages read, cookie-less, from the forum image host only, when the
/// cached file is missing or stale. Every transport here is a `MockTransport`: no test
/// reaches a network (LESSONS 56).
struct AvatarStoreTests {
    /// A 1×1 PNG: `UIImage` decodes it.
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ) ?? Data()
    private static let url = URL(string: "https://forum-images.hardware.fr/images/perso/a.png")!

    private struct Rig {
        let store: AvatarStore
        let transport: MockTransport
        let cache: AvatarCache
        let stored: Counter
    }

    /// Counts `onStored` calls; the store awaits the callback, so the count is final when `offer` returns.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func bump() { lock.withLock { value += 1 } }
    }

    private func rig(reply: HTTPResponse? = nil) -> Rig {
        let directory = CacheDirectory(root: URL.temporaryDirectory.appending(path: "avatar-store-\(UUID().uuidString)"))
        let cache = AvatarCache(cache: directory)
        let response = reply ?? HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: Self.url, body: Self.png)
        let transport = MockTransport { _ async throws(NetworkError) -> HTTPResponse in response }
        let stored = Counter()
        let store = AvatarStore(
            cache: cache, loader: AnonymousAvatarLoader(transport: transport), onStored: { stored.bump() }
        )
        return Rig(store: store, transport: transport, cache: cache, stored: stored)
    }

    @Test func missingAvatarIsDownloadedAndStored() async throws {
        let rig = rig()
        await rig.store.offer(pseudo: "user1", url: Self.url)
        #expect(await rig.transport.requests.count == 1)
        #expect(try rig.cache.entry(forPseudo: "user1")?.isFresh == true)
        #expect(await rig.store.generation == 1)
        #expect(rig.stored.count == 1)
    }

    @Test func freshEntryIsNotDownloadedAgain() async throws {
        let rig = rig()
        try rig.cache.store(Self.png, forPseudo: "user1")
        await rig.store.offer(pseudo: "User1", url: Self.url)
        #expect(await rig.transport.requests.isEmpty)
        #expect(await rig.store.generation == 0)
        #expect(rig.stored.count < 1)
    }

    @Test func staleEntryIsDownloadedAgain() async throws {
        let rig = rig()
        let file = try rig.cache.store(Self.png, forPseudo: "user1")
        let old = Date.now.addingTimeInterval(-AvatarCache.freshnessInterval - 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path(percentEncoded: false))
        #expect(try rig.cache.entry(forPseudo: "user1")?.isFresh == false)
        await rig.store.offer(pseudo: "user1", url: Self.url)
        #expect(await rig.transport.requests.count == 1)
        #expect(try rig.cache.entry(forPseudo: "user1")?.isFresh == true)
    }

    @Test func requestCarriesNoCookieAndFollowsNoRedirect() async throws {
        let rig = rig()
        await rig.store.offer(pseudo: "user1", url: Self.url)
        let requests = await rig.transport.requests
        #expect(requests.count == 1)
        #expect(requests.allSatisfy { $0.headers["Cookie"] == nil && $0.redirectPolicy == .doNotFollow })
    }

    @Test(arguments: [
        "http://forum-images.hardware.fr/a.png",
        "https://forum.hardware.fr/a.png",
        "https://example.com/a.png",
        "https://forum-images.hardware.fr:8443/a.png",
        "https://forum-images.hardware.fr.example.com/a.png",
        "https://192.168.1.1/a.png"
    ])
    func hostOutsideTheForumImageHostIsNeverContacted(_ address: String) async throws {
        let rig = rig()
        await rig.store.offer(pseudo: "user1", url: try #require(URL(string: address)))
        #expect(await rig.transport.requests.isEmpty)
        #expect(try rig.cache.entry(forPseudo: "user1") == nil)
    }

    @Test func settingDoesNotGateForumAvatars() async throws {
        // First-party avatars load whatever "Images externes" says (LOT-071 D-071-1 point 3): the store has no such gate.
        let rig = rig()
        await rig.store.offer(pseudo: "user1", url: Self.url)
        #expect(await rig.transport.requests.count == 1)
        #expect(try rig.cache.entry(forPseudo: "user1") != nil)
    }

    @MainActor @Test func aStoreWriteBumpsTheRowsRefreshGeneration() async throws {
        let directory = CacheDirectory(root: URL.temporaryDirectory.appending(path: "avatar-live-\(UUID().uuidString)"))
        let response = HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: Self.url, body: Self.png)
        let transport = MockTransport { _ async throws(NetworkError) -> HTTPResponse in response }
        let refresh = AvatarRefresh()
        let store = AvatarStore.live(
            refresh: refresh, cache: AvatarCache(cache: directory), loader: AnonymousAvatarLoader(transport: transport)
        )
        #expect(refresh.generation == 0)
        await store.offer(pseudo: "user1", url: Self.url)
        #expect(refresh.generation == 1)
        // A fresh entry writes nothing: the rows are not refreshed again.
        await store.offer(pseudo: "user1", url: Self.url)
        #expect(refresh.generation == 1)
    }

    @Test func nonImageBytesAreNeverStored() async throws {
        let body = Data("<html>".utf8)
        let rig = rig(reply: HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: Self.url, body: body))
        await rig.store.offer(pseudo: "user1", url: Self.url)
        #expect(await rig.transport.requests.count == 1)
        #expect(try rig.cache.entry(forPseudo: "user1") == nil)
        #expect(await rig.store.generation == 0)
    }

    @Test func pageAvatarsAreOnePerAuthorWithoutContinuationOrDeleted() throws {
        func message(
            _ number: Int, _ author: String, deleted: Bool = false, continuation: Bool = false, avatar: Bool = true
        ) -> ReaderMessage {
            ReaderMessage(
                numreponse: number, author: author, isDeleted: deleted, isContinuation: continuation,
                avatarURL: avatar ? Self.url : nil, dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil,
                content: MessageContent(html: "<p>x</p>")
            )
        }
        var page = readerPage(page: 1)
        page.messages = [
            message(1, "user1"), message(2, "USER1"), message(3, "user2", avatar: false), message(4, "user3", deleted: true),
            message(5, "user4", continuation: true), message(6, "user5")
        ]
        #expect(AvatarFillingTopicPageSource.avatars(in: page).map(\.pseudo) == ["user1", "user5"])
    }
}
