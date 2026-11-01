/// One batch of filtered messages: the pages from `startPage` to `endPage`, read in order.
public struct FilteredPostsBatch: Sendable, Equatable {
    /// The messages kept, in page order.
    public let posts: [FilteredPost]
    /// The first page read.
    public let startPage: Int
    /// The last page read; equal to `startPage` when one page was enough, or when the first request was already past
    /// the topic's end (then nothing was read and `maxPage` is below `startPage`).
    public let endPage: Int
    /// The topic's last page, as the last page read shows it.
    public let maxPage: Int
    /// True when `endPage` is the topic's last page: there is nothing left to filter.
    public let isFinished: Bool

    /// Where the next batch starts (legacy "Résultats suivants": `endPage + 1`); nil once the topic is finished.
    public var resumePage: Int? {
        isFinished ? nil : endPage + 1
    }
}
