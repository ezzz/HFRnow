import Foundation

/// Topic number and page read from a canonical topic URL such as `.../hfr-android-sujet_148745_3.htm`.
///
/// The canonical path is the final URL of `forum2.php` (HFR-PROTOCOL R5); it may carry a sub-category segment, so only
/// the `sujet_<post>_<page>.htm` tail is read, after a `-` (slug separator) or at the start of the name.
public struct TopicPageLocation: Sendable, Equatable {
    /// Topic number (the `post` parameter).
    public let topic: Int
    /// Page number, starting at 1.
    public let page: Int

    /// Creates a location.
    public init(topic: Int, page: Int) {
        self.topic = topic
        self.page = page
    }

    /// Reads the location from a canonical topic URL; nil for any other shape (for example `forum2.php`).
    public init?(url: URL) {
        let name = url.lastPathComponent
        guard let match = name.firstMatch(of: /(?:^|-)sujet_(\d+)_(\d+)\.htm$/),
              let topic = Int(match.1), let page = Int(match.2), page >= 1 else { return nil }
        self.init(topic: topic, page: page)
    }
}
