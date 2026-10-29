import SwiftUI

/// The one entry point of the Messages tab on the tab bar; it owns its navigation container, so a call site adds none.
/// LOT-126 (#307) replaces its body with `MessagesTabView(environment:)`, which is a split view of its own, and fills
/// `MessagesListColumn` (the iPad sidebar's content column) with the same list.
struct MessagesRootView: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack { MessagesPlaceholderView() }
    }
}

/// The Messages list in the content column of the regular-width iPad root, with the conversation in the detail column, the
/// Favoris shape. It owns its navigation stack.
struct MessagesListColumn: View {
    let environment: AppEnvironment

    var body: some View {
        NavigationStack { MessagesPlaceholderView() }
    }
}

/// The Messages screen until the private-message list lands (LOT-126); the unread badge is already on the tab.
struct MessagesPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Messages privés", systemImage: "envelope",
            description: Text("Cet écran arrive dans une prochaine version.")
        )
        .navigationTitle("Messages")
    }
}
