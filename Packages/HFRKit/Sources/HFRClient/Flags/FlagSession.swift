import HFRNetwork

/// The account session a flag write runs in: its cookies carry the request, and it holds the account's `hash_check`.
///
/// `HFRSession` is the real one; tests script the answers.
protocol FlagSession: PostingSession {
    /// The last token recorded for the account; nil when none was read yet.
    var hashCheck: String? { get }
}

extension HFRSession: FlagSession {}
