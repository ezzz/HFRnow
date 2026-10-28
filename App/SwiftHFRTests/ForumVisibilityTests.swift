import HFRModels
@testable import SwiftHFR
import Testing

struct ForumVisibilityTests {
    private let apple = ForumCategory(categoryID: .forum(25), title: "Apple", path: "/hfr/apple/liste_sujet-1.htm")
    private let discussions = ForumCategory(categoryID: .forum(13), title: "Discussions", path: "/hfr/Discussions/liste_sujet-1.htm")

    @Test func hidesTheAppleCategoryWhenLoggedOut() {
        let visible = ForumVisibility().visible([discussions, apple], isLoggedIn: false, accountName: nil)
        #expect(visible == [discussions])
    }

    @Test func hidesItForTheReviewAccountWhateverTheCase() {
        let visible = ForumVisibility().visible([apple, discussions], isLoggedIn: true, accountName: "AppleReview")
        #expect(visible == [discussions])
    }

    @Test func showsItToAnotherLoggedInAccount() {
        let visible = ForumVisibility().visible([apple, discussions], isLoggedIn: true, accountName: "someone")
        #expect(visible == [apple, discussions])
    }

    @Test func aLoggedInSessionWithoutKnownNameIsTreatedAsLoggedOut() {
        let visible = ForumVisibility().visible([apple, discussions], isLoggedIn: true, accountName: nil)
        #expect(visible == [discussions])
    }

    @Test func theReviewAccountNameIsConfiguration() {
        let policy = ForumVisibility(reviewAccountName: "reviewer")
        #expect(policy.visible([apple], isLoggedIn: true, accountName: "applereview") == [apple])
        #expect(policy.visible([apple], isLoggedIn: true, accountName: "reviewer").isEmpty)
    }

    @Test func recognisesTheCategoryByPathWhenTheIDIsMissing() {
        let withoutID = ForumCategory(title: "Apple", path: "/hfr/apple/liste_sujet-1.htm")
        #expect(ForumVisibility().visible([withoutID], isLoggedIn: false, accountName: nil).isEmpty)
    }
}
