import Foundation

/// The themes the app offers (LOT-188): the decoded theme files, Legacy always first, the others by family then name.
public struct ThemeCatalog: Sendable, Equatable {
    /// The Legacy theme as the app knows it even without its file: today's look (LOT-121/122), credited to Ezzz (THEMES.md §2).
    public static let legacy = ThemeDefinition(
        id: ThemeDefinition.legacyID, name: "Legacy", family: "Classiques", author: "Ezzz", variants: nil
    )

    /// Every theme, Legacy first.
    public let themes: [ThemeDefinition]

    /// A file that could not be decoded, or whose id was already taken; the catalog leaves it out.
    public struct Rejection: Sendable, Equatable, CustomStringConvertible {
        /// Where the file came from (its name).
        public let source: String
        /// Why it was left out.
        public let reason: String

        public var description: String { "\(source): \(reason)" }
    }

    /// The files left out.
    public let rejections: [Rejection]

    /// Builds the catalog from theme files (`source` names each one in `rejections`). A file that does not decode, or a
    /// second file with an id already seen, is left out; a missing Legacy file is replaced by `legacy`.
    public init(files: [(source: String, data: Data)]) {
        var byID: [String: ThemeDefinition] = [:]
        var rejections: [Rejection] = []
        for file in files.sorted(by: { $0.source < $1.source }) {
            do {
                let theme = try JSONDecoder().decode(ThemeDefinition.self, from: file.data)
                guard byID[theme.id] == nil else {
                    rejections.append(Rejection(source: file.source, reason: "duplicate id \(theme.id)"))
                    continue
                }
                byID[theme.id] = theme
            } catch {
                rejections.append(Rejection(source: file.source, reason: String(describing: error)))
            }
        }
        let legacy = byID.removeValue(forKey: ThemeDefinition.legacyID) ?? Self.legacy
        themes = [legacy] + byID.values.sorted(by: Self.galleryOrder)
        self.rejections = rejections
    }

    /// The theme stored under `id`, or Legacy for nil or an id no file has (THEMES.md: unknown id reads as Legacy).
    public func theme(id: String?) -> ThemeDefinition {
        id.flatMap { id in themes.first { $0.id == id } } ?? themes[0]
    }

    /// The themes the gallery lists, grouped by family in `ThemeDefinition.familyOrder` (Legacy's family first); seasonal
    /// families are left out (their window is LOT-166's).
    public var galleryFamilies: [(family: String, themes: [ThemeDefinition])] {
        let shown = themes.filter { !ThemeDefinition.seasonalFamilies.contains($0.family) }
        var families: [String] = []
        for theme in shown where !families.contains(theme.family) { families.append(theme.family) }
        return families.sorted { Self.familyRank($0) < Self.familyRank($1) }
            .map { family in (family, shown.filter { $0.family == family }) }
    }

    public static func == (lhs: ThemeCatalog, rhs: ThemeCatalog) -> Bool {
        lhs.themes == rhs.themes && lhs.rejections == rhs.rejections
    }

    private static func familyRank(_ family: String) -> (Int, String) {
        (ThemeDefinition.familyOrder.firstIndex(of: family) ?? ThemeDefinition.familyOrder.count, family)
    }

    private static func galleryOrder(_ lhs: ThemeDefinition, _ rhs: ThemeDefinition) -> Bool {
        let (left, right) = (familyRank(lhs.family), familyRank(rhs.family))
        if left != right { return left < right }
        if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
        return lhs.id < rhs.id
    }
}
