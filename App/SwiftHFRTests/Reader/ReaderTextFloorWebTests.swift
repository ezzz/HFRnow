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
                        <td><b class="s1">cite<sub>q</sub> :</b><p>cité</p></td></tr></table></div>
                        <table class="code"><tr><td><b class="s1">Code<sub>c</sub> :</b><br />let x = 1</td></tr></table>
                        <table class="fixed"><tr><td>H<sub>2</sub>O<sub>2<sub>n</sub></sub></td></tr></table>
                        <p>texte H<sub>2</sub>O x<sup>2</sup></p>
                        <p>y<sup>2<sup>n</sup></sup></p>
                        """,
                    signatureHTML: """
                        <br />ma signature <button type="button" class="image-tap">Afficher l'image</button>
                        <a class="image-link" href="https://example.invalid/i.png">https://example.invalid/i.png</a>
                        <table class="code"><tr><td><b class="s1">Code :</b><br />x</td></tr></table> H<sub>2</sub>O
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

    /// One probed element: its name, its selector and its size at 100 % over the root's.
    private struct ProbedElement {
        let name: String
        let selector: String
        let ratio: Double

        init(_ name: String, _ selector: String, _ ratio: Double) {
            self.name = name
            self.selector = selector
            self.ratio = ratio
        }
    }

    /// Name, selector (`::after` for a pseudo-element) and the size at 100 % over the root's: what dev-swift computed before
    /// #1237, from each element's real nesting. The video button and card are children of the article, so they follow the
    /// body, not the message text; the signature's children are one 0.85 step further than the message text's.
    private let elements: [ProbedElement] = [
        ProbedElement("content", ".content", 15 / 17.0),
        ProbedElement("date", ".date", 0.85),
        ProbedElement("quote header", "table.oldcitation b.s1", 0.85 * 15 / 17),
        ProbedElement("bubble", ".quoted-bubble", 0.765),
        ProbedElement("badge", ".separator1::after", 0.7),
        ProbedElement("signature", ".signature", 0.85 * 15 / 17),
        ProbedElement("trailer", ".trailer", 0.85),
        ProbedElement("video button", ".videos button.video", 0.85),
        ProbedElement("video card", ".videolinks .video-pill", 0.85),
        ProbedElement("code header", "table.code b.s1", 0.85 * 0.85 * 15 / 17),
        ProbedElement("signature image button", ".signature button.image-tap", 0.85 * 0.85 * 15 / 17),
        ProbedElement("signature image link", ".signature .image-link", 0.85 * 0.85 * 15 / 17),
        ProbedElement("sub", ".content > p sub", 15 / 17.0 / 1.2),
        ProbedElement("sup", ".content sup", 15 / 17.0 / 1.2),
        ProbedElement("sub in a code block", ".content table.fixed sub", 0.85 * 15 / 17 / 1.2),
        ProbedElement("sub in the signature", ".signature > sub", 0.85 * 15 / 17 / 1.2),
        ProbedElement("sub in a quote header", "table.oldcitation b.s1 sub", 0.85 * 15 / 17 / 1.2),
        ProbedElement("sub in a code header", "table.code b.s1 sub", 0.85 * 0.85 * 15 / 17 / 1.2),
        ProbedElement("nested sup", ".content > p sup sup", 15 / 17.0 / 1.44),
        ProbedElement("nested sub in a code block", ".content table.fixed sub sub", 0.85 * 15 / 17 / 1.44),
        ProbedElement("code header in the signature", ".signature table.code b.s1", 0.85 * 0.85 * 0.85 * 15 / 17)
    ]

    /// The computed font size (px) of each element, then the root's. The video nodes are added where the builder puts them
    /// (children of the article, after the message text).
    private func probe(rootPixels: Int?) -> String {
        let list = elements.map { element in
            let selector = element.selector.replacingOccurrences(of: "::after", with: "")
            return "['\(selector)', \(element.selector.hasSuffix("::after"))]"
        }
        return """
            \(rootPixels.map { "document.documentElement.style.fontSize = '\($0)px';" } ?? "")
            const article = document.querySelector('article.message');
            article.insertAdjacentHTML('beforeend', '<div class="videos"><button type="button" class="video">Video</button></div>'
                + '<div class="videolinks"><a class="video-card" href="https://example.invalid/v">'
                + '<span class="video-pill">YouTube</span></a></div>');
            const px = (selector, pseudo) => parseFloat(
                getComputedStyle(document.querySelector(selector), pseudo ? '::after' : null).fontSize);
            const sizes = [\(list.joined(separator: ", "))].map(([selector, pseudo]) => px(selector, pseudo));
            sizes.push(parseFloat(getComputedStyle(document.documentElement).fontSize));
            return JSON.stringify(sizes);
            """
    }

    /// `rootPixels` stands for a Dynamic Type size (the host stays at its default in a test): 14 is xSmall's body.
    private func sizes(percent: Int, rootPixels: Int?, token: Int) async -> [Double] {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.textScale = TextScale(percent: percent)
        controller.show(floorDocument(token: token))
        guard await until({ recorder.ready == [token] }) else { return [] }
        let json = (try? await evaluate(probe(rootPixels: rootPixels), in: controller)) as? String ?? "[]"
        return (try? JSONDecoder().decode([Double].self, from: Data(json.utf8))) ?? []
    }

    /// Default Dynamic Type, and xSmall (a context's 100 % size is then under 11 px, which a floored parent must not leak into
    /// its children).
    private let roots: [Int?] = [nil, 14]

    /// The rule of `TextScale.pointSize`: below 100 % a size is at least `min(its size at 100 %, 11)`, and never above its size at
    /// 100 %. A text already under 11 px at 100 % keeps that size (no jump up to 11).
    @Test func at70PercentEveryTextHoldsTheFloorAndNeverGrows() async {
        for (index, root) in roots.enumerated() {
            let seen = await sizes(percent: 70, rootPixels: root, token: 10 + index)
            #expect(seen.count == elements.count + 1, "seen: \(seen)")
            guard seen.count == elements.count + 1 else { continue }
            let rootSize = seen[elements.count]
            for (element, size) in zip(elements, seen) {
                let unscaled = element.ratio * rootSize
                let label = "\(element.name) computes to \(size) px at 70 %, root \(rootSize)"
                #expect(size >= min(unscaled, 11) - 0.01, "\(label): under the floor")
                #expect(size <= unscaled + 0.01, "\(label): above its \(unscaled) px at 100 %")
            }
        }
    }

    @Test func at100AndAboveTheSizesAreTheUnscaledOnesTimesThePercentage() async {
        var token = 20
        for root in roots {
            for percent in [100, 130] {
                token += 1
                let seen = await sizes(percent: percent, rootPixels: root, token: token)
                guard seen.count == elements.count + 1 else {
                    Issue.record("seen: \(seen)")
                    continue
                }
                let rootSize = seen[elements.count], scale = Double(percent) / 100
                for (element, size) in zip(elements, seen) {
                    let expected = element.ratio * rootSize * scale
                    #expect(abs(size - expected) < 0.05, "\(element.name) at \(percent) %, root \(rootSize): \(size), expected \(expected)")
                }
            }
        }
    }
}
