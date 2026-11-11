import Foundation
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// `MemberAvatarPrefetcher` and its live lookup (#714): a one-to-one correspondent with no cached avatar is looked up on their
/// profile, cookie-less, one lookup at a time, at most once per pseudo. Every transport is a `MockTransport` (LESSONS 56).
struct MemberAvatarPrefetcherTests {
    private static let avatar = URL(string: "https://forum-images.hardware.fr/images/perso/a.png")!

    /// A scripted lookup that records the pseudos asked and the most lookups seen running at once.
    private final class ScriptedLookup: MemberAvatarLookup, @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        private var running = 0
        private var peak = 0
        private let answer: @Sendable (String) -> URL?

        init(answer: @escaping @Sendable (String) -> URL? = { _ in MemberAvatarPrefetcherTests.avatar }) {
            self.answer = answer
        }

        var pseudos: [String] { lock.withLock { asked } }
        var maximumConcurrency: Int { lock.withLock { peak } }

        func avatarURL(forPseudo pseudo: String) async -> URL? {
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

    private func prefetcher(
        _ lookup: ScriptedLookup, cached: Set<String> = [], offers: Offers = Offers(), spacing: Duration = .zero
    ) -> MemberAvatarPrefetcher {
        MemberAvatarPrefetcher(
            lookup: lookup, spacing: spacing, hasAvatar: { cached.contains($0.lowercased()) },
            offer: { pseudo, url in
                #expect(url == Self.avatar)
                offers.add(pseudo)
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

    /// Never twice: the same pseudo, in any case, after a success or after a lookup that found nothing.
    @Test func aPseudoIsLookedUpOnceWhateverTheOutcome() async {
        let lookup = ScriptedLookup { $0 == "user3" ? nil : MemberAvatarPrefetcherTests.avatar }
        let offers = Offers()
        let prefetcher = prefetcher(lookup, offers: offers)
        for pseudo in ["user2", "User2", "USER2", "user3", "user3"] {
            await prefetcher.prefetch(pseudo: pseudo)
        }
        #expect(lookup.pseudos == ["user2", "user3"])
        #expect(offers.pseudos == ["user2"])
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

    /// `profilebdd.php` answers the `301` of `R716a`/`R716c` (with the id of the `R56b` member); the profile is `R56b`.
    /// The session answers the same, so only the request counts catch a lookup that would use it.
    private func liveRig(location: String = "/hfr/profil-910002.htm") throws -> LiveRig {
        let profile = try LiveTopicPageSourceTests.capture("R56b-profile-other-member-anon.html")
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
        return LiveRig(
            lookup: LiveMemberAvatarLookup(fetcher: PageFetcher(session: session, anonymous: anonymous)),
            session: session, anonymous: anonymous
        )
    }

    @Test func theLiveLookupReadsTheAvatarOfTheRedirectedProfileWithoutCookies() async throws {
        let rig = try liveRig()
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture("R56b-profile-other-member-anon.html"), encoding: .utf8))
        let expected = try #require(try UserProfileParser.parse(html: html).avatarURL)
        #expect(await rig.lookup.avatarURL(forPseudo: "user two") == expected)
        #expect(await rig.session.requests.isEmpty)
        let requests = await rig.anonymous.requests
        #expect(requests.map(\.url.absoluteString) == [
            "https://forum.hardware.fr/profilebdd.php?config=hfr.inc&pseudo=user%20two",
            "https://forum.hardware.fr/hfr/profil-910002.htm"
        ])
        #expect(requests.first?.redirectPolicy == .doNotFollow)
        #expect(requests.allSatisfy { $0.headers["Cookie"] == nil })
    }

    /// An unknown pseudo (`R716d`: empty id) stops after the first request; a location that is not a profile too.
    @Test(arguments: ["/hfr/profil-.htm", "/forum2.php?config=hfr.inc", "https://evil.example/hfr/profil-910002.htm"])
    func anUnknownMemberCostsOneRequest(location: String) async throws {
        let rig = try liveRig(location: location)
        #expect(await rig.lookup.avatarURL(forPseudo: "user3") == nil)
        #expect(await rig.anonymous.requests.count == 1)
        #expect(await rig.session.requests.isEmpty)
    }
}
