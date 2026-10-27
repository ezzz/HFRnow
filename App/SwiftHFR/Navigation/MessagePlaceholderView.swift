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
                Text("La lecture des messages arrive bientôt. \(FrenchPlural.count(topic.repliesCount, "réponse", "réponses")) sur \(FrenchPlural.count(topic.pageCount, "page", "pages")).")
            }
        } else {
            ContentUnavailableView("Choisissez un sujet", systemImage: "text.bubble")
        }
    }
}
