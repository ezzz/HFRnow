import HFRModels

/// App Review workaround kept from the legacy app (audit Q-7): the Apple category is hidden when logged out and for the
/// App Review account. The reviewer account name is configuration, not a constant of the logic.
struct ForumVisibility: Sendable, Equatable {
    /// The category to hide.
    var hiddenCategory: CategoryID = .forum(25)
    /// Pseudo of the App Review account (default `applereview`).
    var reviewAccountName = "applereview"

    /// `forums` without the hidden category when the viewer is logged out or is the review account.
    func visible(_ forums: [ForumCategory], isLoggedIn: Bool, accountName: String?) -> [ForumCategory] {
        guard hidesCategory(isLoggedIn: isLoggedIn, accountName: accountName) else { return forums }
        return forums.filter { category(of: $0) != hiddenCategory }
    }

    /// Whether the viewer must not see the hidden category.
    func hidesCategory(isLoggedIn: Bool, accountName: String?) -> Bool {
        guard isLoggedIn, let accountName else { return true }
        return accountName.compare(reviewAccountName, options: .caseInsensitive) == .orderedSame
    }

    private func category(of forum: ForumCategory) -> CategoryID? {
        forum.categoryID ?? ForumCatalogue.categoryID(forPath: forum.path)
    }
}
