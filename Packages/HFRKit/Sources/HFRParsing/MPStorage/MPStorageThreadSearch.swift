import HFRModels

/// What one page of the private messages list says about the MPStorage thread (LOT-038).
public struct MPStorageThreadSearch: Sendable, Hashable {
    /// Topic numbers (the `post=` of their links) of the rows titled with the storage subject, in list order.
    ///
    /// Any member can send an MP with that subject (#1200 P1): a candidate is the account's storage thread only once its
    /// first message proves to be the account's (its edit link, `MPStorageTransport`).
    public var candidates: [Int]
    /// The page's pager. The caller walks on with `navigation.nextPath` while no candidate is the account's.
    public var navigation: PageNavigation

    /// Creates a search result.
    public init(candidates: [Int], navigation: PageNavigation) {
        self.candidates = candidates
        self.navigation = navigation
    }
}
