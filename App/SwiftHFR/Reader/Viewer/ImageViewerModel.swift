import Foundation
import HFRNetwork
import Observation

/// A downloaded image of the viewer.
struct ViewerImage: Equatable, Sendable {
    /// The bytes as received (what is saved and shared).
    let data: Data
    /// The `image/*` type.
    let mimeType: String
}

/// How the viewer downloads, saves and copies; the app wires the real ones, tests stub them.
struct ImageViewerServices: Sendable {
    /// Downloads `url` (cookie-less, the host's `Referer` rule) or throws.
    var load: @Sendable (_ url: URL, _ allowsThirdParty: Bool) async throws -> ViewerImage
    /// Adds the image to the photo library.
    var save: @Sendable (_ image: ViewerImage) async throws(ImageSaveError) -> Void
    /// Puts a URL on the pasteboard.
    var copy: @MainActor @Sendable (_ url: URL) -> Void
}

/// Why an image was not saved (legacy `MessageImagePhotoLibrarySaver.SaveError`).
enum ImageSaveError: Error, Equatable, Sendable {
    /// The user refused access to Photos.
    case permissionDenied
    /// The bytes are not an image.
    case invalidImage
    /// The library refused the write.
    case system
}

/// Download state of one image of the gallery.
enum ViewerImageState: Equatable, Sendable {
    /// Not requested yet.
    case idle
    /// Being downloaded.
    case loading
    /// Downloaded.
    case loaded(ViewerImage)
    /// Not available.
    case failed
}

// Port of HFRswift/Classes/SimplePhotoViewController.m and MessagesView.swift (`FullScreenPhotoViewer` `:5643`,
// `MessageImagePhotoLibrarySaver` `:2430`) @ 2440d79. Differences: GAP-057 / FEAT-014: swipe between the images of the page,
// every request through the cookie-less client (legacy used `URLSession.shared`), a failed full-size URL falls back to the thumbnail.
/// The full-screen viewer's state (LOT-109): the images, the selected one, their download states and the feedback line.
///
/// Only the selected image and its direct neighbours are requested, so a page with many pictures does not download them all.
@Observable @MainActor
final class ImageViewerModel: Identifiable {
    let images: [GalleryImage]
    /// The selected image; the view binds it to its pager.
    var index: Int {
        didSet {
            guard index != oldValue else { return }
            prefetch()
        }
    }

    /// Download state per gallery position.
    private(set) var states: [ViewerImageState]
    /// A short message for the viewer's banner (saved, error), in French.
    private(set) var feedback: String?
    /// Changes with every message, so the banner's timer restarts when the same text comes twice.
    private(set) var feedbackID = 0
    /// The address that answered for each loaded position (the thumbnail when the full-size URL failed).
    private var answered: [Int: URL] = [:]
    @ObservationIgnored private let services: ImageViewerServices
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]

    /// Creates the viewer of `images` opened on `index` (clamped).
    init(images: [GalleryImage], index: Int, services: ImageViewerServices) {
        self.images = images
        self.index = images.isEmpty ? 0 : min(max(index, 0), images.count - 1)
        self.services = services
        states = Array(repeating: .idle, count: images.count)
    }

    /// "2 / 5" for the pager's title; empty for a single image.
    var positionText: String {
        images.count > 1 ? "\(index + 1) / \(images.count)" : ""
    }

    /// The selected image once downloaded.
    var currentImage: ViewerImage? {
        guard states.indices.contains(index), case .loaded(let image) = states[index] else { return nil }
        return image
    }

    /// The address copied by "Copier le lien": the one that answered (the full-size URL, or the thumbnail when only that worked).
    var currentLink: URL? {
        guard images.indices.contains(index) else { return nil }
        return answered[index] ?? images[index].full
    }

    /// Requests the selected image and its neighbours that were not requested yet, and drops the ones further away: a photo
    /// topic swiped through must not hold hundreds of megabytes (an image is up to `ReaderImageFetcher.maximumBytes`).
    func prefetch() {
        for position in states.indices where abs(position - index) > 1 && states[position] != .idle {
            tasks.removeValue(forKey: position)?.cancel()
            states[position] = .idle
        }
        // The selected image asks again when an earlier attempt failed (a neighbour that failed on a network drop).
        if states.indices.contains(index), states[index] == .failed { start(index) }
        for position in [index, index + 1, index - 1] where images.indices.contains(position) && states[position] == .idle {
            start(position)
        }
    }

    /// Asks again for an image that failed.
    func retry(_ position: Int) {
        guard states.indices.contains(position), states[position] == .failed else { return }
        start(position)
    }

    /// Returns when the downloads started so far are over (a signal for callers that must not guess a delay).
    func settle() async {
        for task in Array(tasks.values) { await task.value }
    }

    /// Stops every download (the viewer closes).
    func cancel() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        // A cancelled download never answers: its image is asked for again by the next `prefetch`.
        for position in states.indices where states[position] == .loading { states[position] = .idle }
    }

    /// Copies the full-size address of the selected image.
    func copyLink() {
        guard let url = currentLink else { return }
        services.copy(url)
        say("Lien copié")
    }

    /// Saves the selected image to Photos; says so when it is not downloaded yet.
    func saveToPhotos() async {
        guard let image = currentImage else {
            say("Image pas encore chargée")
            return
        }
        do throws(ImageSaveError) {
            try await services.save(image)
            say("Photo enregistrée")
        } catch {
            switch error {
            case .permissionDenied: say("Autorise l'accès aux Photos pour enregistrer l'image.")
            case .invalidImage: say("Impossible d'enregistrer cette image.")
            case .system: say("L'enregistrement dans Photos a échoué.")
            }
        }
    }

    private func say(_ text: String) {
        feedback = text
        feedbackID += 1
    }

    /// Clears the banner.
    func dismissFeedback() {
        feedback = nil
    }

    private func start(_ position: Int) {
        states[position] = .loading
        let item = images[position]
        let services = services
        tasks[position] = Task { [weak self] in
            let result = await Self.download(item, services: services)
            guard !Task.isCancelled, let self else { return }
            self.tasks[position] = nil
            if let result {
                self.answered[position] = result.url
                self.states[position] = .loaded(result.image)
            } else {
                self.states[position] = .failed
            }
        }
    }

    /// The full-size image, or the thumbnail the page showed when the host does not serve the full-size one.
    private static func download(_ item: GalleryImage, services: ImageViewerServices) async -> (image: ViewerImage, url: URL)? {
        if let image = try? await services.load(item.full, item.allowsThirdParty) { return (image, item.full) }
        guard item.full != item.shown, !Task.isCancelled,
              let image = try? await services.load(item.shown, item.allowsThirdParty) else { return nil }
        return (image, item.shown)
    }
}
