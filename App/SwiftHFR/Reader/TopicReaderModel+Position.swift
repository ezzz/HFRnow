import HFRStorage

extension TopicReaderModel {
    /// Takes what writes on the account's behalf: the position recorder (LOT-111) and the composer's placement of the legacy
    /// drafts (LOT-158), nil when the reader offers no reply.
    func adopt(_ services: ReaderServices, composer: ComposerServices?) {
        positions = services.positions
        legacyDrafts = composer?.legacyDrafts
    }

    /// The web view reports `post` as the topmost message of document `token`: recorded as the reading position. A report
    /// of an older document, of a message the page on screen does not hold, or of a continuation block is ignored.
    func recordPosition(post: Int, token: Int) async {
        guard token == document?.token, let page, let topic = page.topicID, let positions,
              page.messages.contains(where: { !$0.isContinuation && $0.numreponse == post }) else { return }
        await positions.record(ReadingPosition(page: page.currentPage, messageNumber: post), in: topic)
    }
}
