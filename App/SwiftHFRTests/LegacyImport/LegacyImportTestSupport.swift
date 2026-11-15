import Foundation
import HFRStorage
@testable import SwiftHFR

/// Answers each run with the next scripted report (an empty report once they are used up) and records the account passed.
actor ScriptedLegacyImport: LegacyImportRunning {
    private var reports: [LegacyImportReport]
    /// The `currentAccount` of each run, in order.
    private(set) var accounts: [String?] = []

    init(_ reports: [LegacyImportReport]) {
        self.reports = reports
    }

    func importLegacyData(currentAccount: String?) async -> LegacyImportReport {
        accounts.append(currentAccount)
        return reports.isEmpty ? LegacyImportReport() : reports.removeFirst()
    }
}

/// A report where every step not named is `nothingToImport` (so the report is complete unless a named step is not done).
func importReport(_ outcomes: [LegacyImportStep: LegacyImportOutcome] = [:], rejected: Int = 0) -> LegacyImportReport {
    var all = Dictionary(uniqueKeysWithValues: LegacyImportStep.allCases.map { ($0, LegacyImportOutcome.nothingToImport) })
    all.merge(outcomes) { _, named in named }
    return LegacyImportReport(outcomes: all, rejectedItems: rejected)
}
