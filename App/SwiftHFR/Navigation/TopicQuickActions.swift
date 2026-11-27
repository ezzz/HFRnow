import Foundation
import HFRModels

/// A topic page to open from a row's menu, and where on it.
struct TopicOpening: Hashable, Sendable {
    /// The page, and the message its link names.
    var target: ReaderTarget
    /// Opens at the page's last message (legacy `initialScroll: .bottom`) instead of the target's anchor or the top.
    var atLastMessage = false
}

// Port of HFRswift/Swift/Common.swift (TopicListRowView quick actions, `:2875-2893, 2984-3093`; TopicQuickActionPolicy
// `:2261-2366`) @ 2440d79. Differences: GAP-028; a link is read by LOT-095's router (`ReaderTarget(link:fallbackTopic:)`), and
// a topic number known from the row builds the page itself, so a resume link never stands for page 1.
/// The legacy quick actions of a topic row's menu (LOT-125): Première page, Dernière page, Dernière réponse, Page numéro…
/// and Copier le lien. Every list of this lot shows the five (legacy defaults for the forum and favourites contexts).
enum TopicQuickActions {
    /// "Première page", at its top (legacy `aURLOfFirstPage ?? aURL`).
    static func firstPage(of topic: TopicSummary) -> TopicOpening? {
        page(1, of: topic)
    }

    /// "Dernière page", at its top (legacy `aURLOfLastPage ?? aURL`): the row's last-page link, page taken from the link.
    static func lastPage(of topic: TopicSummary) -> TopicOpening? {
        if let target = ReaderTarget(link: topic.lastPagePath, fallbackTopic: topic.topicID), target.numreponse == nil {
            return TopicOpening(target: target.atPage(target.page))
        }
        return page(topic.pageCount, of: topic)
    }

    /// "Dernière réponse", at the page's last message (legacy `lastReplyURL`, `initialScroll: .bottom`). The flags list
    /// ("Drapeaux & Favoris", legacy context `.favorites`) opens the last page; the other lists the last post's link, else
    /// the last page.
    static func lastReply(of topic: TopicSummary, in source: TopicSource) -> TopicOpening? {
        lastReply(of: topic, usingLastPost: source != .flagged)
    }

    /// "Dernière réponse" of a list that is no topic list (search results: legacy `lastReplyURL`, last post first).
    static func lastReply(of topic: TopicSummary, usingLastPost: Bool) -> TopicOpening? {
        if usingLastPost, let path = topic.lastPost?.path,
           let target = ReaderTarget(link: path, fallbackTopic: topic.topicID) {
            return TopicOpening(target: target, atLastMessage: true)
        }
        guard var opening = lastPage(of: topic) else { return nil }
        opening.atLastMessage = true
        return opening
    }

    /// "Dernière correspondance" (search results): the page and message the search matched, at the match's anchor (legacy
    /// `searchMatchURL`, `initialScroll: .top`). Nil when the row names no match.
    static func searchMatch(of topic: TopicSummary) -> TopicOpening? {
        guard let hit = topic.searchHit,
              let target = ReaderTarget(link: hit.postPath, fallbackTopic: topic.topicID) else { return nil }
        return TopicOpening(target: target)
    }

    /// The pages "Page numéro…" accepts (legacy `1...maxTopicPageValue`).
    static func pages(of topic: TopicSummary) -> ClosedRange<Int> { 1...topic.pageCount }

    /// The page "Page numéro…" proposes first (legacy `curTopicPage`, at least 1).
    static func suggestedPage(of topic: TopicSummary) -> Int {
        min(max(topic.currentPage ?? 1, 1), topic.pageCount)
    }

    /// "Page numéro…": `number` at its top; nil outside the topic's pages (legacy ignores it).
    static func page(_ number: Int, of topic: TopicSummary) -> TopicOpening? {
        guard pages(of: topic).contains(number) else { return nil }
        if let topicID = topic.topicID { return TopicOpening(target: ReaderTarget(source: .topic(topicID), page: number)) }
        guard let target = ReaderTarget(link: topic.firstPagePath ?? topic.path) else { return nil }
        return TopicOpening(target: target.atPage(number))
    }

    /// "Copier le lien": the absolute link of the first page (legacy `copyLink`: first page, else the row's link, else the
    /// last page, else the last post); nil when none is a forum link.
    static func link(of topic: TopicSummary) -> URL? {
        let candidates = [topic.firstPagePath, topic.path, topic.lastPagePath, topic.lastPost?.path]
        return candidates.lazy.compactMap { $0.flatMap(ReaderTarget.forumURL) }.first
    }
}

/// One entry of a row menu that is not a topic list's: what it does when chosen.
enum TopicRowMenuEntry: Hashable {
    case searchMatch(TopicOpening)
    case firstPage(TopicOpening)
    case lastPage(TopicOpening)
    case lastReply(TopicOpening)
    /// Asks for a page number, then `TopicQuickActions.page(_:of:)`.
    case pagePrompt
    case copyLink(URL)
}

/// The lists whose rows carry the quick actions besides the topic lists (legacy `TopicOpenContext`).
enum TopicRowMenuContext: Equatable {
    /// Legacy `.privateMessages`: no "Dernière réponse" (`showOpenLastReply: false`, `Common.swift:2587-2625` @ 87fe0d1c).
    case privateMessages
    /// Legacy `.globalSearch`: "Dernière correspondance" first, then the five (`Common.swift:3558-3600` @ 87fe0d1c).
    case globalSearch
}

extension TopicQuickActions {
    /// The entries a `context` row offers, in legacy order. An entry that cannot run (no link to open, no match) is left out, not
    /// dimmed (HIG, #1162); "Page numéro…" needs a page it can build (a topic number or a link).
    /// Later entries of the MP menu (#676: "Marquer non lu", "Supprimer") follow these in the view, after a divider.
    static func menu(of topic: TopicSummary, in context: TopicRowMenuContext) -> [TopicRowMenuEntry] {
        var entries: [TopicRowMenuEntry] = []
        if context == .globalSearch, let opening = searchMatch(of: topic) { entries.append(.searchMatch(opening)) }
        if let opening = firstPage(of: topic) { entries.append(.firstPage(opening)) }
        if let opening = lastPage(of: topic) { entries.append(.lastPage(opening)) }
        if context == .globalSearch, let opening = lastReply(of: topic, usingLastPost: true) { entries.append(.lastReply(opening)) }
        if page(suggestedPage(of: topic), of: topic) != nil { entries.append(.pagePrompt) }
        if let link = link(of: topic) { entries.append(.copyLink(link)) }
        return entries
    }
}
