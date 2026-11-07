import Foundation
import HFRModels
import HFRStorage
import Observation
import SwiftUI
import UIKit

/// Fills the avatar cache (LOT-066) from the topic and MP pages the app reads, as legacy did while parsing
/// (`ParseMessagesOperation.m:176, 430-446` @ 2440d79): download when the cache has no avatar of the author or it is older than 24 h.
///
/// Downloads go through `AnonymousAvatarLoader` (cookie-less, `forum-images.hardware.fr` over HTTPS, no redirect, 256 KiB cap).
/// The "Images externes" setting does not gate them: forum avatars are first-party under the image policy (LOT-071 D-071-1
/// point 3), the reader shows them whatever the setting says, and legacy downloaded them unconditionally. A failed download keeps
/// the previous file (`AvatarCache` writes atomically and never deletes on a miss).
actor AvatarStore {
    private let cache: AvatarCache
    private let loader: any AvatarLoading
    private let onStored: @Sendable @MainActor () -> Void
    private var inFlight: Set<String> = []
    /// Number of avatars written since the store was created.
    private(set) var generation = 0

    /// A store over `cache`; `onStored` runs on the main actor after each write.
    init(
        cache: AvatarCache, loader: any AvatarLoading = AnonymousAvatarLoader(),
        onStored: @escaping @Sendable @MainActor () -> Void = {}
    ) {
        self.cache = cache
        self.loader = loader
        self.onStored = onStored
    }

    /// The app's store: the standard avatar cache, and each write bumps `refresh` so the rows read the cache again.
    static func live(
        refresh: AvatarRefresh?, cache: AvatarCache = AvatarCache(cache: .standard), loader: any AvatarLoading = AnonymousAvatarLoader()
    ) -> AvatarStore {
        AvatarStore(cache: cache, loader: loader, onStored: { refresh?.didStore() })
    }

    /// Downloads and stores the avatar of each `(pseudo, url)` that the cache lacks or holds stale, one request per pseudo.
    func offer(_ avatars: [(pseudo: String, url: URL)]) async {
        for avatar in avatars {
            await offer(pseudo: avatar.pseudo, url: avatar.url)
        }
    }

    /// Same for one avatar.
    func offer(pseudo: String, url: URL) async {
        let key = pseudo.lowercased()
        guard !pseudo.isEmpty, !inFlight.contains(key), AnonymousAvatarLoader.isAllowed(url) else { return }
        // A cache that cannot be read (bad key, unsafe folder) cannot be written either.
        do {
            if try cache.entry(forPseudo: pseudo)?.isFresh == true { return }
        } catch {
            return
        }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        // Decoded once: bytes that are not an image are never stored.
        guard let data = await loader.avatarData(at: url), AvatarImage.isDecodable(data),
              (try? cache.store(data, forPseudo: pseudo)) != nil else { return }
        generation += 1
        await onStored()
    }
}

/// Whether bytes are an image the app can show.
enum AvatarImage {
    static func isDecodable(_ data: Data) -> Bool {
        UIImage(data: data) != nil
    }
}

/// The store's generation, observed by the avatar views: a view that reads it re-reads the cache when it changes.
@MainActor @Observable
final class AvatarRefresh {
    /// The generation of the last write.
    private(set) var generation = 0

    /// Records a write. A counter of its own, not the store's: the store is rebuilt with the session and restarts at 0.
    func didStore() {
        generation += 1
    }
}

extension EnvironmentValues {
    /// The avatar refresh model, injected by the app; nil in previews and tests (the avatar is then read once).
    @Entry var avatarRefresh: AvatarRefresh?
}

/// Hands the avatars of every page the source serves to the store, without delaying the page.
struct AvatarFillingTopicPageSource: TopicPageSource {
    let base: any TopicPageSource
    let store: AvatarStore

    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage {
        let page = try await base.page(for: target)
        let avatars = Self.avatars(in: page)
        if !avatars.isEmpty {
            // Fire and forget: the reader must not wait for downloads, and cancelling the page load must not cancel them.
            Task.detached(priority: .utility) { [store] in await store.offer(avatars) }
        }
        return page
    }

    /// One `(author, avatar)` per author of the page; the continuation block repeats the previous message and adds nothing.
    static func avatars(in page: ReaderPage) -> [(pseudo: String, url: URL)] {
        var seen: Set<String> = []
        var result: [(pseudo: String, url: URL)] = []
        for message in page.messages where !message.isDeleted && !message.isContinuation {
            guard let url = message.avatarURL, !message.author.isEmpty, seen.insert(message.author.lowercased()).inserted else { continue }
            result.append((message.author, url))
        }
        return result
    }
}
