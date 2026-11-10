import Foundation
@testable import SwiftHFR
import Testing

struct ChangelogTests {
    private static let json = """
    [{"id": 1, "section": "T", "summary": "Un"}, {"id": 2, "section": "UX", "summary": "Deux"},
     {"id": 3, "section": "UX", "summary": "Trois"}]
    """

    @Test func sectionsListTheirEntriesInFileOrder() {
        let changelog = Changelog(data: Data(Self.json.utf8))
        #expect(changelog.sections == [.experience, .technical])
        #expect(changelog.entries(in: .experience).map(\.summary) == ["Deux", "Trois"])
        #expect(changelog.entries(in: .technical).map(\.summary) == ["Un"])
    }

    @Test func dataThatIsNotTheExportGivesAnEmptyChangelog() {
        #expect(Changelog(data: Data("not json".utf8)).entries.isEmpty)
        #expect(Changelog(data: Data("[{\"section\": \"?\", \"summary\": \"x\"}]".utf8)).entries.isEmpty)
        #expect(Changelog(data: Data()).sections.isEmpty)
    }

    @Test func theBundledChangelogIsTheExportOfTheLegacyFixesFile() {
        let changelog = Changelog.bundled()
        #expect(changelog.entries.count > 50)
        #expect(changelog.entries.allSatisfy { !$0.summary.isEmpty && !$0.summary.contains("`") })
        #expect(changelog.sections == [.experience, .technical])
    }
}
