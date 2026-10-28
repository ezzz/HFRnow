import Foundation
import HFRModels

/// HFR's confirmation of a flag write.
public struct TopicFlagResult: Sendable, Equatable {
    /// The write HFR confirmed.
    public var action: TopicFlagAction
    /// The topic the write was for, read from the link that was followed.
    public var topic: TopicID
    /// HFR's sentence, for example "Favori positionné avec succès".
    public var message: String
    /// The page HFR refreshes to (the sub-forum list after `addflag`, the favourites of the category after `delflag`).
    /// Always `https` on `forum.hardware.fr` (LOT-037).
    public var refreshURL: URL

    /// Creates a result.
    public init(action: TopicFlagAction, topic: TopicID, message: String, refreshURL: URL) {
        self.action = action
        self.topic = topic
        self.message = message
        self.refreshURL = refreshURL
    }
}

/// A topic page read with the account's session, which moved the account's read flag (HFR-PROTOCOL §7 E25).
public struct TopicReadMark: Sendable, Equatable {
    /// The topic read.
    public var topic: TopicID
    /// The page HFR served: the one asked for, or the last page when the one asked for is past it (`R24`).
    public var page: Int
    /// Number of pages of the topic.
    public var pageCount: Int
    /// The URL HFR finally served the page from (the canonical `…-sujet_<post>_<page>.htm`).
    public var pageURL: URL

    /// Creates a read mark.
    public init(topic: TopicID, page: Int, pageCount: Int, pageURL: URL) {
        self.topic = topic
        self.page = page
        self.pageCount = pageCount
        self.pageURL = pageURL
    }
}
