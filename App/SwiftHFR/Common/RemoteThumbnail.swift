import SwiftUI
import UIKit

/// A small image loaded through the app's image client (#1193), never `AsyncImage`: `loader` decides which hosts may be
/// asked (the cookie-less client, policy C, its own host filter) and caches what it decoded. A grey square stands in until the
/// image is there, and for good when it cannot be had.
struct RemoteThumbnail: View {
    let url: URL
    let loader: SmileyImageLoader
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .task(id: url) {
            image = SmileyImageLoader.cached(url)
            guard image == nil else { return }
            let loaded = await loader.image(at: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
