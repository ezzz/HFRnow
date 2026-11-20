import HFRModels
import HFRParsing
import SwiftUI

/// What the « Style des messages » preview shows (#1063): two sample messages, an odd and an even one, built by the reader's own
/// `TopicHTMLBuilder` so the preview cannot drift from `reader.css`. Sample content only: neutral pseudos, no image, no link, so
/// nothing is requested. The two styles differ by what `reader.css` says at `.style-modern` / `.style-classic`: the header tint
/// (3 % accent against 15 %) and where the text starts (`--indent`, under the pseudo, against the left margin). Messages have no
/// alternating band any more (#1210), so the sample text does not mention one.
enum StylePreviewContent {
    /// The page of the two sample messages.
    static let page = ReaderPage(
        topicID: nil, title: "Aperçu", currentPage: 1, maxPage: 1,
        messages: [
            message(1, author: "Exemple A", text: "Premier message d’exemple."),
            message(2, author: "Exemple B", text: "Second message d’exemple.")
        ]
    )

    private static func message(_ number: Int, author: String, text: String) -> ReaderMessage {
        ReaderMessage(
            numreponse: number, author: author, isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "01-01-2026 10:0\(number):00", editNote: nil, quotedByCount: nil,
            content: MessageContent(html: "<p>\(text)</p>")
        )
    }

    /// The preview's document for `style`: the reader's page with the chosen `style-*` class.
    static func html(style: ThemeStyle, token: Int) -> String {
        TopicHTMLBuilder.document(for: page, token: token, options: ReaderRenderOptions(style: style))
    }

    /// The sentence under the preview: what the chosen style changes, as `reader.css` draws it.
    static func sentence(for style: ThemeStyle) -> String {
        switch style {
        case .modern: "Moderne : texte aligné sous le pseudo, en-têtes à peine teintés."
        case .classic: "Classique : en-têtes teintés, texte à la marge."
        }
    }
}

/// A live, non-interactive preview of the message style under the picker, shown by the reader's web view (`ReaderWebView`: the
/// colour theme, density and text size come from the environment as in the reader). Hidden from VoiceOver: the sentence under it
/// carries the meaning.
struct StylePreview: View {
    let style: ThemeStyle
    /// The web view is made when the settings screen shows the preview, not before.
    @State private var controller: ReaderWebController?
    @State private var document: ReaderDocument?
    @State private var token = 0
    @ScaledMetric(relativeTo: .body) private var height = 220.0
    /// The in-app text size (70 to 130 %) scales the page's text too: the frame follows, or the second message would be cut.
    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let controller {
                    ReaderWebView(controller: controller, document: document, scrollRequest: nil)
                } else {
                    Color.clear
                }
            }
            .frame(height: textScale.scaled(height))
            .clipShape(.rect(cornerRadius: 8))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            Text(StylePreviewContent.sentence(for: style))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear { makeController() }
        .onChange(of: style, initial: true) { _, style in show(style) }
    }

    private func makeController() {
        guard controller == nil else { return }
        // No image in the sample, so the fetcher is never asked and third-party images stay off.
        let controller = ReaderWebController(imageFetcher: ReaderImageFetcher(), autoLoadsThirdPartyImages: { false })
        controller.webView.scrollView.isScrollEnabled = false
        self.controller = controller
    }

    private func show(_ style: ThemeStyle) {
        token += 1
        document = ReaderDocument(
            token: token, html: StylePreviewContent.html(style: style, token: token), anchor: nil, keepsScrollPosition: false
        )
    }
}
