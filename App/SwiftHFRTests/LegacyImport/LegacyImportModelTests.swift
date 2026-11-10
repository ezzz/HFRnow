import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-158: when the import runs and when its summary shows.
@MainActor
struct LegacyImportModelTests {
    @Test func theLaunchRunHappensOnceAndNamesNoAccount() async {
        let importer = ScriptedLegacyImport([importReport(), importReport()])
        let model = LegacyImportModel(importer: importer)
        await model.runAtLaunch()
        await model.runAtLaunch()
        #expect(await importer.accounts == [nil])
        #expect(!model.isRunning)
    }

    @Test func aLaunchWithNothingToImportOrOnlyWaitingStepsShowsNothing() async {
        let waiting = importReport([.superFavorites: .waitingForAccount, .drafts: .waitingForAccount, .pageCache: .imported(12)])
        let model = LegacyImportModel(importer: ScriptedLegacyImport([waiting]))
        await model.runAtLaunch()
        #expect(model.summary == nil)
        #expect(model.lastReport == waiting)
    }

    @Test func aLaunchAfterACompleteImportShowsNothing() async {
        let done = LegacyImportReport(
            outcomes: Dictionary(uniqueKeysWithValues: LegacyImportStep.allCases.map { ($0, LegacyImportOutcome.alreadyDone) })
        )
        let model = LegacyImportModel(importer: ScriptedLegacyImport([done]))
        await model.runAtLaunch()
        #expect(model.summary == nil)
    }

    @Test func anImportShowsTheSummary() async throws {
        let model = LegacyImportModel(importer: ScriptedLegacyImport([importReport([.accounts: .imported(2)])]))
        await model.runAtLaunch()
        let summary = try #require(model.summary)
        #expect(summary.rows.map(\.title) == ["Comptes"])
        #expect(summary.rows.first?.detail == "2 comptes")
    }

    @Test func refusedItemsAloneShowTheSummary() async {
        let model = LegacyImportModel(importer: ScriptedLegacyImport([importReport(rejected: 1)]))
        await model.runAtLaunch()
        #expect(model.summary?.rejectedLine == "1 élément refusé (pseudo vide ou invalide)")
    }

    @Test func aRetryRunsWithTheCurrentAccountAndKeepsWhatTheFirstRunImported() async throws {
        let importer = ScriptedLegacyImport([
            importReport([.accounts: .imported(2), .drafts: .failed(.destinationFailed)]),
            importReport([.accounts: .alreadyDone, .drafts: .imported(1)])
        ])
        let model = LegacyImportModel(importer: importer)
        await model.runAtLaunch()
        #expect(model.summary?.canRetry == true)
        let summaryID = try #require(model.summary?.id)
        await model.retry(currentAccount: "user1")
        let summary = try #require(model.summary)
        #expect(summary.id == summaryID)
        #expect(summary.rows.map(\.detail) == ["2 comptes", "1 brouillon, rouvert à l’ouverture du sujet"])
        #expect(!summary.canRetry)
        #expect(await importer.accounts == [nil, "user1"])
    }

    @Test func aLaterRunThatFailsAgainShowsTheClosedSheetAgain() async {
        let importer = ScriptedLegacyImport([
            importReport([.drafts: .failed(.sourceUnavailable)]), importReport([.drafts: .failed(.sourceUnavailable)])
        ])
        let model = LegacyImportModel(importer: importer)
        await model.runAtLaunch()
        model.summary = nil
        await model.accountDidChange(to: "user1")
        // The failure is the same, but a run that failed says something: the sheet shows again.
        #expect(model.summary?.canRetry == true)
    }

    @Test func aClosedSheetStaysClosedWhenALaterRunOnlyFindsStepsDone() async {
        let importer = ScriptedLegacyImport([
            importReport([.accounts: .imported(1), .superFavorites: .waitingForAccount]), importReport([.accounts: .alreadyDone])
        ])
        let model = LegacyImportModel(importer: importer)
        await model.runAtLaunch()
        model.summary = nil
        await model.accountDidChange(to: "user1")
        #expect(model.summary == nil)
        #expect(await importer.accounts == [nil, "user1"])
    }

    @Test func anAccountChangeRunsTheImportOnlyWhileIncompleteAndWithAnAccount() async {
        let importer = ScriptedLegacyImport([
            importReport([.superFavorites: .waitingForAccount]), importReport([.superFavorites: .imported(3)])
        ])
        let model = LegacyImportModel(importer: importer)
        await model.accountDidChange(to: "user1") // before the launch run: nothing is known yet
        await model.runAtLaunch()
        await model.accountDidChange(to: nil) // logged out: nobody to receive the global items
        await model.accountDidChange(to: "user1")
        await model.accountDidChange(to: "user2") // complete now
        #expect(await importer.accounts == [nil, "user1"])
        #expect(model.lastReport?.isComplete == true)
    }

    @Test func aRunSaysWhenItImportedAccounts() async {
        let importer = ScriptedLegacyImport([
            importReport([.accounts: .failed(.sourceUnavailable)]), importReport([.accounts: .nothingToImport]),
            importReport([.accounts: .imported(1)])
        ])
        let model = LegacyImportModel(importer: importer)
        await model.runAtLaunch()
        #expect(model.summary?.canRetry == true)
        #expect(await model.retry(currentAccount: nil) == false)
        // The open sheet is refreshed by a retry that finds nothing: the failure and its button go.
        #expect(model.summary?.canRetry == false)
        #expect(await model.retry(currentAccount: nil) == true)
    }

    @Test func overlappingRunsAreCountedUntilTheLastEnds() async {
        let gate = ImportGate()
        let model = LegacyImportModel(importer: GatedLegacyImport(gate: gate))
        let first = Task { await model.runAtLaunch() }
        await gate.untilArrived(1)
        let second = Task { await model.retry(currentAccount: "user1") }
        await gate.untilArrived(2)
        #expect(model.isRunning)
        await gate.release()
        await first.value
        #expect(await second.value == false)
        #expect(!model.isRunning)
    }
}

/// Holds every run until `release()`.
actor ImportGate {
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var released = false

    func arrive() async {
        arrivals += 1
        for waiter in arrivalWaiters where waiter.count <= arrivals { waiter.continuation.resume() }
        arrivalWaiters.removeAll { $0.count <= arrivals }
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func untilArrived(_ count: Int) async {
        if arrivals >= count { return }
        await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// An import that waits at the gate, then finds nothing.
struct GatedLegacyImport: LegacyImportRunning {
    let gate: ImportGate

    func importLegacyData(currentAccount: String?) async -> LegacyImportReport {
        await gate.arrive()
        return importReport()
    }
}
