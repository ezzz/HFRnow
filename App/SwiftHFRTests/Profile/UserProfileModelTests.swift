import Foundation
import HFRParsing
@testable import SwiftHFR
import Testing

/// A scripted profile source: answers in order, counts the members asked for.
final class FakeUserProfiles: UserProfileSource, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<UserProfile, ListLoadError>]
    private var asked: [Int] = []

    init(_ answers: [Result<UserProfile, ListLoadError>]) { self.answers = answers }

    var requests: [Int] { lock.withLock { asked } }

    func profile(memberID: Int) async throws(ListLoadError) -> UserProfile {
        let next: Result<UserProfile, ListLoadError> = lock.withLock {
            asked.append(memberID)
            return answers.isEmpty ? .failure(.other) : answers.removeFirst()
        }
        return try next.get()
    }
}

/// The profile screen's model (LOT-116), on the captured profiles.
@MainActor
struct UserProfileModelTests {
    static func captured(_ name: String) throws -> UserProfile {
        let data = try LiveTopicPageSourceTests.capture(name)
        return try UserProfileParser.parse(html: try #require(String(data: data, encoding: .utf8)))
    }

    @Test func theFirstAppearanceLoadsTheMemberOnce() async throws {
        let profile = try Self.captured("R56b-profile-other-member-anon.html")
        let source = FakeUserProfiles([.success(profile)])
        let model = UserProfileModel(memberID: 910_002, source: source)
        #expect(model.title == "Profil")
        await model.onAppear()
        await model.onAppear()
        #expect(source.requests == [910_002])
        #expect(model.profile == profile)
        #expect(model.title == profile.pseudo)
        #expect(model.error == nil)
    }

    /// A failed first load shows the error; "Réessayer" loads again and the profile replaces it.
    @Test func aFailedLoadIsRetried() async throws {
        let profile = try Self.captured("R56a-profile-operator-anon.html")
        let source = FakeUserProfiles([.failure(.unreadable), .success(profile)])
        let model = UserProfileModel(memberID: 910_001, source: source)
        await model.onAppear()
        #expect(model.profile == nil)
        #expect(model.error == .unreadable)
        await model.reload()
        #expect(model.profile == profile)
        #expect(model.error == nil)
        #expect(source.requests == [910_001, 910_001])
    }

    /// Every finished load, failed or not, bumps the generation the images key their task on: a reload retries a failed image.
    @Test func everyFinishedLoadBumpsTheImageGeneration() async throws {
        let profile = try Self.captured("R56a-profile-operator-anon.html")
        let source = FakeUserProfiles([.success(profile), .failure(.offline), .success(profile)])
        let model = UserProfileModel(memberID: 910_001, source: source)
        #expect(model.loadGeneration == 0)
        await model.onAppear()
        #expect(model.loadGeneration == 1)
        await model.reload()
        #expect(model.loadGeneration == 2)
        await model.reload()
        #expect(model.loadGeneration == 3)
    }

    /// A failed reload keeps the profile on screen with the error (banner).
    @Test func aFailedReloadKeepsTheProfile() async throws {
        let profile = try Self.captured("R56a-profile-operator-anon.html")
        let model = UserProfileModel(memberID: 910_001, source: FakeUserProfiles([.success(profile), .failure(.offline)]))
        await model.onAppear()
        await model.reload()
        #expect(model.profile == profile)
        #expect(model.error == .offline)
    }

    /// The MP button exists only once LOT-128 wires a composer, and hands it the page's pseudo.
    @Test func theMessageButtonFollowsTheHook() async throws {
        let profile = try Self.captured("R56b-profile-other-member-anon.html")
        let unwired = UserProfileModel(memberID: 910_002, source: FakeUserProfiles([.success(profile)]))
        await unwired.onAppear()
        #expect(unwired.privateMessageRecipient == nil)

        var written: [String] = []
        let wired = UserProfileModel(memberID: 910_002, source: FakeUserProfiles([.success(profile)])) { written.append($0) }
        #expect(wired.privateMessageRecipient == nil)
        wired.writePrivateMessage()
        #expect(written.isEmpty)
        await wired.onAppear()
        #expect(wired.privateMessageRecipient == profile.pseudo)
        wired.writePrivateMessage()
        #expect(written == [profile.pseudo])
    }

    /// Field links and the page's link rows open in a browser, never in the app with the session (LESSONS 43).
    @Test func linksOpenInABrowser() throws {
        let model = UserProfileModel(memberID: 1, source: FakeUserProfiles([]))
        let site = url("https://example.com/member")
        #expect(model.action(forLink: site, defaultBrowser: false) == .inAppBrowser(site))
        #expect(model.action(forLink: site, defaultBrowser: true) == .defaultBrowser(site))
        let forum = url("https://forum.hardware.fr/hfr/recherche/pseudo-user3.htm")
        #expect(model.action(forLink: forum, defaultBrowser: false) == .inAppBrowser(forum))
        #expect(model.action(forLink: url("javascript:alert(1)"), defaultBrowser: false) == .ignored)
    }
}
