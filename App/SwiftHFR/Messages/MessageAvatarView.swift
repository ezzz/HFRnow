import HFRStorage
import SwiftUI
import UIKit

/// The interlocutor's avatar from the avatar cache (LOT-066), a generic one when the cache has none, a group icon for a
/// group thread. It only reads the cache: HFR's list rows carry no avatar link, and nothing here downloads one.
struct MessageAvatarView: View {
    let pseudo: String?
    let isGroup: Bool
    @State private var image: UIImage?

    var body: some View {
        Group {
            if isGroup {
                placeholder("person.2.fill")
            } else if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder("person.crop.circle.fill")
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay { Circle().stroke(.tertiary, lineWidth: 1) }
        .accessibilityHidden(true)
        .task(id: pseudo) { image = isGroup ? nil : await Self.cachedImage(pseudo: pseudo) }
    }

    private func placeholder(_ symbol: String) -> some View {
        Circle().fill(.quaternary).overlay {
            Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(.secondary).padding(8)
        }
    }

    /// Decodes the cached file off the main actor; a missing, unreadable or non-image file is no avatar.
    private static func cachedImage(pseudo: String?) async -> UIImage? {
        guard let pseudo, !pseudo.isEmpty else { return nil }
        return await Task.detached {
            guard let entry = try? AvatarCache(cache: .standard).entry(forPseudo: pseudo),
                  let data = try? Data(contentsOf: entry.fileURL) else { return nil }
            return UIImage(data: data)
        }.value
    }
}
