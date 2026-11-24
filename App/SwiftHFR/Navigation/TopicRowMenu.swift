import HFRModels
import SwiftUI

/// The page-number prompt of a row menu ("Page numéro…", legacy `pagePickerSheet`), shared by the MP list and the search results.
/// The topic list has its own copy (`TopicListView`).
struct TopicPagePrompt: ViewModifier {
    /// The row being asked about; nil closes the prompt.
    @Binding var topic: TopicSummary?
    @Binding var text: String
    let open: (TopicSummary, TopicOpening) -> Void

    func body(content: Content) -> some View {
        content.alert(
            "Page numéro", isPresented: Binding(get: { topic != nil }, set: { if !$0 { topic = nil } }), presenting: topic
        ) { topic in
            TextField("Page", text: $text).keyboardType(.numberPad)
            Button("Annuler", role: .cancel) {}
            Button("Aller") {
                let number = Int(text.trimmingCharacters(in: .whitespaces)) ?? 0
                if let opening = TopicQuickActions.page(number, of: topic) { open(topic, opening) }
            }
        } message: { topic in
            Text("Entre 1 et \(topic.pageCount)")
        }
    }
}

/// The quick-action entries of a row menu (MP list, search results), legacy order; what cannot run is left out (#1162).
struct TopicRowMenu: View {
    let topic: TopicSummary
    let context: TopicRowMenuContext
    let open: (TopicSummary, TopicOpening) -> Void
    /// Asks for a page number for this row (the owner presents `TopicPagePrompt`).
    let askPage: (TopicSummary) -> Void

    var body: some View {
        ForEach(TopicQuickActions.menu(of: topic, in: context), id: \.self) { entry in
            switch entry {
            case .searchMatch(let opening):
                Button("Dernière correspondance", systemImage: "magnifyingglass") { open(topic, opening) }
            case .firstPage(let opening):
                Button("Première page", systemImage: "backward.end") { open(topic, opening) }
            case .lastPage(let opening):
                Button("Dernière page", systemImage: "forward.end") { open(topic, opening) }
            case .lastReply(let opening):
                Button("Dernière réponse", systemImage: "text.append") { open(topic, opening) }
            case .pagePrompt:
                Button("Page numéro…", systemImage: "number") { askPage(topic) }
            case .copyLink(let link):
                Button("Copier le lien", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = link.absoluteString
                    AccessibilityNotification.Announcement("Lien copié").post()
                }
            }
        }
    }
}
