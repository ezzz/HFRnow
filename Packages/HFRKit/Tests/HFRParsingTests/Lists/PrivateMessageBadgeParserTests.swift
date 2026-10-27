import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// LOT-023: one reader for the unread private messages count, against the legacy oracle and the legacy regexes.
@Suite("Private message badge parser")
struct PrivateMessageBadgeParserTests {
    @Test("Home page: the count of the oracle's side effect (`nbMP`); logged out has none", arguments: [
        ("R01", "R01-home-anon", nil as Int?),
        ("R02", "R02-home-logged-in-unread-mp", 10),
        ("R03", "R03-home-logged-in-no-unread-mp", 0)
    ])
    func homePage(oracleName: String, capture: String, expected: Int?) throws {
        let oracle = try ForumListOracle.load(oracleName)
        #expect(oracle.sideEffects.nbMP == expected)
        #expect(try PrivateMessageBadgeParser.unreadCount(in: Fixture.capture(capture)) == expected)
    }

    @Test("Every captured list page announces what the oracle's header reader found", arguments: TopicListDifferentialTests.cases)
    func listPages(_ testCase: TopicListDifferentialTests.DifferentialCase) throws {
        let oracle = try TopicListOracle.load(testCase.name)
        let legacy = try #require(oracle.result)
        // D6 (LOT-022): the oracle keeps the whole cell text when it holds no digit; the port types it as 0.
        let expected = try #require(legacy.needToUpdateMP) ? Int(legacy.sNewMPNumber ?? "") ?? 0 : nil
        #expect(try PrivateMessageBadgeParser.unreadCount(in: oracle.capture()) == expected, Comment(rawValue: testCase.name))
    }

    @Test("The home and the list header agree with the third legacy reader, `cCatTopic red` (MPBackgroundService)")
    func backgroundServiceRegex() throws {
        // MPBackgroundService.swift:115-139, reproduced on the raw page: node text of `class="cCatTopic red"`, first integer.
        let pattern = /class=["']cCatTopic red["'][^>]*>(.*?)</
        let unread = try Fixture.capture("R02-home-logged-in-unread-mp")
        let legacy = unread.firstMatch(of: pattern).flatMap { Int($0.output.1.firstMatch(of: /[0-9]+/)?.output ?? "") }
        #expect(legacy == 10)
        #expect(try PrivateMessageBadgeParser.unreadCount(in: unread) == legacy)
        // No unread: legacy found no node and returned nil, which a poll cannot tell from a failure. The port says 0 (D2).
        let none = try Fixture.capture("R03-home-logged-in-no-unread-mp")
        #expect(none.firstMatch(of: pattern) == nil)
        #expect(try PrivateMessageBadgeParser.unreadCount(in: none) == 0)
    }

    @Test("A page without a private messages entry gives nil: the MP list, a message page, a topic page", arguments: [
        "R13a-mp-list", "R08-1-list-cat13-owntopic1-empty", "R20-topic-p1-anon"
    ])
    func noEntry(_ capture: String) throws {
        #expect(try PrivateMessageBadgeParser.unreadCount(in: Fixture.capture(capture)) == nil)
    }

    @Test("A maintenance page throws instead of reading as logged out")
    func maintenance() {
        #expect(throws: ListPageFailure.maintenance("Maintenance en cours")) {
            try PrivateMessageBadgeParser.unreadCount(in: "<html><body><p>Maintenance en cours</p></body></html>")
        }
    }

    @Test("The sentence's number may have several digits and any plural", arguments: [
        ("Vous avez 1 nouveau message privé", 1), ("Vous avez 12 nouveaux messages privés", 12), ("Messages privés", 0)
    ])
    func sentences(text: String, expected: Int) {
        #expect(PrivateMessageBadgeParser.count(inText: text) == expected)
    }
}
