@testable import SwiftHFR
import Testing

/// The words of the « Filtrer les posts » bubble (#1072), written from `FilteredPostsCriteria.keeps`.
struct FilteredPostsMessagesTests {
    /// Every rule of the filter, and the role of « Minimum de citations ».
    @Test func theExplanationNamesTheRulesAndTheMinimumsRole() {
        let text = FilteredPostsMessages.explanation.joined(separator: " ")
        #expect(FilteredPostsMessages.explanation.count == 2)
        #expect(FilteredPostsMessages.explanation.allSatisfy { !$0.isEmpty })
        for part in ["cités au moins N fois", "les vôtres", "vous citent", "vous mentionnent", "liste blanche"] {
            #expect(text.contains(part), "\(part)")
        }
        #expect(FilteredPostsMessages.explanation[1].contains("Minimum de citations"))
        #expect(FilteredPostsMessages.explanation[1].contains("moins il reste de messages"))
    }

    /// Pins the wording of the button's label. It does not prove that the row draws the button: that is for the device check.
    @Test func theInfoButtonLabelIsThePinnedWording() {
        #expect(FilteredPostsMessages.infoLabel == "À propos du filtre des posts")
    }
}
