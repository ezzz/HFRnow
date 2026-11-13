import CoreGraphics
@testable import SwiftHFR
import Testing

/// The composer's chrome on an iPhone (#854, operator 2026-11-12, reference: the Claude app's composer): the control row inside
/// the text card's bottom edge, close, drafts and send as small floating glass buttons; an iPad keeps its bar and row.
/// On the main actor: `ComposerHeader` is a view, its rules are main-actor isolated.
@MainActor
struct ComposerChromeTests {
    @Test(arguments: [true, false])
    func onlyAnIPhoneHasTheControlsInTheCardAndTheFloatingButtons(isPhone: Bool) {
        let chrome = ComposerChrome(isPhone: isPhone)
        #expect(chrome.controlsInCard == isPhone)
        #expect(chrome.headerFloats == isPhone)
    }

    /// The text card holds the chips, the editor and the controls: the text grows the card, never over the controls.
    @Test func theTextCardHoldsTheEditorAndTheControlsUnderIt() {
        var layout = ComposerCardLayout(top: 40, controls: 56, text: 60, line: 20)
        #expect(layout.textCardHeight == CGFloat(76 + 56))
        layout.chips = 66
        #expect(layout.textCardHeight == CGFloat(66 + 76 + 56))
        // Past six lines the editor scrolls: the card stops at its cap with the controls still inside it.
        layout.text = 500
        #expect(layout.textCardHeight == CGFloat(66 + (6 * 20 + 16) + 56))
    }

    @Test func theSheetIsTheFloatingButtonsTheTextCardAndItsGaps() {
        let layout = ComposerCardLayout(top: 40, chips: 66, controls: 56, text: 60, line: 20)
        #expect(layout.cardHeight == 40 + layout.textCardHeight + 2 * ComposerCardLayout.gap)
    }

    /// At Dynamic Type XL the control row takes two lines (`ViewThatFits`): the card counts both and the text keeps its two.
    @Test func twoControlLinesAtXLStillLeaveTheTextItsTwoLines() {
        let cell = ComposerBarMetrics(density: .regular, scale: TextScale(percent: 100), dynamicType: 19.0 / 17.0).cellSize
        let oneLine = ComposerCardLayout(top: 40, controls: cell, text: 0, line: 23)
        let twoLines = ComposerCardLayout(top: 40, controls: 2 * cell + 8, text: 0, line: 23)
        #expect(twoLines.editorHeight == oneLine.editorHeight)
        #expect(twoLines.editorHeight == 2 * 23 + ComposerCardLayout.editorInsets)
        #expect(abs(twoLines.textCardHeight - oneLine.textCardHeight - (cell + 8)) < 0.001)
    }

    @Test func sendIsGreyedWithNothingToSendProminentWithTextAndASpinnerWhileSending() {
        let empty = ComposerHeader.SendState(isSending: false, canSend: false)
        #expect(!empty.isEnabled)
        #expect(!empty.isProminent)
        #expect(!empty.showsSpinner)
        #expect(empty.label == "Envoyer")
        let ready = ComposerHeader.SendState(isSending: false, canSend: true)
        #expect(ready.isEnabled)
        #expect(ready.isProminent)
        #expect(ready.label == "Envoyer")
        let sending = ComposerHeader.SendState(isSending: true, canSend: false)
        #expect(sending.showsSpinner)
        #expect(!sending.isEnabled)
        #expect(sending.label == "Envoi en cours")
    }

    @Test func closeAndDraftsWaitWhileSending() {
        #expect(ComposerHeader.closeIsEnabled(isSending: false))
        #expect(!ComposerHeader.closeIsEnabled(isSending: true))
        let drafts = ComposerHeader.Drafts(hasDrafts: true, isEnabled: true) {}
        let reading = ComposerHeader.Drafts(hasDrafts: false, isEnabled: false) {}
        let idle = ComposerHeader.draftsAreEnabled(drafts, isSending: false)
        let sending = ComposerHeader.draftsAreEnabled(drafts, isSending: true)
        let unread = ComposerHeader.draftsAreEnabled(reading, isSending: false)
        #expect(idle)
        #expect(!sending)
        #expect(!unread)
    }
}
