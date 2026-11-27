import Foundation
import HFRModels
import HFRParsing
import HFRStorage

extension MPSegment {
    /// Switch label.
    var title: String {
        switch self {
        case .all: "Tous"
        case .oneToOne: "MP"
        case .group: "MP multiples"
        }
    }
}

/// A page of the private message list ready to display.
struct MessageListContent: Sendable, Equatable {
    /// Conversations in page order. Each row keeps its own unread state and group flag, so a later lot can split or count
    /// them without fetching again (LOT-171).
    var threads: [PrivateMessageThread]
    /// Page shown (1-based).
    var page: Int
    /// A next page exists.
    var hasNext: Bool
    /// HFR's last page (`navigation.last`, a lower bound when HFR's pager is a window), at least `page`: « page x / y » of the pager.
    var pageCount: Int
    /// `PageNavigation.isExact` (HFR's pager is a window); « page x / y+ » when false.
    var pageCountIsExact: Bool
    /// Why there is no row, when there is none.
    var emptyReason: EmptyReason?
    /// The page's "new private message" link (`md_btn_new_topic`, `R13a`), resolved on the forum; nil when absent.
    var newMessageURL: URL?

    /// Conversations of this page the member has not read; the mailbox total is the badge's (home page), not this.
    var unreadCount: Int { threads.filter(\.isUnread).count }

    init(
        threads: [PrivateMessageThread], page: Int, hasNext: Bool, pageCount: Int? = nil, pageCountIsExact: Bool = true,
        emptyReason: EmptyReason?, newMessageURL: URL? = nil
    ) {
        self.threads = threads
        self.page = page
        self.pageCount = max(pageCount ?? page, page)
        self.pageCountIsExact = pageCountIsExact
        self.hasNext = hasNext
        self.emptyReason = emptyReason
        self.newMessageURL = newMessageURL
    }

    init(page list: PrivateMessageListPage) {
        threads = list.threads
        page = list.navigation.current
        hasNext = list.navigation.nextPath != nil
        pageCount = max(list.navigation.last, list.navigation.current + (list.navigation.nextPath == nil ? 0 : 1))
        pageCountIsExact = list.navigation.isExact || list.navigation.nextPath == nil
        emptyReason = list.threads.isEmpty ? .nothing : nil
        newMessageURL = list.newMessagePath.flatMap { HFRURL.absolute($0) }
    }

    /// What a logged-out visitor sees: no request is made, the list asks for a login.
    static let signedOut = MessageListContent(threads: [], page: 1, hasNext: false, emptyReason: .signInRequired(nil))
}
