import SwiftUI
import UIKit

/// An animated smiley image (legacy `SmileyThumbnailView`, `HFRswift/Swift/AnswerView.swift:1651` @ 2440d79).
///
/// The cell does no work when its smiley did not change (LESSONS 49): `updateUIView` returns at once for the same URL,
/// so scrolling or a parent update never restarts a download or a decode.
struct SmileyThumbnailView: UIViewRepresentable {
    let url: URL
    var contentMode: UIView.ContentMode = .center

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        context.coordinator.update(view, url: url)
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
        private let loader = SmileyImageLoader()

        func update(_ view: UIImageView, url: URL) {
            guard current != url else { return }
            current = url
            task?.cancel()
            view.image = SmileyImageLoader.cached(url)
            if view.image != nil {
                view.startAnimating()
                return
            }
            task = Task { [weak view, loader] in
                guard let image = await loader.image(at: url), !Task.isCancelled else { return }
                guard let view, self.current == url else { return }
                view.image = image
                view.startAnimating()
            }
        }

        func cancel() {
            task?.cancel()
            task = nil
        }
    }
}
