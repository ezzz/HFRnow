import Foundation
import HFRModels
@testable import SwiftHFR

/// A scripted topic page source: each call is answered by a closure and recorded.
final class FakeTopicPages: TopicPageSource, @unchecked Sendable {
    typealias Handler = @Sendable (ReaderTarget) async throws(ListLoadError) -> ReaderPage

    private let lock = NSLock()
    private var recorded: [ReaderTarget] = []
    private var storedHandler: Handler

    init(handler: @escaping Handler = { target in readerPage(page: target.page) }) {
        storedHandler = handler
    }

    var handler: Handler {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    /// Requests received, in order.
    var requests: [ReaderTarget] { lock.withLock { recorded } }

    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage {
        lock.withLock { recorded.append(target) }
        return try await handler(target)
    }
}

/// Lets a test hold a load open until it decides to finish it.
actor ReaderGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    private var arrived = false

    func untilArrived() async {
        while !arrived { await Task.yield() }
    }

    func wait() async {
        arrived = true
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

let readerTopic = TopicID(category: .forum(13), topic: 28563)

/// Page `page` of 5 of `readerTopic`, two messages numbered from `page * 100`.
func readerPage(page: Int, maxPage: Int = 5, title: String = "Sujet") -> ReaderPage {
    ReaderPage(
        topicID: readerTopic, title: title, currentPage: page, maxPage: maxPage,
        messages: [
            ReaderMessage(
                numreponse: page * 100, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>un</p>")
            ),
            ReaderMessage(
                numreponse: page * 100 + 1, author: "autre", isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "27-10-2026 10:01:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>deux</p>")
            )
        ]
    )
}

func url(_ text: String) -> URL {
    guard let url = URL(string: text) else { preconditionFailure("Valid test URL: \(text)") }
    return url
}
