import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-158: what the summary sheet says for each outcome, counts only.
struct LegacyImportSummaryTests {
    private func summary(_ reports: LegacyImportReport...) -> LegacyImportSummary {
        var summary = LegacyImportSummary()
        reports.forEach { summary.add($0) }
        return summary
    }

    @Test func everyDataStepHasItsWordingInStepOrder() {
        let shown = summary(importReport([
            .drafts: .imported(2), .accounts: .imported(1), .pseudoLists: .imported(3), .superFavorites: .imported(1),
            .collapsedSections: .imported(2), .smileyFavorites: .imported(4), .smileySearchHistory: .imported(1),
            .uploadHistory: .imported(5)
        ]))
        #expect(shown.rows.map(\.title) == [
            "Comptes", "Listes noire et blanche", "Super favoris", "Sections repliées des favoris", "Smileys favoris",
            "Recherches de smileys", "Images envoyées", "Brouillons"
        ])
        #expect(shown.rows.map(\.detail) == [
            "1 compte", "3 pseudos", "1 sujet, placé au prochain chargement des favoris", "2 sections", "4 smileys",
            "1 recherche", "5 images", "2 brouillons, rouverts à l’ouverture du sujet"
        ])
        #expect(shown.isWorthShowing)
        #expect(!shown.canRetry)
    }

    @Test func failuresAndWaitingStepsSayWhatHappensNext() {
        let shown = summary(importReport([
            .accounts: .failed(.sourceUnavailable), .pseudoLists: .failed(.sourceUnreadable), .superFavorites: .waitingForAccount,
            .uploadHistory: .failed(.destinationFailed)
        ]))
        #expect(shown.rows.map(\.detail) == [
            "Échec : sera réessayé", "Illisible : ignoré, l’original est conservé",
            "En attente d’un compte : repris à la première connexion", "Échec : sera réessayé"
        ])
        #expect(shown.rows.map(\.isFailure) == [true, false, false, true])
        #expect(shown.canRetry)
    }

    @Test func anUnreadableSourceAloneOffersNoRetry() {
        let shown = summary(importReport([.smileyFavorites: .failed(.sourceUnreadable)]))
        #expect(shown.isWorthShowing)
        #expect(!shown.canRetry)
    }

    @Test func theMPStorageSwitchIsNeverShown() {
        let shown = summary(importReport([.mpStorageSwitch: .imported(1)]))
        #expect(shown.rows.isEmpty)
        #expect(!shown.isWorthShowing)
    }

    @Test func thePageCacheIsShownWithTheDataButNeverAlone() {
        let alone = summary(importReport([.pageCache: .imported(1)]))
        #expect(!alone.isWorthShowing)
        let withData = summary(importReport([.accounts: .imported(1), .pageCache: .imported(37)]))
        #expect(withData.rows.last?.title == "Ancien cache des pages")
        #expect(withData.rows.last?.detail == "37 pages supprimées")
        let failedCache = summary(importReport([.accounts: .imported(1), .pageCache: .failed(.sourceUnavailable)]))
        #expect(failedCache.rows.map(\.step) == [.accounts])
        #expect(!failedCache.canRetry)
    }

    @Test func aStepDoneEarlierKeepsItsResultAndALaterOutcomeReplacesAnEarlierOne() {
        let shown = summary(
            importReport([.accounts: .imported(2), .drafts: .waitingForAccount, .smileyFavorites: .failed(.sourceUnavailable)]),
            importReport([.accounts: .alreadyDone, .drafts: .nothingToImport, .smileyFavorites: .imported(3)])
        )
        #expect(shown.rows.map(\.detail) == ["2 comptes", "3 smileys"])
        #expect(!shown.canRetry)
    }

    @Test func anUnreadableSourceStaysShownAfterTheNextRunFindsItDone() {
        let shown = summary(
            importReport([.pseudoLists: .failed(.sourceUnreadable)]), importReport([.pseudoLists: .alreadyDone])
        )
        #expect(shown.rows.map(\.detail) == ["Illisible : ignoré, l’original est conservé"])
    }

    @Test func refusedItemsAddUpAcrossRuns() {
        let shown = summary(importReport(rejected: 1), importReport(rejected: 2))
        #expect(shown.rejectedLine == "3 éléments refusés (pseudo vide ou invalide)")
        #expect(summary(importReport()).rejectedLine == nil)
    }

    @Test func nothingImportedShowsNoRow() {
        let shown = summary(importReport([.accounts: .imported(0)]))
        #expect(shown.rows.isEmpty)
        #expect(!shown.isWorthShowing)
    }
}
