import Foundation

/// What a search inside a topic found (LOT-046).
public enum TopicSearchResult: Sendable, Equatable {
    /// The topic page holding the first match, where HFR redirects (`…&currentnum=<n>#t<n>`, `R52a`): a forum page of the
    /// searched topic.
    case match(URL)
    /// HFR found nothing ("Désolé aucune réponse n'a été trouvée", `R52b`).
    case noMatch
}
