@testable import SwiftHFR
import Testing

/// #1176 (HIG › Sheets: one sheet at a time): the login form pushed inside the Comptes sheet.
struct LoginPresentationTests {
    @Test func aSheetBringsItsOwnStackAndItsCancelButton() {
        #expect(LoginView.Presentation.sheet.wrapsInNavigationStack)
        #expect(LoginView.Presentation.sheet.offersCancelButton)
    }

    @Test func aPushedFormUsesTheStackItWasPushedOnAndTheBackButton() {
        // A nested stack would draw two navigation bars; « Annuler » would be a second way back next to the system one.
        #expect(!LoginView.Presentation.pushed.wrapsInNavigationStack)
        #expect(!LoginView.Presentation.pushed.offersCancelButton)
    }

    /// `navigationDestination(item:)` needs a hashable item: two targets are one destination only when they are equal.
    @Test func loginTargetsAreHashableByTheirAccount() {
        let one = LoginTarget.existing(id: "a", displayName: "A")
        #expect(Set([one, .existing(id: "a", displayName: "A"), .newAccount, .newAccount]).count == 2)
    }
}
