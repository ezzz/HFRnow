/// Which transport a fetch goes through.
public enum FetchIdentity: Sendable, Equatable {
    /// Cookie-less: never marks anything read (HFR-PROTOCOL §7, E25). Default for topic pages.
    case anonymous
    /// The account's session: needed for personal lists, flags and reading as the user.
    case authenticated
}
