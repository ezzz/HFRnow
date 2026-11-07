import SwiftUI
import UIKit

// Port of HFRswift/Swift/AnswerView.swift (SmileyThumbnailView) @ 2440d79. Differences: UIImageView only (no SDWebImage), loads
// through SmileyImageLoader (GAP-087).
/// An animated smiley image (legacy `SmileyThumbnailView`, `HFRswift/Swift/AnswerView.swift:1651` @ 2440d79).
///
/// The cell does no work when its smiley did not change (LESSONS 49): `updateUIView` returns at once for the same URL,
/// so scrolling or a parent update never restarts a download or a decode.
struct SmileyThumbnailView: UIViewRepresentable {
    let url: URL
    var contentMode: UIView.ContentMode = .center
    /// Set once an image is shown; stays false while loading or when it cannot be had.
    var hasImage: Binding<Bool> = .constant(true)
    /// A third-party host may be contacted (the GIF panel, after notice N1); smileys never.
    var allowsThirdParty = false

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        let loader = SmileyImageLoader(allowsThirdParty: allowsThirdParty)
        context.coordinator.update(view, url: url, hasImage: hasImage, loader: loader)
    }

    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Remembers which URL the view shows and the download in flight.
    @MainActor
    final class Coordinator {
        private var current: URL?
        private var task: Task<Void, Never>?
        func update(_ view: UIImageView, url: URL, hasImage: Binding<Bool>, loader: SmileyImageLoader) {
            guard current != url else { return }
            current = url
            task?.cancel()
            view.image = SmileyImageLoader.cached(url)
            if view.image != nil {
                view.startAnimating()
                // Not during the view update: SwiftUI forbids writing state from it.
                Task { hasImage.wrappedValue = true }
                return
            }
            Task { hasImage.wrappedValue = false }
            task = Task { [weak view, loader] in
                guard let image = await loader.image(at: url), !Task.isCancelled else {
                    // Not remembered as shown: the next update (scroll, reopen) tries again.
                    if self.current == url { self.current = nil }
                    return
                }
                guard let view, self.current == url else { return }
                view.image = image
                view.startAnimating()
                hasImage.wrappedValue = true
            }
        }

        func cancel() {
            task?.cancel()
            task = nil
        }
    }
}
