import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

struct MultiQuoteCookieTests {
    private let topic = TopicID(category: .forum(13), topic: 42)
    private func token(_ numreponse: Int) -> QuoteSelectionToken {
        QuoteSelectionToken(forum: "hardwarefr", topic: topic, numreponse: numreponse)
    }

    private func toggled(_ selection: inout MultiQuoteCookie, _ numreponse: Int) -> Bool {
        selection.toggle(numreponse)
    }

    @Test func nameFollowsTheQuoterArguments() {
        #expect(MultiQuoteCookie.name(for: token(1)) == "quoteshardwarefr-13-42")
        let privateTopic = QuoteSelectionToken(forum: "hardwarefr", topic: TopicID(category: .privateMessages, topic: 7), numreponse: 1)
        #expect(MultiQuoteCookie.name(for: privateTopic) == "quoteshardwarefr-prive-7")
    }

    @Test func toggleAppendsThenRemoves() {
        var selection = MultiQuoteCookie(token: token(12))
        #expect(toggled(&selection, 12) == true)
        #expect(toggled(&selection, 1) == true)
        #expect(selection.value == "|12|1")
        #expect(toggled(&selection, 12) == false)
        #expect(selection.value == "|1")
        #expect(toggled(&selection, 1) == false)
        #expect(selection.isEmpty)
        #expect(selection.value.isEmpty)
    }

    /// Legacy `contains("|1")` saw `|12` as selecting 1, and `replacingOccurrences(of: "|1")` turned `|12|1` into `2`.
    @Test func matchIsExactNotSubstring() {
        var selection = MultiQuoteCookie(name: "quoteshardwarefr-13-42", value: "|12|123")
        #expect(!selection.contains(1))
        #expect(toggled(&selection, 1) == true)
        #expect(selection.value == "|12|123|1")
        #expect(toggled(&selection, 1) == false)
        #expect(selection.value == "|12|123")
        #expect(selection.selectedNumbers == [12, 123])
    }

    @Test func parsingDropsEmptySegmentsAndKeepsUnknownMarkers() {
        let selection = MultiQuoteCookie(name: "q", value: "||5|x|6|")
        #expect(selection.markers == ["5", "x", "6"])
        #expect(selection.selectedNumbers == [5, 6])
        #expect(selection.value == "|5|x|6")
    }

    @Test func removingADuplicatedMarkerRemovesEveryCopy() {
        var selection = MultiQuoteCookie(name: "q", value: "|5|6|5")
        #expect(toggled(&selection, 5) == false)
        #expect(selection.value == "|6")
    }

    @Test func storedCookieHasSiteAttributesAndOneHourOfLife() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var selection = MultiQuoteCookie(token: token(9))
        #expect(selection.storedCookie(now: now) == nil)
        selection.toggle(9)
        let cookie = try #require(selection.storedCookie(now: now))
        #expect(cookie.name == "quoteshardwarefr-13-42")
        #expect(cookie.value == "|9")
        #expect(cookie.domain == ".hardware.fr")
        #expect(cookie.path == "/")
        #expect(cookie.expiresDate == now.addingTimeInterval(3600))
    }
}
