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
    /// Where the image comes from: smileys (forum host, intrinsic size) or the GIF panel (Giphy's CDN after notice N1, fills its frame).
    var source = Source.smiley

    enum Source: Equatable {
        case smiley, gif
    }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        Self.configure(view, contentMode: contentMode, flexible: source == .gif)
        return view
    }

    /// A GIF is hundreds of points wide: with the default priorities the image view keeps its intrinsic size and the sheet crops it
    /// (the buttons below fall out of view). Flexible makes it take whatever the layout proposes. Smileys keep the defaults.
    static func configure(_ view: UIImageView, contentMode: UIView.ContentMode, flexible: Bool) {
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.isAccessibilityElement = false
        guard flexible else { return }
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            view.setContentCompressionResistancePriority(.defaultLow, for: axis)
            view.setContentHuggingPriority(.defaultLow, for: axis)
        }
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        context.coordinator.update(view, url: url, hasImage: hasImage)
    }

    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(loader: source == .gif ? .gif() : SmileyImageLoader())
    }

    /// Remembers which URL the view shows and the download in flight.
    @MainActor
    final class Coordinator {
        private var current: URL?
        private var task: Task<Void, Never>?
        /// Built once per cell: a loader per update would leak an HTTP session each time.
        private let loader: SmileyImageLoader

        init(loader: SmileyImageLoader) {
            self.loader = loader
        }

        func update(_ view: UIImageView, url: URL, hasImage: Binding<Bool>) {
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
