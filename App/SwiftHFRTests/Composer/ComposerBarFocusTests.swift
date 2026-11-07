@testable import SwiftHFR
import Testing

/// The formatting bar's focus rule (#599): off while another field has focus, and a bar action never moves focus off it.
struct ComposerBarFocusTests {
    @Test(arguments: [ComposerField.recipient, .subject])
    func theBarIsOffWhileAnotherFieldHasFocus(field: ComposerField) {
        #expect(!ComposerBarFocus.allowsBar(focused: field))
    }

    @Test
    func theBarIsOnWhileTheTextHasFocusOrNothingHas() {
        #expect(ComposerBarFocus.allowsBar(focused: .text))
        // A reply whose keyboard went away (a sheet closed without inserting) keeps a working bar, as before #599.
        #expect(ComposerBarFocus.allowsBar(focused: nil))
    }

    @Test(arguments: [ComposerField.recipient, .subject])
    func aBarActionNeverMovesFocusOffAnotherField(field: ComposerField) {
        #expect(ComposerBarFocus.focus(afterBarActionFrom: field) == field)
    }

    @Test
    func aBarActionKeepsOrBringsFocusToTheText() {
        #expect(ComposerBarFocus.focus(afterBarActionFrom: .text) == .text)
        #expect(ComposerBarFocus.focus(afterBarActionFrom: nil) == .text)
    }
}
