/// Why a list page could not be turned into models; "no results" is not a failure (the topic list is just empty).
public enum ListPageFailure: Error, Sendable, Equatable {
    /// The forum is in maintenance; carries the message HFR shows.
    case maintenance(String)
    /// The page requires a login the session does not have; carries the message HFR shows.
    /// The topic list parser reports it for the MP list only (LOT-022): elsewhere a wall and an empty filter look the same.
    case notAuthenticated(String)
    /// The page does not have the expected structure; carries a diagnostic.
    case malformed(String)
}
