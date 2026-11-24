@testable import SwiftHFR
import Testing

/// #693: the one rule every screen without content follows (the lists, the profile, the reader).
struct ScreenLoadStateTests {
    @Test func aFailureWinsOverARunningLoad() {
        // A retry runs while `ContentLoader` keeps the error: the failure stays on screen until a load succeeds.
        #expect(ScreenLoadState(error: .offline, isLoading: true) == .failed(.offline))
        #expect(ScreenLoadState(error: .offline, isLoading: false) == .failed(.offline))
    }

    @Test func aRunningLoadShowsTheSpinner() {
        #expect(ScreenLoadState(error: nil, isLoading: true) == .loading)
    }

    @Test func aListThatIsNotLoadingShowsNothing() {
        #expect(ScreenLoadState(error: nil, isLoading: false) == .idle)
    }

    @Test func aScreenWaitingForItsFirstContentSpinsByDefault() {
        // The profile and the reader show the spinner until their first page, whatever their loader says.
        #expect(ScreenLoadState(error: nil) == .loading)
        #expect(ScreenLoadState(error: .timedOut) == .failed(.timedOut))
    }
}
