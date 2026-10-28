import SwiftUI

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
