import Foundation
import SwiftUI
@testable import SwiftHFR
import Testing

/// Where the composer opens (#653): at partial height on an iPhone, whatever it writes (a reply, an edit, a new topic, a new
/// private message: operator, 2026-11-10), a card docked on the keyboard so the page it was opened from stays visible above it;
/// full height on an iPad and in compact height, where the system shows a sheet full anyway and no toggle claims otherwise.
struct ComposerPresentationTests {
    @Test(arguments: [true, false])
    func everyComposerOpensAtPartialHeightOnlyOnAnIPhone(isPhone: Bool) {
        let expected: ComposerHeight = isPhone ? .partial : .full
        #expect(ComposerHeight.shown(chosen: nil, isPhone: isPhone, verticalSizeClass: .regular) == expected)
        #expect(ComposerHeight.offersToggle(isPhone: isPhone, verticalSizeClass: .regular) == isPhone)
    }

    @Test func inCompactHeightTheSheetIsFullAndOffersNoToggle() {
        // iPhone in landscape: the system ignores the custom detent, so "Plein écran" would sit on a full sheet.
        #expect(!ComposerHeight.offersToggle(isPhone: true, verticalSizeClass: .compact))
        #expect(ComposerHeight.shown(chosen: nil, isPhone: true, verticalSizeClass: .compact) == .full)
        #expect(ComposerHeight.shown(chosen: .partial, isPhone: true, verticalSizeClass: .compact) == .full)
        // Back in portrait, the choice made before the rotation holds.
        #expect(ComposerHeight.shown(chosen: .full, isPhone: true, verticalSizeClass: .regular) == .full)
    }

    @Test func atAnAccessibilityTextSizeTheComposerOpensFullWithItsToggle() {
        // AX sizes: the control row takes two tall rows, a third of the screen leaves no line for the text.
        #expect(ComposerHeight.shown(chosen: nil, isPhone: true, verticalSizeClass: .regular, largeText: true) == .full)
        #expect(ComposerHeight.offersToggle(isPhone: true, verticalSizeClass: .regular))
        #expect(ComposerHeight.shown(chosen: .partial, isPhone: true, verticalSizeClass: .regular, largeText: true) == .partial)
        #expect(ComposerHeight.shown(chosen: nil, isPhone: true, verticalSizeClass: .regular, largeText: false) == .partial)
    }

    @Test func theToggleGoesBothWays() {
        #expect(ComposerHeight.partial.toggled == .full)
        #expect(ComposerHeight.full.toggled == .partial)
        #expect(ComposerHeight.shown(chosen: .full, isPhone: true, verticalSizeClass: .regular) == .full)
        #expect(ComposerHeight.shown(chosen: .partial, isPhone: true, verticalSizeClass: .regular) == .partial)
    }

    /// The docked card (operator reference of 2026-11-10): as tall as its text, from two lines up to six, then the editor scrolls.
    @Test func theCardGrowsWithItsTextFromTwoToSixLinesThenTheEditorScrolls() {
        var layout = ComposerCardLayout(top: 70, controls: 56, text: 0, line: 20)
        #expect(layout.editorHeight == CGFloat(2 * 20 + 16), "an empty text keeps two lines and the text view's insets")
        layout.text = 60
        #expect(layout.editorHeight == CGFloat(60 + 16))
        layout.text = 120
        #expect(layout.editorHeight == CGFloat(120 + 16))
        layout.text = 500
        #expect(layout.editorHeight == CGFloat(6 * 20 + 16), "past six lines the card stops growing")
        // A larger text size makes each line, so the cap, taller.
        layout.line = 30
        #expect(layout.editorHeight == CGFloat(6 * 30 + 16))
    }

    @Test func theCardIsEveryPartAsLaidOut() {
        var layout = ComposerCardLayout(top: 70, controls: 56, text: 60, line: 20)
        let gaps = 2 * ComposerCardLayout.gap
        #expect(layout.cardHeight == 70 + 76 + gaps + 56)
        layout.chips = 66
        #expect(layout.cardHeight == 70 + 66 + 76 + gaps + 56)
        // New lines grow the card, one line at a time.
        layout.text = 80
        #expect(layout.cardHeight == 70 + 66 + 96 + gaps + 56)
    }

    @Test func beforeItsPartsAreMeasuredTheCardHasItsFallbackHeight() {
        #expect(ComposerCardLayout().cardHeight == ComposerCardLayout.fallbackHeight)
        #expect(ComposerCardLayout(top: 70, controls: 0, text: 20, line: 20).cardHeight == ComposerCardLayout.fallbackHeight)
    }

    @Test func aTrailingNewLineOrAnEmptyTextIsMeasuredAsALine() {
        #expect(ComposerEditorCard.measured("") == " ")
        #expect(ComposerEditorCard.measured("a\n") == "a\n ")
        #expect(ComposerEditorCard.measured("a") == "a")
    }

    @Test func eachHeightIsTheSheetsOnlyDetentAndTheFullOneIsLarge() {
        #expect(ComposerHeight.full.detent(cardHeight: 300) == .large)
        #expect(ComposerHeight.partial.detent(cardHeight: 300) == .height(300))
    }

    /// #853 device-test variant: partial height offers the card's detent and a larger one (the keyboard-lifted sheet stays within
    /// the undimmed bound); full height offers `.large` only.
    @Test func partialHeightOffersALargerDetentAndFullOnlyLarge() {
        #expect(ComposerHeight.partial.detents(cardHeight: 300) == [.height(300), .large])
        #expect(ComposerHeight.full.detents(cardHeight: 300) == [.large])
        #expect(ComposerHeight.partial.undimmedBound == .large)
    }
}
