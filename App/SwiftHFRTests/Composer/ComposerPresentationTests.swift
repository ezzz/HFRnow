import Foundation
import SwiftUI
@testable import SwiftHFR
import Testing

/// Where the composer opens (#653): at partial height on an iPhone, whatever it writes (a reply, an edit, a new topic, a new
/// private message: operator, 2026-11-10), so the page it was opened from stays visible above it; full height on an iPad and
/// in compact height, where the system shows a sheet full anyway and no toggle claims otherwise.
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

    @Test func thePartialHeightLeavesTheTopThirdToThePage() {
        // The system lifts the sheet above the keyboard: a third of the room, the keyboard below it, the page above.
        #expect(ComposerHeight.partialHeight(available: 900) == 300)
        // A short room (landscape, a small phone) still fits two lines of text and the control row, never more than the room.
        #expect(ComposerHeight.partialHeight(available: 450) == 220)
        #expect(ComposerHeight.partialHeight(available: 200) == 200)
    }

    @Test func aNewTopicOrANewMessageKeepsRoomForItsFieldsAboveTheText() {
        #expect(ComposerHeight.fieldRows(hasSubject: false, hasSecondField: false) == 0)
        #expect(ComposerHeight.fieldRows(hasSubject: true, hasSecondField: false) == 1) // the edit of a first message
        #expect(ComposerHeight.fieldRows(hasSubject: true, hasSecondField: true) == 2) // recipient or sub-category, subject
        // Two field lines on top of the minimum: they never squeeze the text below two lines.
        #expect(ComposerHeight.partialHeight(available: 750, fieldRows: 2, rowHeight: 44) == 308)
        #expect(ComposerHeight.partialHeight(available: 750, fieldRows: 2, rowHeight: 60) == 340)
        // A tall room: the third already holds them.
        #expect(ComposerHeight.partialHeight(available: 1_200, fieldRows: 2, rowHeight: 44) == 400)
        #expect(ComposerHeight.partialHeight(available: 280, fieldRows: 2, rowHeight: 44) == 280)
    }

    @Test func eachHeightIsTheSheetsOnlyDetentAndTheFullOneIsLarge() {
        #expect(ComposerHeight.full.detent(fieldRows: 2) == .large)
        #expect(ComposerHeight.partial.detent(fieldRows: 0) == .custom(PartialComposerDetent.self))
        #expect(ComposerHeight.partial.detent(fieldRows: 1) == .custom(PartialComposerDetentOneField.self))
        #expect(ComposerHeight.partial.detent(fieldRows: 2) == .custom(PartialComposerDetentTwoFields.self))
    }
}
