import Foundation
import HFRStorage

// Port of none @ 87fe0d1c: legacy was the app this update replaces and never imported its data (GAP-170, new UX: spec).
/// What the legacy import did during this launch, in French and in counts only (LOT-158): the content of the summary sheet.
///
/// Built from every report of the launch: each step keeps its most informative outcome, so a later run that finds the step
/// `alreadyDone` never hides what an earlier run imported.
struct LegacyImportSummary: Identifiable, Equatable, Sendable {
    /// One line of the sheet.
    struct Row: Identifiable, Equatable, Sendable {
        let step: LegacyImportStep
        /// The item, "Comptes".
        let title: String
        /// What happened to it, "2 comptes".
        let detail: String
        /// The step failed and will be retried: shown as a warning.
        let isFailure: Bool

        var id: LegacyImportStep { step }
    }

    /// The steps that hold the user's data; `mpStorageSwitch` (kept for LOT-130) and `pageCache` (a clean-up) are not.
    static let dataSteps: [LegacyImportStep] = [
        .accounts, .pseudoLists, .superFavorites, .collapsedSections, .smileyFavorites, .smileySearchHistory, .uploadHistory,
        .drafts
    ]

    /// The outcome kept for each step.
    private(set) var outcomes: [LegacyImportStep: LegacyImportOutcome] = [:]
    /// Legacy accounts or pseudos the stores refused, over every run.
    private(set) var rejectedItems = 0

    /// One sheet per launch: the sheet stays the same while a retry refreshes it.
    let id: UUID

    /// An empty summary.
    init(id: UUID = UUID()) {
        self.id = id
    }

    /// Adds a run's report. A step runs again only while it is not done, so its latest outcome is the true one; only
    /// `alreadyDone` (a step done by an earlier run) never replaces what that run said.
    mutating func add(_ report: LegacyImportReport) {
        for (step, outcome) in report.outcomes where outcome != .alreadyDone || outcomes[step] == nil {
            outcomes[step] = outcome
        }
        rejectedItems += report.rejectedItems
    }

    /// Whether the sheet has something to say: a data step imported something or failed, or items were refused. A launch
    /// with nothing to import, or after a complete import, stays silent; so does a page-cache clean-up alone.
    var isWorthShowing: Bool {
        rejectedItems > 0 || Self.dataSteps.contains { step in
            switch outcomes[step] {
            case .imported(let count): count > 0
            case .failed: true
            case .nothingToImport, .alreadyDone, .waitingForAccount, nil: false
            }
        }
    }

    /// A data step failed with an error the next run may not meet: "Réessayer" is offered (a page-cache failure is retried
    /// quietly at the next launch).
    var canRetry: Bool {
        Self.dataSteps.contains { outcomes[$0].map(Self.isRetriable) == true }
    }

    /// The lines of the sheet, in step order: every data step that has something to say, and the page cache when pages went.
    var rows: [Row] {
        var rows: [Row] = []
        for step in Self.dataSteps {
            guard let outcome = outcomes[step], let detail = Self.detail(of: outcome, step: step) else { continue }
            rows.append(Row(step: step, title: Self.title(of: step), detail: detail, isFailure: Self.isRetriable(outcome)))
        }
        switch outcomes[.pageCache] {
        case .imported(let count) where count > 0:
            rows.append(Row(
                step: .pageCache, title: Self.title(of: .pageCache),
                detail: FrenchPlural.count(count, "page supprimée", "pages supprimées"), isFailure: false
            ))
        default:
            break
        }
        return rows
    }

    /// The refused items line; nil when none.
    var rejectedLine: String? {
        guard rejectedItems > 0 else { return nil }
        return FrenchPlural.count(rejectedItems, "élément refusé", "éléments refusés") + " (pseudo vide ou invalide)"
    }

    // MARK: - Wording

    /// The French name of a step's data.
    static func title(of step: LegacyImportStep) -> String {
        switch step {
        case .accounts: "Comptes"
        case .pseudoLists: "Listes noire et blanche"
        case .superFavorites: "Super favoris"
        case .collapsedSections: "Sections repliées des favoris"
        case .smileyFavorites: "Smileys favoris"
        case .smileySearchHistory: "Recherches de smileys"
        case .uploadHistory: "Images envoyées"
        case .drafts: "Brouillons"
        case .mpStorageSwitch: "Synchronisation MPStorage"
        case .pageCache: "Ancien cache des pages"
        }
    }

    /// What an outcome says, nil when the row is not shown (`nothingToImport`, `alreadyDone`, nothing imported).
    static func detail(of outcome: LegacyImportOutcome, step: LegacyImportStep) -> String? {
        switch outcome {
        case .imported(let count): count > 0 ? importedDetail(count, step: step) : nil
        case .nothingToImport, .alreadyDone: nil
        case .waitingForAccount: "En attente d’un compte : repris à la première connexion"
        case .failed(.sourceUnreadable): "Illisible : ignoré, l’original est conservé"
        case .failed(.sourceUnavailable), .failed(.destinationFailed): "Échec : sera réessayé"
        }
    }

    private static func importedDetail(_ count: Int, step: LegacyImportStep) -> String {
        switch step {
        case .accounts: FrenchPlural.count(count, "compte", "comptes")
        case .pseudoLists: FrenchPlural.count(count, "pseudo", "pseudos")
        case .superFavorites:
            "\(FrenchPlural.count(count, "sujet", "sujets")), \(agreed("placé", count)) au prochain chargement des favoris"
        case .collapsedSections: FrenchPlural.count(count, "section", "sections")
        case .smileyFavorites: FrenchPlural.count(count, "smiley", "smileys")
        case .smileySearchHistory: FrenchPlural.count(count, "recherche", "recherches")
        case .uploadHistory: FrenchPlural.count(count, "image", "images")
        case .drafts: "\(FrenchPlural.count(count, "brouillon", "brouillons")), \(agreed("rouvert", count)) à l’ouverture du sujet"
        case .mpStorageSwitch: FrenchPlural.count(count, "réglage", "réglages")
        case .pageCache: FrenchPlural.count(count, "page supprimée", "pages supprimées")
        }
    }

    /// A past participle agreeing with `count` (French: zero and one are singular).
    private static func agreed(_ participle: String, _ count: Int) -> String {
        abs(count) <= 1 ? participle : participle + "s"
    }

    private static func isRetriable(_ outcome: LegacyImportOutcome) -> Bool {
        outcome == .failed(.sourceUnavailable) || outcome == .failed(.destinationFailed)
    }
}
