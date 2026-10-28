import SwiftUI

/// The one entry point of the Messages tab, on the tab bar and in the iPad sidebar. LOT-126 replaces its body with the MP list
/// and touches no other file.
struct MessagesRootView: View {
    var body: some View { MessagesPlaceholderView() }
}

/// The Messages tab until the private-message list lands (LOT-126); the unread badge is already on the tab.
struct MessagesPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Messages privés", systemImage: "envelope",
            description: Text("Cet écran arrive dans une prochaine version.")
        )
        .navigationTitle("Messages")
    }
}
