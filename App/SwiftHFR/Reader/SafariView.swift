import HFRModels
import SafariServices
import SwiftUI

// Moved out of TopicReaderView.swift, which reached SwiftLint's `file_length` with issue #750.
struct ExternalLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct VideoItem: Identifiable {
    let embed: MessageEmbed
    var id: String { embed.embedURL.absoluteString }
}

/// A web link opened outside the reader, in Safari's own view (LOT-071 T8): Safari's data, not the app's. Legacy
/// `SafariInAppView` (`MessagesView.swift:2874-2885` at `21173e77`).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
