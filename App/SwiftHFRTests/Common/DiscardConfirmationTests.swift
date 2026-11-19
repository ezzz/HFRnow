import Foundation
import HFRClient
@testable import SwiftHFR
import Testing

/// #1169 (HIG › Sheets, › Modality): « Alerte Modération » and « Créer un sondage » ask before throwing typed text away, as the
/// composer does (#429): the swipe-down is blocked and « Annuler » asks while these predicates hold.
@MainActor
struct DiscardConfirmationTests {
    @Test func aModerationReasonAsksOnceTyped() {
        let model = ModeratorAlertComposerModel(alert: ScriptedAlertForm(.success("ok")).prepared) { _ in }
        #expect(!model.hasUnsavedReason, "nothing typed")
        model.reason = " \n\t"
        #expect(!model.hasUnsavedReason, "blank")
        model.reason = "Spam"
        #expect(model.hasUnsavedReason)
    }

    /// Once the sheet ended (sent, closed, unconfirmed) nothing is left to lose: the sheet closes by itself.
    @Test func anEndedModerationSheetHasNothingToLose() async {
        let model = ModeratorAlertComposerModel(alert: ScriptedAlertForm(.success("ok")).prepared) { _ in }
        model.reason = "Spam"
        await model.send()
        #expect(!model.hasUnsavedReason)
    }

    @Test func aPollAsksOnceAFieldDiffersFromWhatTheSheetOpenedOn() {
        let empty = PollDraft()
        #expect(!PollCreationSheet.hasChanges(empty, from: empty))
        #expect(PollCreationSheet.hasChanges(PollDraft(question: "Pizza ?"), from: empty))
        #expect(PollCreationSheet.hasChanges(PollDraft(answers: ["Oui", ""]), from: empty))
        #expect(PollCreationSheet.hasChanges(PollDraft(answers: ["", "", ""]), from: empty), "an answer added")
        #expect(PollCreationSheet.hasChanges(PollDraft(allowsVisitors: true), from: empty))
        #expect(PollCreationSheet.hasChanges(PollDraft(closingDate: Date(timeIntervalSince1970: 0)), from: empty))
        // Editing the composer's poll: unchanged is not a change.
        let existing = PollDraft(question: "Pizza ?", answers: ["Oui", "Non"])
        #expect(!PollCreationSheet.hasChanges(existing, from: existing))
        #expect(PollCreationSheet.hasChanges(PollDraft(question: "Pizza ?", answers: ["Oui", "Non", "Bof"]), from: existing))
    }

    @Test func theDialogNamesTheActions() {
        #expect(DiscardConfirmation.discardTitle == "Abandonner")
        #expect(DiscardConfirmation.keepTitle == "Continuer la saisie")
    }
}
