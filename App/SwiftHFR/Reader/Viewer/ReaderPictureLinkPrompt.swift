import SwiftUI

/// A link around a tapped picture that leaves the app, waiting for the user's answer (#912).
struct PendingPictureLink: Identifiable, Equatable {
    /// What "Ouvrir" does: the in-app Safari view or the default browser, as « Navigateur par défaut » says.
    let action: ReaderLinkAction
    let url: URL

    var id: URL { url }

    /// The domain the sentence names (the address itself when it has no host).
    var domain: String { url.host() ?? url.absoluteString }

    /// Nil unless `action` takes the user out of the app (a forum link opens in the reader with no warning, LOT-137).
    init?(_ action: ReaderLinkAction) {
        guard let url = action.externalURL else { return nil }
        self.action = action
        self.url = url
    }
}

/// The confirmation before a picture's link opens a page outside the reader (#912). `confirmationDialog` clears its item before
/// a button runs, so the action takes the item it was shown for.
struct ReaderPictureLinkPrompt: ViewModifier {
    @Binding var pending: PendingPictureLink?
    let open: @MainActor (ReaderLinkAction) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Ce lien ouvre une page externe", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible, presenting: pending
        ) { link in
            Button("Ouvrir") { open(link.action) }
            Button("Annuler", role: .cancel) {}
        } message: { link in
            Text(link.domain)
        }
    }
}
