import HFRStorage

extension TopicReaderModel {
    /// The web view reports `post` as the topmost message of document `token`: recorded as the reading position. A report
    /// of an older document, of a message the page on screen does not hold, or of a continuation block is ignored.
    func recordPosition(post: Int, token: Int) async {
        guard token == document?.token, let page, let topic = page.topicID, let positions,
              page.messages.contains(where: { !$0.isContinuation && $0.numreponse == post }) else { return }
        await positions.record(ReadingPosition(page: page.currentPage, messageNumber: post), in: topic)
    }
}
