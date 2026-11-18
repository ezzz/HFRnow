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
        #expect(StylePreviewContent.sentence(for: .modern) == "Moderne : texte aligné sous le pseudo, en-têtes à peine teintés.")
        #expect(StylePreviewContent.sentence(for: .classic) == "Classique : en-têtes teintés, texte à la marge.")
    }

    /// `reader.css` gives even messages their own band in both styles (`article.message:nth-of-type(even)`), so no sentence may
    /// present the alternation as what a style changes; the two sentences name different things.
    @Test func noSentenceClaimsTheAlternationOrTheAvatarIndent() {
        let sentences = ThemeStyle.allCases.map(StylePreviewContent.sentence(for:))
        #expect(Set(sentences).count == ThemeStyle.allCases.count)
        for sentence in sentences {
            #expect(!sentence.contains("altern"))
            #expect(!sentence.contains("avatar"))
        }
    }
}
