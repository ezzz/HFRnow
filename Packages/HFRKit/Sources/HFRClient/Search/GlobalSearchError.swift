import HFRModels
import HFRNetwork
import HFRParsing

/// Why a global search gave no results page (LOT-046).
public enum GlobalSearchError: Error, Sendable, Equatable {
    /// The text holds a word legacy would not search for (decision Q-7); nothing was sent.
    case bannedWord(String)
    /// The path is not a search results page of the forum; nothing was sent.
    case invalidPage(String)
    /// The request could not be built (empty text, impossible date) or sent, HFR answered an HTTP error, or the task was
    /// cancelled before a request left.
    case network(NetworkError)
    /// The waiting page names no results page on the forum (legacy: "Aucune page de résultats n'a été trouvée").
    case noResultsPage(ParsingError)
    /// The results page is not a list (maintenance, unreadable page, page served off the forum).
    case page(ListPageFailure)
}
