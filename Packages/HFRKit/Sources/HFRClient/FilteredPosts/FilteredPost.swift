import HFRModels
import HFRParsing

/// A message the post filter kept, with the page it was read on.
public struct FilteredPost: Sendable, Equatable {
    /// The topic page the message is on.
    public let page: Int
    /// The message block as the page served it (LOT-030).
    public let block: MessageBlock
    /// Its quotes (LOT-032).
    public let quotes: [MessageQuote]
}
