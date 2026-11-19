import CoreGraphics
import Foundation
@testable import SwiftHFR
import Testing

/// #1136 (operator 2026-11-18): the docked card grows with the reply up to the room the screen leaves, not to a fixed six lines;
/// past that the editor scrolls inside it. The room comes from the geometry (window, safe area, navigation bar, keyboard, the
/// strip of page kept visible), not from a line count.
struct ComposerCardGrowthTests {
    private static let line: CGFloat = 20
    private static let available: CGFloat = 600

    /// The buttons' row 70 pt, the control row 56 pt, one line 20 pt, and a screen that leaves a 600 pt card.
    private func layout(lines: CGFloat, available: CGFloat? = Self.available) -> ComposerCardLayout {
        ComposerCardLayout(top: 70, controls: 56, text: lines * Self.line, line: Self.line, availableHeight: available)
    }

    /// What the editor's text may take of the 600 pt card: all but the buttons, the controls, the gap under the card and the
    /// text view's own insets.
    private static var textRoom: CGFloat { available - 70 - 56 - FloatingSpacing.gap - ComposerCardLayout.editorInsets }

    @Test func theEditorGrowsLineByLineUpToTheRoomTheScreenLeaves() {
        #expect(layout(lines: 1).editorHeight == 2 * Self.line + ComposerCardLayout.editorInsets, "a short text keeps two lines")
        #expect(layout(lines: 6).editorHeight == 6 * Self.line + ComposerCardLayout.editorInsets)
        #expect(layout(lines: 12).editorHeight == 12 * Self.line + ComposerCardLayout.editorInsets, "past six lines it keeps growing")
        #expect(
            layout(lines: 40).editorHeight == Self.textRoom + ComposerCardLayout.editorInsets, "then the editor scrolls inside the card"
        )
    }

    @Test func theCardNeverTakesMoreThanTheRoom() {
        #expect(layout(lines: 40).cardHeight == Self.available)
        #expect(layout(lines: 12).cardHeight < Self.available)
    }

    @Test func beforeTheScreenIsMeasuredTheCapIsTodaysSixLines() {
        let unmeasured = layout(lines: 40, available: nil)
        #expect(unmeasured.editorHeight == 6 * Self.line + ComposerCardLayout.editorInsets)
    }

    @Test func aTightScreenNeverShrinksTheCapBelowSixLines() {
        #expect(layout(lines: 40, available: 200).editorHeight == 6 * Self.line + ComposerCardLayout.editorInsets)
    }

    /// Before the keyboard has shown there is no room (today's six lines); once it has, the room follows it up and down but a
    /// hidden keyboard keeps the last room, so the card does not rise over the page.
    @Test func theRoomFollowsTheKeyboardOnlyWhileItIsUp() {
        var keyboard = ComposerKeyboardRoom()
        #expect(keyboard.room(window: 874, topInset: 62, line: 20) == nil, "no keyboard yet: no room, a long draft stays at six lines")
        keyboard.keyboardChanged(height: 0)
        #expect(keyboard.room(window: 874, topInset: 62, line: 20) == nil, "a hidden keyboard is not a measure")
        keyboard.keyboardChanged(height: 336)
        let up = keyboard.room(window: 874, topInset: 62, line: 20)
        #expect(up == ComposerCardLayout.room(window: 874, topInset: 62, keyboard: 336, line: 20))
        keyboard.keyboardChanged(height: 0)
        #expect(keyboard.room(window: 874, topInset: 62, line: 20) == up, "the keyboard hides: the room stays")
        keyboard.keyboardChanged(height: 400)
        let higher = ComposerCardLayout.room(window: 874, topInset: 62, keyboard: 400, line: 20)
        #expect(keyboard.room(window: 874, topInset: 62, line: 20) == higher)
    }

    /// The window less the safe area, the navigation bar, the keyboard and a strip of the page's last message (three lines of the
    /// body font): an iPhone 18 Pro (402 × 874 pt, top inset 62 pt, keyboard 336 pt with its suggestion bar; illustrative inputs,
    /// to be replaced by a device measure on #893).
    @Test func theRoomIsTheScreenLessWhatMustStayVisible() {
        let room = ComposerCardLayout.room(window: 874, topInset: 62, keyboard: 336, line: 20)
        #expect(room == 874 - 62 - ComposerCardLayout.navigationBarHeight - 336 - ComposerCardLayout.pageStripLines * 20)
        #expect(ComposerCardLayout.room(window: 874, topInset: 62, keyboard: 0, line: 20) > room, "a hidden keyboard leaves more")
        #expect(ComposerCardLayout.room(window: 300, topInset: 62, keyboard: 336, line: 20) == 0, "never negative")
    }
}
