import Foundation

/// One line of the changelog: a legacy problem SwiftHFR fixes or changes on purpose (`docs/CHANGELOG-LEGACY.md`, LOT-120).
struct ChangelogEntry: Decodable, Equatable, Sendable {
    /// The section the line belongs to.
    enum Section: String, Decodable, CaseIterable, Sendable {
        /// "UX": the experience.
        case experience = "UX"
        /// "T": the engine.
        case technical = "T"

        /// Heading of the section.
        var title: String {
            switch self {
            case .experience: "Expérience"
            case .technical: "Technique"
            }
        }
    }

    let section: Section
    let summary: String
}

/// The "Nouveautés" list: the "Résumé (FR)" column of `docs/CHANGELOG-LEGACY.md`, exported to the bundled
/// `changelog-v1.json` by `tooling/docs/export-app-changelog.py` (LOT-120). The v1 changelog is based on that file.
struct Changelog: Equatable, Sendable {
    /// Every line, in the file's order.
    let entries: [ChangelogEntry]

    /// The lines of `section`, in order.
    func entries(in section: ChangelogEntry.Section) -> [ChangelogEntry] {
        entries.filter { $0.section == section }
    }

    /// The sections that have lines, in display order.
    var sections: [ChangelogEntry.Section] {
        ChangelogEntry.Section.allCases.filter { section in entries.contains { $0.section == section } }
    }

    /// The changelog read from `data`; an empty one when the data is not the exported JSON (the screen then says so).
    init(data: Data) {
        entries = (try? JSONDecoder().decode([ChangelogEntry].self, from: data)) ?? []
    }

    /// The changelog bundled with the app; empty when the resource is missing.
    static func bundled(in bundle: Bundle = .main) -> Changelog {
        guard let url = bundle.url(forResource: "changelog-v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return Changelog(data: Data()) }
        return Changelog(data: data)
    }
}
