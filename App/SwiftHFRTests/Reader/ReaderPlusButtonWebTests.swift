import Foundation
import HFRModels
@testable import SwiftHFR
import Testing
import UIKit

/// #1068 in the real reader: the message "+" is drawn at legacy's size, a 16 px cross with 2 px strokes
/// (`plus-tinted@2x.png`, measured: 64 px, an opaque 16 pt cross with 4 px strokes; `style-liste-dark.css:590-595` @ 87fe0d1c), in a tap
/// box of at least 32 px (44 px here), without growing the header, and it does not follow the reader's text size (legacy's does not).
@MainActor
@Suite(.serialized)
struct ReaderPlusButtonWebTests: ReaderWebTesting {
    private func document(token: Int, withMenu: Bool) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>texte</p>")
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        let options = ReaderRenderOptions(showsMessageMenus: withMenu)
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token, options: options), anchor: nil,
            keepsScrollPosition: false
        )
    }

    /// [header height, button width, button height, cross width, cross height, stroke width, cross colour is the action colour (1),
    ///  cross is centred in the button (1)]; empty without a button.
    private let probe = """
        const header = document.querySelector('.message .header');
        const button = header.querySelector('.menu-button');
        if (!button) { return JSON.stringify([header.getBoundingClientRect().height]); }
        const icon = button.querySelector('svg'), path = icon.querySelector('path');
        const b = button.getBoundingClientRect(), i = icon.getBoundingClientRect();
        const probe = document.createElement('i');
        probe.style.color = 'var(--action)';
        document.body.appendChild(probe);
        const action = getComputedStyle(probe).color;
        probe.remove();
        const centred = Math.abs((i.left + i.width / 2) - (b.left + b.width / 2)) < 0.5
            && Math.abs((i.top + i.height / 2) - (b.top + b.height / 2)) < 0.5;
        return JSON.stringify([header.getBoundingClientRect().height, b.width, b.height, i.width, i.height,
                               parseFloat(getComputedStyle(path).strokeWidth), getComputedStyle(path).stroke === action ? 1 : 0,
                               centred ? 1 : 0]);
        """

    private func measure(withMenu: Bool, token: Int, scale: Int? = nil) async -> [Double] {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: token, withMenu: withMenu))
        guard await until({ recorder.ready == [token] }) else { return [] }
        if let scale {
            _ = try? await evaluate("document.documentElement.style.setProperty('--text-scale', '\(scale)'); return true;", in: controller)
        }
        let json = (try? await evaluate(probe, in: controller)) as? String ?? "[]"
        return (try? JSONDecoder().decode([Double].self, from: Data(json.utf8))) ?? []
    }

    @Test func thePlusIsALegacySizeCrossInATapBoxAndTheHeaderKeepsItsHeight() async {
        let without = await measure(withMenu: false, token: 1)
        let seen = await measure(withMenu: true, token: 2)
        #expect(without.count == 1 && seen.count == 8, "without: \(without), seen: \(seen)")
        guard without.count == 1, seen.count == 8 else { return }
        #expect(abs(seen[0] - without[0]) <= 1, "the header is \(seen[0]) px with the button, \(without[0]) without")
        #expect(seen[1] >= 32 && seen[2] >= 32, "tap box: \(seen[1]) x \(seen[2])")
        #expect(seen[3] == 16 && seen[4] == 16, "cross: \(seen[3]) x \(seen[4])")
        #expect(seen[5] == 2, "stroke: \(seen[5])")
        #expect(seen[6] == 1, "the cross is not drawn in the action colour")
        #expect(seen[7] == 1, "the cross is not centred in its box")
    }

    @Test func theCrossIgnoresTheReaderTextSize() async {
        let seen = await measure(withMenu: true, token: 3, scale: 3)
        #expect(seen.count == 8, "seen: \(seen)")
        guard seen.count == 8 else { return }
        #expect(seen[3] == 16 && seen[4] == 16 && seen[5] == 2, "at 300 %: \(seen)")
    }
}
