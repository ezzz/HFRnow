import Foundation
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// `MemberAvatarPrefetcher` and its live lookup (#714): a one-to-one correspondent with no cached avatar is looked up on their
/// profile (id cookie-less, profile with the session since #1363), one lookup at a time, at most once per pseudo. Every
/// transport is a `MockTransport` (LESSONS 56).
struct MemberAvatarPrefetcherTests {
    private static let avatar = URL(string: "https://forum-images.hardware.fr/images/perso/a.png")!

    /// A scripted lookup that records the pseudos asked and the most lookups seen running at once.
    private final class ScriptedLookup: MemberAvatarLookup, @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        private var running = 0
        private var peak = 0
        private let answer: @Sendable (String) -> MemberAvatarLookupResult

        init(answer: @escaping @Sendable (String) -> MemberAvatarLookupResult = { _ in .avatar(MemberAvatarPrefetcherTests.avatar) }) {
            self.answer = answer
        }

        var pseudos: [String] { lock.withLock { asked } }
        var maximumConcurrency: Int { lock.withLock { peak } }

        func avatar(forPseudo pseudo: String) async -> MemberAvatarLookupResult {
            lock.withLock {
                asked.append(pseudo)
                running += 1
                peak = max(peak, running)
            }
            // Long enough for a second caller to start if the turns did not hold.
            try? await Task.sleep(for: .milliseconds(20))
            lock.withLock { running -= 1 }
            return answer(pseudo)
        }
    }

    /// Records what the prefetcher offers to the store.
    private final class Offers: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        var pseudos: [String] { lock.withLock { items } }
        func add(_ pseudo: String) { lock.withLock { items.append(pseudo) } }
    }

    /// Stands for the avatar cache: a pseudo is cached from the start, or once offered when `offersAreStored`.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var pseudos: Set<String>
        init(_ pseudos: Set<String>) { self.pseudos = pseudos }
        func contains(_ pseudo: String) -> Bool { lock.withLock { pseudos.contains(pseudo.lowercased()) } }
        func add(_ pseudo: String) { lock.withLock { _ = pseudos.insert(pseudo.lowercased()) } }
    }

    private func prefetcher(
        _ lookup: ScriptedLookup, cached: Set<String> = [], offers: Offers = Offers(), spacing: Duration = .zero,
        retryDelay: Duration = .seconds(60), offersAreStored: Bool = true
    ) -> MemberAvatarPrefetcher {
        let cache = Cache(cached)
        return MemberAvatarPrefetcher(
            lookup: lookup, spacing: spacing, retryDelay: retryDelay, hasAvatar: { cache.contains($0) },
            offer: { pseudo, url in
                #expect(url == Self.avatar)
                offers.add(pseudo)
                if offersAreStored { cache.add(pseudo) }
            }
        )
    }

    @Test func aMissingAvatarIsLookedUpAndOffered() async {
        let lookup = ScriptedLookup()
        let offers = Offers()
        await prefetcher(lookup, offers: offers).prefetch(pseudo: " user2 ")
        #expect(lookup.pseudos == ["user2"])
        #expect(offers.pseudos == ["user2"])
    }

    /// Never twice: the same pseudo, in any case, after a success or after HFR said there is no avatar.
    @Test func aPseudoIsLookedUpOnceOnceHFRAnswered() async {
        let lookup = ScriptedLookup { $0 == "user3" ? .none : .avatar(MemberAvatarPrefetcherTests.avatar) }
        let offers = Offers()
        let prefetcher = prefetcher(lookup, offers: offers)
        for pseudo in ["user2", "User2", "USER2", "user3", "user3"] {
            await prefetcher.prefetch(pseudo: pseudo)
        }
        #expect(lookup.pseudos == ["user2", "user3"])
        #expect(offers.pseudos == ["user2"])
    }

    /// A failed exchange (a list opened offline) is not asked again at once, and is once its retry time has passed.
    @Test func aFailedLookupIsRetriedOnlyAfterItsDelay() async throws {
        let lookup = ScriptedLookup { _ in .failed }
        let prefetcher = prefetcher(lookup, retryDelay: .milliseconds(200))
        await prefetcher.prefetch(pseudo: "user2")
        await prefetcher.prefetch(pseudo: "user2")
        #expect(lookup.pseudos == ["user2"])
        try await Task.sleep(for: .milliseconds(250))
        await prefetcher.prefetch(pseudo: "user2")
        #expect(lookup.pseudos == ["user2", "user2"])
    }

    /// An avatar the store did not keep (a failed download) counts as a failure: retried after the delay, not at once.
    @Test func anAvatarNotStoredIsRetriedOnlyAfterItsDelay() async throws {
        let lookup = ScriptedLookup()
        let offers = Offers()
        let prefetcher = prefetcher(lookup, offers: offers, retryDelay: .milliseconds(200), offersAreStored: false)
        await prefetcher.prefetch(pseudo: "user2")
        await prefetcher.prefetch(pseudo: "user2")
        #expect(lookup.pseudos == ["user2"])
        try await Task.sleep(for: .milliseconds(250))
        await prefetcher.prefetch(pseudo: "user2")
        #expect(offers.pseudos == ["user2", "user2"])
    }

    @Test func aCachedAvatarOrABlankPseudoIsNotLookedUp() async {
        let lookup = ScriptedLookup()
        let prefetcher = prefetcher(lookup, cached: ["user2"])
        for pseudo in ["User2", "", "  "] {
            await prefetcher.prefetch(pseudo: pseudo)
        }
        #expect(lookup.pseudos.isEmpty)
    }

    /// Rows shown together: their lookups run one after the other, never two at once, and each runs once.
    @Test func lookupsRunOneAtATime() async {
        let lookup = ScriptedLookup()
        let prefetcher = prefetcher(lookup)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<6 {
                group.addTask { await prefetcher.prefetch(pseudo: "user\(index % 3)") }
            }
        }
        #expect(lookup.maximumConcurrency == 1)
        #expect(lookup.pseudos.sorted() == ["user0", "user1", "user2"])
    }

    /// Two lookups start at least `spacing` apart (the live prefetcher's is one second).
    @Test func lookupsAreSpaced() async {
        let lookup = ScriptedLookup()
        let prefetcher = prefetcher(lookup, spacing: .milliseconds(200))
        let clock = ContinuousClock()
        let start = clock.now
        await prefetcher.prefetch(pseudo: "user1")
        await prefetcher.prefetch(pseudo: "user2")
        #expect(clock.now - start >= .milliseconds(200))
        #expect(lookup.pseudos == ["user1", "user2"])
    }

    /// A row that left the screen before its turn is not looked up, and is when it shows again.
    @Test func aRowGoneBeforeItsTurnIsNotLookedUp() async {
        let lookup = ScriptedLookup()
        let prefetcher = prefetcher(lookup)
        let first = Task { await prefetcher.prefetch(pseudo: "user1") }
        // Let the first lookup take the turn before the second row asks.
        while lookup.pseudos.isEmpty { await Task.yield() }
        let gone = Task { await prefetcher.prefetch(pseudo: "user2") }
        gone.cancel()
        await first.value
        await gone.value
        #expect(lookup.pseudos == ["user1"])
        await prefetcher.prefetch(pseudo: "user2")
        #expect(lookup.pseudos == ["user1", "user2"])
    }

    // MARK: - Live lookup

    private struct LiveRig {
        let lookup: LiveMemberAvatarLookup
        let session: MockTransport
        let anonymous: MockTransport
    }

    /// `profilebdd.php` answers the `301` of `R716a`/`R716c` (a member id); the profile served is `R1363b`.
    /// Both clients answer the same, so only the request counts catch a lookup that would use the wrong one.
    private func liveRig(location: String = "/hfr/profil-910002.htm") throws -> LiveRig {
        let profile = try LiveTopicPageSourceTests.capture("R1363b-profile-own-user1.html")
        let handler: MockTransport.Handler = { request async throws(NetworkError) -> HTTPResponse in
            if request.url.path() == "/profilebdd.php" {
                return HTTPResponse(statusCode: 301, headers: ["Location": location], url: request.url)
            }
            return HTTPResponse(
                statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: request.url, body: profile
            )
        }
        let session = MockTransport(handler: handler)
        let anonymous = MockTransport(handler: handler)
        let fetcher = PageFetcher(session: session, anonymous: anonymous)
        return LiveRig(
            lookup: LiveMemberAvatarLookup(
                fetcher: fetcher, profiles: LiveUserProfileSource(fetcher: fetcher, isLoggedIn: { true })
            ),
            session: session, anonymous: anonymous
        )
    }

    /// The id lookup leaves without cookies (`R716c`); the profile goes through the session, HFR refusing it without (#1363).
    @Test func theLiveLookupFindsTheIdWithoutCookiesAndReadsTheProfileWithTheSession() async throws {
        let rig = try liveRig()
        let data = try LiveTopicPageSourceTests.capture("R1363b-profile-own-user1.html")
        let html = try #require(String(data: data, encoding: .utf8))
        let expected = try #require(try UserProfileParser.parse(html: html).avatarURL)
        #expect(await rig.lookup.avatar(forPseudo: "user two") == .avatar(expected))
        let anonymous = await rig.anonymous.requests
        #expect(anonymous.map(\.url.absoluteString) == ["https://forum.hardware.fr/profilebdd.php?config=hfr.inc&pseudo=user%20two"])
        #expect(anonymous.first?.redirectPolicy == .doNotFollow)
        #expect(anonymous.allSatisfy { $0.headers["Cookie"] == nil })
        #expect(await rig.session.requests.map(\.url.absoluteString) == ["https://forum.hardware.fr/hfr/profil-910002.htm"])
    }

    /// HFR's 403 to a profile (`R1363a`) is a failure, asked again later, not "no avatar".
    @Test func aRefusedProfileIsAFailure() async {
        let redirect = MockTransport { request async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: 301, headers: ["Location": "/hfr/profil-910002.htm"], url: request.url)
        }
        let refused = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            throw .httpStatus(code: 403, url: url("https://forum.hardware.fr/hfr/profil-910002.htm"))
        }
        let fetcher = PageFetcher(session: refused, anonymous: redirect)
        let lookup = LiveMemberAvatarLookup(fetcher: fetcher, profiles: LiveUserProfileSource(fetcher: fetcher, isLoggedIn: { true }))
        #expect(await lookup.avatar(forPseudo: "user2") == .failed)
        #expect(await refused.requests.count == 1)
    }

    /// An unknown pseudo (`R716d`: empty id) stops after the first request, as HFR's answer; a location that is not a profile too.
    @Test(arguments: ["/hfr/profil-.htm", "/forum2.php?config=hfr.inc", "https://evil.example/hfr/profil-910002.htm"])
    func anUnknownMemberCostsOneRequest(location: String) async throws {
        let rig = try liveRig(location: location)
        #expect(await rig.lookup.avatar(forPseudo: "user3") == .none)
        #expect(await rig.anonymous.requests.count == 1)
        #expect(await rig.session.requests.isEmpty)
    }

    /// A failed exchange is `.failed`, not "no avatar", so the prefetcher asks again later.
    @Test func aTransportFailureIsAFailure() async {
        let offline = MockTransport { _ async throws(NetworkError) -> HTTPResponse in throw .offline }
        let fetcher = PageFetcher(session: MockTransport(replies: []), anonymous: offline)
        let lookup = LiveMemberAvatarLookup(fetcher: fetcher, profiles: LiveUserProfileSource(fetcher: fetcher, isLoggedIn: { true }))
        #expect(await lookup.avatar(forPseudo: "user2") == .failed)
    }
}
