//
//  SidebarPrivateMessageItem.swift
//  HFRswift
//

import Foundation

/// A private message as a sidebar entry, opened like the Messages list does (last page / post).
struct SidebarPrivateMessageItem: Identifiable {
    let id: String
    let title: String
    let isUnread: Bool
    let topic: Topic
    let page: Int
    let maxPage: Int

    init(topic source: Topic) {
        let rawTitle = (source._aTitle ?? "Message").trimmingCharacters(in: .whitespacesAndNewlines)
        let unreadPrefix = "[non lu]"
        let hasUnreadPrefix = rawTitle.lowercased().hasPrefix(unreadPrefix)
        let cleanTitle = hasUnreadPrefix
            ? String(rawTitle.dropFirst(unreadPrefix.count)).trimmingCharacters(in: .whitespaces)
            : rawTitle
        let interlocutor = source.aAuthorOrInter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = interlocutor.isEmpty || interlocutor.localizedCaseInsensitiveContains("multiples")
            ? cleanTitle
            : "\(interlocutor) · \(cleanTitle)"
        isUnread = hasUnreadPrefix || !source.isViewed

        let decision = TopicOpenPolicy.defaultDecision(for: source, context: .privateMessages)
        let url = decision.preferredURL ?? source.aURL ?? ""
        let resolvedPage = max(TopicPageURLRouting.pageNumber(from: url) ?? decision.fallbackPage, 1)
        let resolvedMax = max(Int(source.maxTopicPage), resolvedPage)

        let destination = Topic()
        destination._aTitle = cleanTitle
        destination.aURL = url
        destination.aURLOfFirstPage = source.aURLOfFirstPage
        destination.aURLOfLastPost = source.aURLOfLastPost
        destination.aURLOfLastPage = source.aURLOfLastPage ?? url
        destination.aURLOfFlag = source.aURLOfFlag
        destination.aAuthorOrInter = source.aAuthorOrInter
        destination.postID = source.postID
        destination.catID = source.catID
        destination.curTopicPage = Int32(resolvedPage)
        destination.maxTopicPage = Int32(resolvedMax)

        id = url.isEmpty ? "mp-\(source.postID)-\(cleanTitle)" : url
        topic = destination
        page = resolvedPage
        maxPage = resolvedMax
    }
}
