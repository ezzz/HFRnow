import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// #1237: below 100 % no reader text computes under 11 px (the floor of `TextScale.pointSize`, #1157), and 100 % and above
/// are unchanged. Legacy never goes below 100 % (`Common.swift:314-322` @ 87fe0d1c), so the floor is SwiftHFR's own.
@MainActor
@Suite(.serialized)
struct ReaderTextFloorWebTests: ReaderWebTesting {
    private func floorDocument(token: Int) -> ReaderDocument {
        func message(_ number: Int, quoted: Int?) -> ReaderMessage {
            ReaderMessage(
                numreponse: number, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "27-10-2026 10:00:00", editNote: "Message édité", quotedByCount: quoted,
                content: MessageContent(
                    html: """
                        <div class="container"><table class="oldcitation"><tr class="none">
                        <td><b class="s1">cite :</b><p>cité</p></td></tr></table></div>
                        <table class="code"><tr><td><b class="s1">Code :</b><br />let x = 1</td></tr></table>
                        <p>texte H<sub>2</sub>O x<sup>2</sup></p>
                        """,
                    signatureHTML: """
                        <br />ma signature <button type="button" class="image-tap">Afficher l'image</button>
                        <a class="image-link" href="https://example.invalid/i.png">https://example.invalid/i.png</a>
                        """
                )
            )
        }
        let page = ReaderPage(
            topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1,
            messages: [message(1, quoted: 3), message(2, quoted: nil)]
        )
        let options = ReaderRenderOptions(showsSignatures: true)
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token, options: options, separatorAfter: 1),
            anchor: nil, keepsScrollPosition: false
        )
    }

    /// Name, selector (`::after` for a pseudo-element) and the size at 100 % over the root's: what dev-swift computed before
    /// #1237, from each element's real nesting. The video button and card are children of the article, so they follow the
    /// body, not the message text; the signature's children are one 0.85 step further than the message text's.
    private let elements: [(name: String, selector: String, ratio: Double)] = [
        ("content", ".content", 15 / 17.0),
        ("date", ".date", 0.85),
        ("quote header", "table.oldcitation b.s1", 0.85 * 15 / 17),
        ("bubble", ".quoted-bubble", 0.765),
        ("badge", ".separator1::after", 0.7),
        ("signature", ".signature", 0.85 * 15 / 17),
        ("trailer", ".trailer", 0.85),
        ("video button", ".videos button.video", 0.85),
        ("video card", ".videolinks .video-pill", 0.85),
        ("code header", "table.code b.s1", 0.85 * 0.85 * 15 / 17),
        ("signature image button", ".signature button.image-tap", 0.85 * 0.85 * 15 / 17),
        ("signature image link", ".signature .image-link", 0.85 * 0.85 * 15 / 17),
        ("sub", ".content sub", 15 / 17.0 / 1.2),
        ("sup", ".content sup", 15 / 17.0 / 1.2)
    ]

    /// The computed font size (px) of each element, then the root's. The video nodes are added where the builder puts them
    /// (children of the article, after the message text).
    private var probe: String {
        let list = elements.map { element in
            let selector = element.selector.replacingOccurrences(of: "::after", with: "")
            return "['\(selector)', \(element.selector.hasSuffix("::after"))]"
        }
        return """
            const article = document.querySelector('article.message');
            article.insertAdjacentHTML('beforeend', '<div class="videos"><button type="button" class="video">Video</button></div>'
                + '<div class="videolinks"><a class="video-card" href="https://example.invalid/v"><span class="video-pill">YouTube</span></a></div>');
            const px = (selector, pseudo) => parseFloat(getComputedStyle(document.querySelector(selector), pseudo ? '::after' : null).fontSize);
            const sizes = [\(list.joined(separator: ", "))].map(([selector, pseudo]) => px(selector, pseudo));
            sizes.push(parseFloat(getComputedStyle(document.documentElement).fontSize));
            return JSON.stringify(sizes);
            """
    }

    private func sizes(percent: Int, token: Int) async -> [Double] {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.textScale = TextScale(percent: percent)
        controller.show(floorDocument(token: token))
        guard await until({ recorder.ready == [token] }) else { return [] }
        let json = (try? await evaluate(probe, in: controller)) as? String ?? "[]"
        return (try? JSONDecoder().decode([Double].self, from: Data(json.utf8))) ?? []
    }

    @Test func at70PercentEveryTextIsAtLeast11Px() async {
        let seen = await sizes(percent: 70, token: 1)
        #expect(seen.count == elements.count + 1, "seen: \(seen)")
        for (element, size) in zip(elements, seen) {
            #expect(size >= 10.99, "\(element.name) computes to \(size) px at 70 %")
        }
    }

    @Test func at100AndAboveTheSizesAreTheUnscaledOnesTimesThePercentage() async {
        for (percent, token) in [(100, 2), (130, 3)] {
            let seen = await sizes(percent: percent, token: token)
            guard seen.count == elements.count + 1 else {
                Issue.record("seen: \(seen)")
                continue
            }
            let root = seen[elements.count], scale = Double(percent) / 100
            for (element, size) in zip(elements, seen) {
                let expected = element.ratio * root * scale
                #expect(abs(size - expected) < 0.05, "\(element.name) at \(percent) %: \(size), expected \(expected)")
            }
        }
    }
}
