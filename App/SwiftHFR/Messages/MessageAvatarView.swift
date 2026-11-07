import HFRStorage
import SwiftUI
import UIKit

// Port of HFRswift/Swift/MPListView.swift (MPAvatarView, MPAvatarImageStore) @ 2440d79. Differences: the avatar cache is filled by
// `AvatarStore` from the pages read (GAP-228); the placeholder is a monogram, not a grey disc.
/// The interlocutor's avatar from the avatar cache (LOT-066), a monogram when the cache has none, a group icon for a group
/// thread; the row sets its size (LOT-169 density). It only reads the cache; `AvatarStore` fills it, and the view reads it again
/// when the store's generation changes.
struct MessageAvatarView: View {
    let pseudo: String?
    let isGroup: Bool
    @State private var image: UIImage?
    @Environment(\.avatarRefresh) private var refresh
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if isGroup {
                groupPlaceholder
            } else if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                monogram
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .overlay { Circle().stroke(.tertiary, lineWidth: 1) }
        .accessibilityHidden(true)
        .task(id: TaskKey(pseudo: pseudo, generation: refresh?.generation ?? 0)) {
            image = isGroup ? nil : await Self.cachedImage(pseudo: pseudo)
        }
    }

    /// Re-runs the cache read for another pseudo or after the store wrote an avatar.
    private struct TaskKey: Equatable {
        let pseudo: String?
        let generation: Int
    }

    private var groupPlaceholder: some View {
        Circle().fill(.quaternary).overlay {
            Image(systemName: "person.2.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(8)
        }
    }

    private var monogram: some View {
        let dark = colorScheme == .dark
        let mark = Monogram(pseudo: pseudo ?? "")
        return Circle().fill(Self.color(mark.background(dark: dark))).overlay {
            Text(mark.initials)
                .font(.system(size: 100, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.01)
                .lineLimit(1)
                .foregroundStyle(Self.color(Monogram.foreground(dark: dark)))
                .padding(10)
        }
    }

    private static func color(_ rgb: Monogram.RGB) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
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
