@testable import SwiftHFR
import Testing

/// The words of the « Navigateur par défaut » bubble (#1071), written from what `ReaderLinkAction` does.
struct DefaultBrowserMessagesTests {
    @Test func theSwitchKeepsItsTitle() {
        #expect(DefaultBrowserMessages.title == "Navigateur par défaut")
    }

    /// Both positions, then what the switch never changes: the reader keeps the forum's topics, MPs and profiles.
    @Test func theExplanationDescribesBothPositionsAndTheReaderException() {
        let lines = DefaultBrowserMessages.explanation
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { !$0.isEmpty })
        #expect(lines[0].hasPrefix("Activé") && lines[0].contains("hors de l’app"))
        #expect(lines[1].hasPrefix("Désactivé") && lines[1].contains("à l’intérieur de l’app"))
        #expect(lines[2].contains("lecteur") && lines[2].contains("profils"))
    }

    /// Pins the wording of the button's label. It does not prove that the row draws the button, nor that the old line
    /// « Désactivé : navigateur intégré » is gone: both are for the device check (no view-inspection tool).
    @Test func theInfoButtonLabelIsThePinnedWording() {
        #expect(DefaultBrowserMessages.infoLabel == "À propos du navigateur par défaut")
    }
}
