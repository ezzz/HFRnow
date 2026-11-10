import Foundation
import HFRModels
import HFRParsing
@testable import SwiftHFR
import Testing

@MainActor
struct AboutModelTests {
    private func model(version: AppVersion = AppVersion(info: [:])) -> AboutModel {
        AboutModel(version: version, topicPages: FakeTopicPages())
    }

    @Test func versionShowsShortVersionAndBuild() {
        let version = AppVersion(info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "42"])
        #expect(version.display == "1.0 (42)")
    }

    @Test func aMissingOrNonTextKeyShowsAQuestionMark() {
        #expect(AppVersion(info: nil).display == "? (?)")
        #expect(AppVersion(info: ["CFBundleShortVersionString": 1, "CFBundleVersion": "7"]).display == "? (7)")
    }

    @Test func theTwoLinksAreTheOperatorsIdForms() {
        #expect(AboutTopicLink.allCases.map(\.title) == ["[TU] Super HFR+", "Beta"])
        #expect(AboutTopicLink.superHFRPlus.address == "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=25&post=1711&page=1")
        #expect(
            AboutTopicLink.beta.address
                == "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=25&subcat=528&post=8811&page=1"
        )
    }

    @Test func eachLinkIsATopicRouteOfTheAppleCategoryNotABrowserLink() throws {
        let expected: [(AboutTopicLink, Int)] = [(.superHFRPlus, 1711), (.beta, 8811)]
        for (link, post) in expected {
            let url = try #require(URL(string: link.address))
            guard case .topic(let routed) = HFRLinkRoute.route(for: url) else {
                Issue.record("\(link) is not routed as a topic")
                continue
            }
            #expect(routed.id == TopicID(category: .forum(25), topic: post))
            #expect(routed.page == 1)
            #expect(link.target == ReaderTarget(source: .topic(routed.id), page: 1))
        }
    }

    @Test func aLinkOpensItsTopicInTheReader() throws {
        let about = model()
        let reader = try #require(about.reader(for: .superHFRPlus))
        #expect(reader.requested == ReaderTarget(source: .topic(TopicID(category: .forum(25), topic: 1711)), page: 1))
        #expect(reader.title == "[TU] Super HFR+")
        let beta = try #require(about.reader(for: .beta))
        #expect(beta.requested.source == .topic(TopicID(category: .forum(25), topic: 8811)))
    }

    @Test func theSameLinkKeepsItsReaderAcrossRebuilds() throws {
        let about = model()
        let first = try #require(about.reader(for: .beta))
        #expect(about.reader(for: .beta) === first)
        #expect(about.reader(for: .superHFRPlus) !== first)
    }

    @Test func readingATopicRequestsOnlyItsPage() async throws {
        let pages = FakeTopicPages()
        let about = AboutModel(topicPages: pages)
        let reader = try #require(about.reader(for: .superHFRPlus))
        await reader.onAppear()
        #expect(pages.requests.map(\.source) == [.topic(TopicID(category: .forum(25), topic: 1711))])
    }
}
