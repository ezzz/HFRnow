import Foundation

/// What a profile image keeps across the restarts of its load task (a reload of the profile restarts it, LOT-116).
///
/// A reload retries an image that has none, but never takes away one that loaded: a failed or cancelled attempt leaves the
/// state as it was, and the same URL is not downloaded twice. Generic over the image type so the rule is testable without UIKit.
struct ProfileImageState<Image> {
    /// The URL `image` was loaded from.
    private(set) var loadedURL: URL?
    /// The loaded image, nil while there is none (the placeholder shows).
    private(set) var image: Image?

    init() {}

    /// A load task starts for `url`: drops an image of another URL, and says whether a download is needed.
    mutating func begin(url: URL?) -> Bool {
        if loadedURL != url {
            image = nil
            loadedURL = nil
        }
        return image == nil && url != nil
    }

    /// The download of `url` ended: only a result that arrived, uncancelled, replaces the state.
    mutating func finish(url: URL, loaded: Image?, cancelled: Bool) {
        guard let loaded, !cancelled else { return }
        image = loaded
        loadedURL = url
    }
}
