import Foundation
import HFRModels

/// One page of global search results (LOT-046).
public struct GlobalSearchResult: Sendable, Equatable {
    /// The URL the page was served from.
    public var url: URL
    /// The rows and the pager (forum-relative paths for `GlobalSearchFlow.page(atPath:)`); no row and HFR's notice when
    /// nothing matched (`R50c`).
    public var page: TopicListPage

    /// Creates a result.
    public init(url: URL, page: TopicListPage) {
        self.url = url
        self.page = page
    }
}
