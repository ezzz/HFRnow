import Foundation
import HFRStorage
import Observation

/// Runs the legacy import (LOT-067): `LegacyImporter` in the app, a scripted double in tests.
protocol LegacyImportRunning: Sendable {
    /// Runs every step not done yet; `currentAccount` receives the global items when legacy had no main account (D3).
    func importLegacyData(currentAccount: String?) async -> LegacyImportReport
}

extension LegacyImporter: LegacyImportRunning {
    /// Forwards to `run(currentAccount:now:)` at the current date.
    func importLegacyData(currentAccount: String?) async -> LegacyImportReport {
        await run(currentAccount: currentAccount, now: .now)
    }
}

// Port of none @ 87fe0d1c: legacy was the app this update replaces and never imported its data (GAP-170, new UX: spec).
/// The legacy import in the app's life cycle (LOT-158): once at launch before the accounts are read, then at each change of
/// the current account until the import is complete, and on "Réessayer". Shows a summary when a run imported something or
/// failed.
///
/// The engine runs each step once and serializes overlapping runs (LOT-067), so a call here never imports twice; the model
/// only decides when to call and what to show. Nothing it holds names an account's data: counts only.
@MainActor
@Observable
final class LegacyImportModel {
    /// A run is in progress; the root screen's progress view says so.
    var isRunning: Bool { runsInFlight > 0 }
    /// The summary sheet on screen; nil when none (set to nil when the sheet is closed).
    var summary: LegacyImportSummary?
    /// The report of the last run that ended; nil before the launch run ended.
    private(set) var lastReport: LegacyImportReport?

    private var runsInFlight = 0
    /// What this launch's runs did, kept after the sheet closes so a later run's sheet tells the whole story.
    @ObservationIgnored private var launchSummary = LegacyImportSummary()
    @ObservationIgnored private var hasStartedLaunchRun = false
    @ObservationIgnored private let importer: any LegacyImportRunning

    /// Creates the model; nothing runs before `runAtLaunch()`.
    init(importer: any LegacyImportRunning) {
        self.importer = importer
    }

    /// The launch run: once per process, before the accounts are read, with no current account (none is known yet).
    func runAtLaunch() async {
        guard !hasStartedLaunchRun else { return }
        hasStartedLaunchRun = true
        await perform(currentAccount: nil)
    }

    /// The current account changed (restore, login, switch): runs the import again with it while it is not complete, so the
    /// global items waiting for an account (D3) and the steps that failed with a retriable error get their turn. Returns
    /// true when that run imported accounts: the account list must then be read again.
    @discardableResult
    func accountDidChange(to account: String?) async -> Bool {
        guard let account, let lastReport, !lastReport.isComplete else { return false }
        return await perform(currentAccount: account)
    }

    /// "Réessayer" in the summary: runs the import again with the current account and refreshes the sheet. Returns true
    /// when that run imported accounts.
    @discardableResult
    func retry(currentAccount: String?) async -> Bool {
        await perform(currentAccount: currentAccount)
    }

    /// Runs the import and shows the summary when this launch has something to say.
    @discardableResult
    private func perform(currentAccount: String?) async -> Bool {
        runsInFlight += 1
        let report = await importer.importLegacyData(currentAccount: currentAccount)
        runsInFlight -= 1
        lastReport = report
        launchSummary.add(report)
        if Self.saysSomething(report), launchSummary.isWorthShowing {
            summary = launchSummary
        } else if summary != nil {
            // A retry while the sheet is open refreshes it, even when it found nothing new.
            summary = launchSummary
        }
        if case .imported(let count) = report.outcomes[.accounts] { return count > 0 }
        return false
    }

    /// Whether a run did anything worth a sheet by itself: a run that only finds steps done or waiting opens nothing.
    private static func saysSomething(_ report: LegacyImportReport) -> Bool {
        report.rejectedItems > 0 || LegacyImportSummary.dataSteps.contains { step in
            switch report.outcomes[step] {
            case .imported(let count): count > 0
            case .failed: true
            case .nothingToImport, .alreadyDone, .waitingForAccount, nil: false
            }
        }
    }
}

extension LegacyImportModel {
    /// A model for SwiftUI previews: an import with nothing to do, so no preview reads the app's container.
    static func preview() -> LegacyImportModel {
        LegacyImportModel(importer: NothingToImport())
    }
}

/// Finds nothing, so a preview never reads the Keychain or the legacy files.
private struct NothingToImport: LegacyImportRunning {
    func importLegacyData(currentAccount: String?) async -> LegacyImportReport {
        let outcomes = LegacyImportStep.allCases.map { ($0, LegacyImportOutcome.nothingToImport) }
        return LegacyImportReport(outcomes: Dictionary(uniqueKeysWithValues: outcomes))
    }
}
