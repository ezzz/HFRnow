import HFRModels

/// What one page of the private messages list says about the MPStorage thread (LOT-038).
public enum MPStorageThreadSearch: Sendable, Hashable {
    /// The storage thread is on this page; `post` is its topic number (the `post=` of its link).
    case found(post: Int)
    /// Not on this page. The caller walks on with `navigation.nextPath` while there is one; `last` can be a lower bound.
    case notOnPage(navigation: PageNavigation)
}
