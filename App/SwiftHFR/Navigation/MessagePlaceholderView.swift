import HFRModels
import SwiftUI

/// The detail column until the topic reader exists: names the chosen topic, fetches nothing (a topic GET with the account
/// would mark its flags read).
struct MessagePlaceholderView: View {
    let topic: TopicSummary?

    var body: some View {
        if let topic {
            ContentUnavailableView {
                Label(topic.title, systemImage: "text.bubble")
            } description: {
                Text("La lecture des messages arrive bientôt. \(counts(of: topic)).")
            }
        } else {
            ContentUnavailableView("Choisissez un sujet", systemImage: "text.bubble")
        }
    }

    private func counts(of topic: TopicSummary) -> String {
        let replies = FrenchPlural.count(topic.repliesCount, "réponse", "réponses")
        return "\(replies) sur \(FrenchPlural.count(topic.pageCount, "page", "pages"))"
    }
}
