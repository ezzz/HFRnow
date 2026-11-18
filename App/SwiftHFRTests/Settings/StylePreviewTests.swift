import HFRModels
@testable import SwiftHFR
import Testing

/// The « Style des messages » preview of Réglages (#1063): the reader's own document with sample messages.
struct StylePreviewTests {
    @Test(arguments: [(ThemeStyle.modern, "style-modern", "style-classic"), (.classic, "style-classic", "style-modern")])
    func theDocumentCarriesTheSelectedStyleClass(style: ThemeStyle, expected: String, other: String) {
        let html = StylePreviewContent.html(style: style, token: 1)
        #expect(html.contains("<body class=\"nosig \(expected)\">"))
        #expect(!html.contains(other))
    }

    @Test func theDocumentHasTheTwoSampleMessagesAndNoRealMember() {
        let html = StylePreviewContent.html(style: .classic, token: 1)
        #expect(html.components(separatedBy: "<article ").count - 1 == 2)
        for part in ["Exemple A", "Exemple B", "Premier message d’exemple.", "Second message d’exemple"] {
            #expect(html.contains(part), "\(part)")
        }
        #expect(StylePreviewContent.page.messages.map(\.author) == ["Exemple A", "Exemple B"])
    }

    /// Only the reader's own scheme appears: the sample asks for no network, no image and carries no link.
    @Test func theDocumentNamesNoNetworkURL() {
        for style in ThemeStyle.allCases {
            let html = StylePreviewContent.html(style: style, token: 1)
            #expect(!html.contains("http:"))
            #expect(!html.contains("https:"))
            #expect(!html.contains("<img"))
            #expect(!html.contains("<a "))
        }
    }

    @Test func theSentenceNamesWhatEachStyleChanges() {
        #expect(StylePreviewContent.sentence(for: .modern) == "Moderne : texte aligné sous l’avatar, en-têtes discrets.")
        #expect(StylePreviewContent.sentence(for: .classic) == "Classique : en-têtes colorés et alternés, texte à la marge.")
    }
}
