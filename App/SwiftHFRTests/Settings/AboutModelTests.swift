import Foundation
import HFRModels
import HFRParsing
@testable import SwiftHFR
import Testing

@MainActor
struct AboutModelTests {
    private func model() -> AboutModel {
        AboutModel(topicPages: FakeTopicPages())
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

struct BuildReportTests {
    private let info: [String: Any] = [
        "CFBundleShortVersionString": "1.0", "CFBundleVersion": "42", "HFRGitCommit": "cd04954-dirty"
    ]

    @Test func reportHasAStableFormat() {
        let report = BuildReport(version: AppVersion(info: info), system: "iOS 27.0", model: "iPhone18,2")
        #expect(report.text == "SwiftHFR 1.0 (42) · cd04954-dirty · iOS 27.0 · iPhone18,2")
    }

    @Test func missingKeysAndCommitShowAQuestionMark() {
        let report = BuildReport(version: AppVersion(info: [:]), system: "iOS 27.0", model: "?")
        #expect(report.text == "SwiftHFR ? (?) · ? · iOS 27.0 · ?")
        #expect(AppVersion(info: ["HFRGitCommit": ""]).commit == "?")
        #expect(AppVersion(info: ["HFRGitCommit": 7]).commit == "?")
    }

    @Test func rowShowsTheCommitOnlyWhenKnown() {
        #expect(AppVersion(info: info).rowText == "1.0 (42) · cd04954-dirty")
        #expect(AppVersion(info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "42"]).rowText == "1.0 (42)")
    }

    @Test func simulatorModelWinsOverTheHostMachine() {
        #expect(BuildReport.deviceModel(machine: "arm64", environment: ["SIMULATOR_MODEL_IDENTIFIER": "iPhone18,2"]) == "iPhone18,2")
        #expect(BuildReport.deviceModel(machine: "iPhone18,2", environment: [:]) == "iPhone18,2")
        #expect(BuildReport.deviceModel(machine: "", environment: ["SIMULATOR_MODEL_IDENTIFIER": ""]) == "?")
    }
}

@MainActor
struct VersionCopyModelTests {
    private final class Sink {
        var written: [String] = []
        var announced: [String] = []
    }

    private func model(_ sink: Sink, confirmation: Duration = .milliseconds(10)) -> VersionCopyModel {
        VersionCopyModel(
            report: { "SwiftHFR 1.0 (42) · cd04954 · iOS 27.0 · iPhone18,2" },
            write: { sink.written.append($0) }, announce: { sink.announced.append($0) }, confirmation: confirmation
        )
    }

    @Test func aTapCopiesTheReportAndConfirms() async {
        let sink = Sink()
        let model = model(sink)
        model.copy()
        #expect(sink.written == ["SwiftHFR 1.0 (42) · cd04954 · iOS 27.0 · iPhone18,2"])
        #expect(sink.announced == ["Copié"])
        #expect(model.copied)
        await model.reset?.value
        #expect(!model.copied)
    }

    @Test func aSecondTapGetsTheFullConfirmation() async {
        let sink = Sink()
        let model = model(sink)
        model.copy()
        let first = model.reset
        model.copy()
        await first?.value
        #expect(model.copied)
        await model.reset?.value
        #expect(!model.copied)
        #expect(sink.written.count == 2)
    }
}
