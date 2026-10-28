/// The write a posting flow performs, each with the sentence HFR confirms it with.
public enum PostingAction: String, Sendable, Hashable, CaseIterable {
    /// A reply in a topic or a private-message thread (quotes included).
    case reply
    /// A new topic in a forum category.
    case newTopic
    /// A new private-message thread.
    case newPrivateMessage
    /// An edit of an own message.
    case edit
    /// The deletion of an own message (of the whole thread when it is its first post).
    case delete

    /// HFR's confirmation for this write, compared with the whole `.hop` sentence (HFR-PROTOCOL §7 E15).
    ///
    /// Captured on private messages only (`W10`, `W11`, `W15`, `W16a`, `W19`): a public-topic answer with another sentence
    /// is reported as unconfirmed, never as a success (spec "Pending capture").
    var confirmation: String {
        switch self {
        case .reply: "Votre réponse a été postée avec succès !"
        case .newTopic, .newPrivateMessage: "Votre message a été posté avec succès !"
        case .edit: "Votre message a été édité avec succès !"
        case .delete: "Message effacé avec succès !"
        }
    }
}
