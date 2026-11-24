// Port of HFRswift/Swift/Favorites.swift (FavoritesListView, logged-out block `:667-680`, shown when no account is current,
// `:476-478`) and HFRswift/Swift/MainWindow.swift (ForumTopicsListView, filter note `:699-707`) @ 87fe0d1c. Differences: legacy
// draws both as inline rows, left-aligned (`.headline` + `.subheadline`; the note `.footnote`), SwiftHFR as a centred
// `ContentUnavailableView` for the prompt (the shared `EmptyStateView`, #1306) and a left-aligned row for the note; legacy's
// "Ajouter un pseudo" opens its add-account sheet, here the login sheet for a new account; an account whose session expired
// gets "Se reconnecter", as the account button, a state legacy's prompt does not have (#824, GAP-037).

/// The sign-in prompt of Favoris without an account: a title, one line and one button (no refresh: there is nothing to refresh).
struct SignInPrompt: Equatable {
    let title: String
    let message: String
    let systemImage: String
    let action: String
    /// What the button opens: a new account, or the expired current one.
    let target: LoginTarget
}

/// Why Favoris, Suivis and Lus cannot be chosen when logged out: a bold title and a subtitle.
struct FilterNote: Equatable {
    let title: String
    let subtitle: String?
    let systemImage: String
}

extension TopicListModel {
    /// Favoris and Drapeaux without a usable account (legacy `if !isLoggedIn`, `Favorites.swift:667`); nil on forum lists, which
    /// keep their own wall, and once an account is signed in. Like the account button: no account at all adds one, an expired
    /// current account signs in again (`AccountMenuButton.swift:53-56`).
    func signInPrompt(current: AccountRow?) -> SignInPrompt? {
        guard source.isFavoritesList, case .signInRequired? = loader.value?.emptyReason else { return nil }
        if let current, current.status == .expired {
            return SignInPrompt(
                title: "Connectez-vous pour accéder aux favoris",
                message: "Votre session a expiré : reconnectez-vous pour charger vos favoris et vos drapeaux.",
                systemImage: "star.slash",
                action: "Se reconnecter",
                target: .existing(id: current.id, displayName: current.displayName)
            )
        }
        return SignInPrompt(
            title: "Connectez-vous pour accéder aux favoris",
            message: "Ajoutez un pseudo pour charger vos favoris et vos drapeaux.",
            systemImage: "star.slash",
            action: "Ajouter un pseudo",
            target: .newAccount
        )
    }

    /// The note under the filter picker when it cannot be used: legacy's two lines when logged out
    /// (`MainWindow.swift:699-706`), or the app's own note for a list that names no `subcat`.
    var filterNote: FilterNote? {
        guard loader.value != nil, !offersFilter else { return nil }
        guard isSignedIn else {
            return FilterNote(
                title: "Connexion requise pour Favoris, Suivis et Lus",
                subtitle: "Vous pouvez consulter \"Tous\" sans compte.",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        }
        return FilterNote(
            title: "Le filtre n'est pas disponible pour cette liste : choisissez « Tous les sous-forums ».",
            subtitle: nil,
            systemImage: "info.circle"
        )
    }
}
