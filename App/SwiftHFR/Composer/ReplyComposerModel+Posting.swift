import Foundation
import HFRClient

extension ReplyComposerModel {
    /// One write through the poster, with the fields as they are now. Recipient and subject are trimmed, as legacy Swift did
    /// (`AnswerView.swift:1474`, `MessagesView.swift:4213` @ 21173e77); a line break inside one is refused by the engine.
    func post() async throws(PostingError) -> PostingResult {
        switch target {
        case .reply(let reply):
            return try await services.poster.reply(text, formURL: reply.formURL)
        case .newPrivateMessage(let message):
            return try await services.poster.newPrivateMessage(
                to: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                text: text, formURL: message.formURL
            )
        case .newTopic(let topic):
            return try await services.poster.newTopic(
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines), subcategory: picker.selected,
                text: text, formURL: topic.formURL
            )
        }
    }
}
