import Foundation
import HFRClient
import HFRModels
@testable import SwiftHFR
import Synchronization

/// What a release was asked to do.
struct ReleaseCall: Equatable, Sendable {
    let release: QuoteRelease
    let postedText: String
}

/// The reader's quoting seam with a scripted prefill and a selection kept in memory, in toggle order like the cookie.
final class ScriptedQuoter: QuoteOpening {
    private struct State {
        var selected: [Int] = []
        var quote: Result<String, QuoteError> = .success("")
        var selection: Result<String, QuoteError> = .success("")
        var quoteLinks: [URL?] = []
        var selectionLinks: [URL] = []
        var releases: [ReleaseCall] = []
    }

    private let state = Mutex(State())
    /// Suspends every single quote until opened, when set.
    let gate: ReaderGate?

    init(selected: [Int] = [], gate: ReaderGate? = nil) {
        self.gate = gate
        state.withLock { $0.selected = selected }
    }

    /// Scripts the answer of `quote`.
    func scriptQuote(_ result: Result<String, QuoteError>) { state.withLock { $0.quote = result } }
    /// Scripts the answer of `selectionQuote` (its text; the release names the selection as it is at the call).
    func scriptSelection(_ result: Result<String, QuoteError>) { state.withLock { $0.selection = result } }

    /// Quote links `quote` was asked for, in order.
    var quoteLinks: [URL?] { state.withLock { $0.quoteLinks } }
    /// Answer links `selectionQuote` was asked for, in order.
    var selectionLinks: [URL] { state.withLock { $0.selectionLinks } }
    /// Releases asked for, in order.
    var releases: [ReleaseCall] { state.withLock { $0.releases } }
    /// The selection now.
    var selected: [Int] { state.withLock { $0.selected } }

    func selectedNumbers(for token: QuoteSelectionToken) async -> [Int] { selected }

    func toggle(_ token: QuoteSelectionToken) async -> Bool {
        state.withLock { state in
            if let index = state.selected.firstIndex(of: token.numreponse) {
                state.selected.remove(at: index)
                return false
            }
            state.selected.append(token.numreponse)
            return true
        }
    }

    func quote(_ message: MessageActions) async throws(QuoteError) -> String {
        state.withLock { $0.quoteLinks.append(message.quoteURL) }
        await gate?.wait()
        return try state.withLock { $0.quote }.get()
    }

    func selectionQuote(_ token: QuoteSelectionToken, answerFormURL: URL) async throws(QuoteError) -> ReplyQuote {
        let answer = state.withLock { state -> (text: Result<String, QuoteError>, numbers: [Int]) in
            state.selectionLinks.append(answerFormURL)
            return (state.selection, state.selected)
        }
        return ReplyQuote(text: try answer.text.get(), release: QuoteRelease(token: token, numbers: answer.numbers))
    }

    func release(_ release: QuoteRelease, postedText: String) async {
        state.withLock { $0.releases.append(ReleaseCall(release: release, postedText: postedText)) }
    }
}

/// The quote link of message `number` of `readerTopic`, as LOT-031 reads it (`R41a`'s shape).
func quoteLink(_ number: Int) -> URL {
    url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&numrep=\(number)&page=1&p=1&subcat=0&sondage=0&new=0")
}

/// The multi-quote token of message `number` of `readerTopic`.
func quoteToken(_ number: Int) -> QuoteSelectionToken {
    QuoteSelectionToken(forum: "hardwarefr", topic: readerTopic, numreponse: number)
}

/// A page of `readerTopic` whose messages `numbers` carry their quote link and multi-quote token, with the answer link of `R61d`.
func quotablePage(numbers: [Int] = [100, 101], answerURL: URL? = replyFormURL, quotable: Bool = true) -> ReaderPage {
    let messages = numbers.map { number in
        ReaderMessage(
            numreponse: number, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
            dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>x</p>"),
            actions: quotable ? MessageActions(quoteURL: quoteLink(number), quoteSelection: quoteToken(number)) : MessageActions()
        )
    }
    var page = ReaderPage(topicID: readerTopic, title: "Sujet", currentPage: 1, maxPage: 1, messages: messages)
    page.answerURL = answerURL
    return page
}
