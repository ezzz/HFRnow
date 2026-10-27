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
                Text("La lecture des messages arrive bientôt. \(topic.repliesCount) réponses sur \(topic.pageCount) pages.")
            }
        } else {
            ContentUnavailableView("Choisissez un sujet", systemImage: "text.bubble")
        }
    }
}
