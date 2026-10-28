import HFRModels
import SwiftUI

/// The detail column when no topic can be shown: nothing chosen yet, or a row whose link names no topic page.
struct MessagePlaceholderView: View {
    let topic: TopicSummary?

    var body: some View {
        if let topic {
            ContentUnavailableView {
                Label(topic.title, systemImage: "text.bubble")
            } description: {
                Text("Ce sujet ne peut pas être ouvert : son lien n'est pas reconnu.")
            }
        } else {
            ContentUnavailableView("Choisissez un sujet", systemImage: "text.bubble")
        }
    }
}
