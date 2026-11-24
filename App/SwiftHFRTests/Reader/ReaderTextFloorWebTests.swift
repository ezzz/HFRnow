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
                        <td><b class="s1">cite :</b><p>cité</p></td></tr></table></div><p>texte</p>
                        """,
                    signatureHTML: "<br />ma signature"
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

    private let names = ["content", "date", "quote header", "bubble", "badge", "signature", "trailer"]

    /// The computed font sizes (px) of the body text, date, quote header, quoted bubble, "Nouveau" badge, signature and
    /// trailer, then the root's.
    private let probe = """
        const px = (el, pseudo) => parseFloat(getComputedStyle(el, pseudo).fontSize);
        const q = (s) => document.querySelector(s);
        return JSON.stringify([px(q('.content')), px(q('.date')), px(q('b.s1')), px(q('.quoted-bubble')),
                               px(q('.separator1'), '::after'), px(q('.signature')), px(q('.trailer')),
                               px(document.documentElement)]);
        """

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
        #expect(seen.count == 8, "seen: \(seen)")
        for (name, size) in zip(names, seen.dropLast()) {
            #expect(size >= 10.99, "\(name) computes to \(size) px at 70 %")
        }
    }

    @Test func at100AndAboveTheSizesAreTheUnscaledOnesTimesThePercentage() async {
        for (percent, token) in [(100, 2), (130, 3)] {
            let seen = await sizes(percent: percent, token: token)
            guard seen.count == 8 else {
                Issue.record("seen: \(seen)")
                continue
            }
            let root = seen[7], scale = Double(percent) / 100
            let ratios = [15 / 17.0, 0.85, 0.85 * 15 / 17, 0.765, 0.7, 0.85 * 15 / 17, 0.85]
            for (index, size) in seen.dropLast().enumerated() {
                let expected = ratios[index] * root * scale
                #expect(abs(size - expected) < 0.05, "\(names[index]) at \(percent) %: \(size), expected \(expected)")
            }
        }
    }
}
