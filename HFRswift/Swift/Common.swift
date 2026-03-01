//
//  Common.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import Foundation
import SwiftUI
import UIKit

extension Favorite: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension Topic: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension Forum: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

enum RootTabIdentifier: Int {
    case categories = 0
    case favorites = 1
    case messages = 2
    case more = 3
}

extension Notification.Name {
    static let rootTabReselected = Notification.Name("HFRswiftRootTabReselectedNotification")
}

enum AppThemeResolver {
    private static let autoThemeKey = "auto_theme"
    private static let manualThemeKey = "theme"
    private static let autoThemeIOSValue = 3
    private static let darkThemeValue = 1

    static var usesSystemColorScheme: Bool {
        UserDefaults.standard.integer(forKey: autoThemeKey) == autoThemeIOSValue
    }

    static func preferredColorScheme() -> ColorScheme? {
        guard !usesSystemColorScheme else { return nil }
        let manualTheme = UserDefaults.standard.integer(forKey: manualThemeKey)
        return manualTheme == darkThemeValue ? .dark : .light
    }

    static func currentColorScheme() -> ColorScheme {
        resolvedColorScheme()
    }

    static func resolvedColorScheme(systemColorScheme: ColorScheme? = nil) -> ColorScheme {
        if usesSystemColorScheme {
            return systemColorScheme ?? currentSystemColorScheme()
        }
        return preferredColorScheme() ?? .light
    }

    private static func currentSystemColorScheme() -> ColorScheme {
        let style =
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: { $0.isKeyWindow })?
                .traitCollection.userInterfaceStyle
            ?? UIScreen.main.traitCollection.userInterfaceStyle
        return style == .dark ? .dark : .light
    }
}

typealias FavoritesLoadCompletion = ([Favorite]?, Error?) -> Void
typealias TopicsLoadCompletion = ([Topic]?, Error?) -> Void
typealias ForumsLoadCompletion = ([Forum]?, Error?) -> Void

protocol FavoritesLoading {
    func fetchFavorites(completion: @escaping FavoritesLoadCompletion)
}

final class ObjCFavoritesLoader: FavoritesLoading {
    private let controller: FavoritesTableViewController

    init(controller: FavoritesTableViewController = FavoritesTableViewController()) {
        self.controller = controller
    }

    func fetchFavorites(completion: @escaping FavoritesLoadCompletion) {
        controller.fetchContent { favorites, error in
            completion(favorites, error)
        }
    }
}

protocol MPTopicsLoading {
    func fetchTopics(completion: @escaping TopicsLoadCompletion)
}

final class ObjCMPTopicsLoader: MPTopicsLoading {
    private let controller: HFRMPViewController

    init(controller: HFRMPViewController = HFRMPViewController()) {
        self.controller = controller
    }

    func fetchTopics(completion: @escaping TopicsLoadCompletion) {
        controller.loadViewIfNeeded()
        controller.fetchContent { topics, error in
            completion(topics, error)
        }
    }
}

protocol ForumsLoading {
    func fetchForums(completion: @escaping ForumsLoadCompletion)
}

final class ObjCForumsLoader: ForumsLoading {
    private let controller: ForumsTableViewController

    init(controller: ForumsTableViewController = ForumsTableViewController()) {
        self.controller = controller
    }

    func fetchForums(completion: @escaping ForumsLoadCompletion) {
        controller.fetchContent { forums, error in
            completion(forums, error)
        }
    }
}

enum TopicListFlag: Int {
    case all = 0
    case favorites = 1
    case tracked = 2
    case read = 3
}

protocol ForumTopicsLoading {
    func fetchTopics(for forum: Forum, flag: TopicListFlag, completion: @escaping TopicsLoadCompletion)
}

final class ObjCForumTopicsLoader: ForumTopicsLoading {
    private let controller: TopicsTableViewController

    init(controller: TopicsTableViewController = TopicsTableViewController()) {
        self.controller = controller
    }

    func fetchTopics(for forum: Forum, flag: TopicListFlag, completion: @escaping TopicsLoadCompletion) {
        controller.fetchContent(for: forum, flagIndex: flag.rawValue) { topics, error in
            completion(topics, error)
        }
    }
}

struct TopicPageMessageActions: Equatable {
    let quoteURL: URL?
    let profileURL: URL?
    let privateMessageURL: URL?
    let postID: String?
}

struct TopicPageContent {
    let html: String
    let topicAnswerURL: URL?
    let messageActionsByIndex: [Int: TopicPageMessageActions]

    init(
        html: String,
        topicAnswerURL: URL?,
        messageActionsByIndex: [Int: TopicPageMessageActions] = [:]
    ) {
        self.html = html
        self.topicAnswerURL = topicAnswerURL
        self.messageActionsByIndex = messageActionsByIndex
    }
}

enum TopicPageLoadingError: LocalizedError {
    case missingHTML

    var errorDescription: String? {
        switch self {
        case .missingHTML:
            return "No HTML returned for topic page"
        }
    }
}

protocol TopicPageLoading {
    func fetchTopicPage(url: String, anchor: String?, completion: @escaping (Result<TopicPageContent, Error>) -> Void)
}

final class ObjCTopicPageLoader: TopicPageLoading {
    private enum MessageActionKey {
        static let quoteURL = "quoteURL"
        static let profileURL = "profileURL"
        static let privateMessageURL = "privateMessageURL"
        static let postID = "postID"
    }

    private let controller: MessagesTableViewController

    init(controller: MessagesTableViewController = MessagesTableViewController()) {
        self.controller = controller
    }

    func fetchTopicPage(url: String, anchor: String?, completion: @escaping (Result<TopicPageContent, Error>) -> Void) {
        controller.fetchContent(forTopicURL: url, anchor: anchor) { html, topicAnswerURL, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let html else {
                completion(.failure(TopicPageLoadingError.missingHTML))
                return
            }
            let answerURL = topicAnswerURL.flatMap(URL.init(string:))
            let messageActionsByIndex = self.extractMessageActionsByIndex()
            completion(.success(TopicPageContent(
                html: html,
                topicAnswerURL: answerURL,
                messageActionsByIndex: messageActionsByIndex
            )))
        }
    }

    private func extractMessageActionsByIndex() -> [Int: TopicPageMessageActions] {
        guard let rawEntries = controller.swiftMessageActionsByIndex() as? [AnyHashable: Any] else {
            return [:]
        }

        var result: [Int: TopicPageMessageActions] = [:]
        for (rawKey, rawValue) in rawEntries {
            let index: Int
            if let number = rawKey as? NSNumber {
                index = number.intValue
            } else if let string = rawKey as? String, let parsed = Int(string) {
                index = parsed
            } else {
                continue
            }

            guard let entry = rawValue as? [AnyHashable: Any] else {
                continue
            }

            let actions = TopicPageMessageActions(
                quoteURL: urlValue(in: entry, key: MessageActionKey.quoteURL),
                profileURL: urlValue(in: entry, key: MessageActionKey.profileURL),
                privateMessageURL: urlValue(in: entry, key: MessageActionKey.privateMessageURL),
                postID: stringValue(in: entry, key: MessageActionKey.postID)
            )

            if actions.quoteURL != nil || actions.profileURL != nil || actions.privateMessageURL != nil || actions.postID != nil {
                result[index] = actions
            }
        }

        return result
    }

    private func urlValue(in dictionary: [AnyHashable: Any], key: String) -> URL? {
        guard let rawValue = stringValue(in: dictionary, key: key) else {
            return nil
        }
        return URL(string: rawValue)
    }

    private func stringValue(in dictionary: [AnyHashable: Any], key: String) -> String? {
        guard let rawValue = dictionary[key] as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct TopicPageRenderOutput {
    let fileURL: URL?
    let readAccessURL: URL?
}

enum TopicPageRenderingError: LocalizedError {
    case offlineStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .offlineStorageUnavailable:
            return "OfflineStorage is unavailable"
        }
    }
}

protocol TopicPageRendering {
    func render(html: String) throws -> TopicPageRenderOutput
}

struct OfflineStorageTopicPageRenderer: TopicPageRendering {
    func render(html: String) throws -> TopicPageRenderOutput {
        guard let offlineStorage = OfflineStorage.shared() else {
            throw TopicPageRenderingError.offlineStorageUnavailable
        }
        guard let cacheDirectoryURL = offlineStorage.cacheURL() else {
            throw TopicPageRenderingError.offlineStorageUnavailable
        }
        let fileURL = cacheDirectoryURL
            .appendingPathComponent("topic-\(UUID().uuidString)")
            .appendingPathExtension("htm")
        try html.write(to: fileURL, atomically: false, encoding: .utf8)
        return TopicPageRenderOutput(fileURL: fileURL, readAccessURL: cacheDirectoryURL)
    }
}

enum MessageWebNavigationType {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other
    case unknown
}

enum MessageWebInitialScroll: Equatable {
    case top
    case bottom
}

enum MessageWebPopupSource: Equatable {
    case avatar
    case message
}

struct MessageWebPopupPayload: Equatable {
    let source: MessageWebPopupSource
    let messageIndex: Int
    let yOffset: Int
    let xOffset: Int?
}

struct MessageWebSmileyPayload: Equatable {
    let code: String
    let imageURL: String
}

enum MessageWebAction: Equatable {
    case allowNavigation
    case ignore
    case loadPage(Int, MessageWebInitialScroll)
    case refreshCurrentPage
    case showPopupMenu(MessageWebPopupPayload)
    case manageSmileyFavorite(MessageWebSmileyPayload)
    case openInternalTopic(URL)
    case openExternalURL(URL)
}

protocol MessageWebActionHandling {
    func action(
        for url: URL,
        navigationType: MessageWebNavigationType,
        currentPage: Int,
        maxPage: Int
    ) -> MessageWebAction
}

struct MessageWebActionHandler: MessageWebActionHandling {
    private enum Constants {
        static let autoScheme = "oijlkajsdoihjlkjasdoauto"
        static let touchScheme = "oijlkajsdoihjlkjasdotouch"
        static let preloadedScheme = "oijlkajsdoihjlkjasdopreloaded"
        static let loadedScheme = "oijlkajsdoihjlkjasdoloaded"
        static let refreshScheme = "oijlkajsdoihjlkjasdorefresh"
        static let popupAvatarScheme = "oijlkajsdoihjlkjasdopopupavatar"
        static let popupMessageScheme = "oijlkajsdoihjlkjasdopopupmessage"
        static let imageBrowserScheme = "oijlkajsdoihjlkjasdoimbrows"
        static let smileyScheme = "oijlkajsdoihjlkjasdosmiley"
    }

    func action(
        for url: URL,
        navigationType: MessageWebNavigationType,
        currentPage: Int,
        maxPage: Int
    ) -> MessageWebAction {
        let scheme = (url.scheme ?? "").lowercased()

        if navigationType == .other, url.fragment == "bas" {
            return .ignore
        }

        if scheme == Constants.autoScheme {
            guard let pageAction = autoPagingAction(for: url, currentPage: currentPage, maxPage: maxPage) else {
                return .ignore
            }
            return pageAction
        }

        if scheme == Constants.refreshScheme {
            return .refreshCurrentPage
        }

        if let popupAction = popupAction(for: url, scheme: scheme) {
            return popupAction
        }

        if let imageBrowserAction = imageBrowserAction(for: url, scheme: scheme) {
            return imageBrowserAction
        }

        if let smileyAction = smileyAction(for: url, scheme: scheme) {
            return smileyAction
        }

        if isIgnoredCustomScheme(scheme) {
            return .ignore
        }

        if navigationType == .linkActivated {
            if isForumTopicURL(url) || scheme == "file" {
                return .openInternalTopic(url)
            }
            if scheme == "http" || scheme == "https" {
                return .openExternalURL(url)
            }
        }

        return .allowNavigation
    }

    private func autoPagingAction(for url: URL, currentPage: Int, maxPage: Int) -> MessageWebAction? {
        let boundedMaxPage = max(maxPage, 1)
        let boundedCurrentPage = min(max(currentPage, 1), boundedMaxPage)
        let command = (url.host ?? url.lastPathComponent).lowercased()

        switch command {
        case "begin":
            guard boundedCurrentPage != 1 else { return nil }
            return .loadPage(1, .top)
        case "previous":
            guard boundedCurrentPage > 1 else { return nil }
            return .loadPage(boundedCurrentPage - 1, .bottom)
        case "next":
            guard boundedCurrentPage < boundedMaxPage else { return nil }
            return .loadPage(boundedCurrentPage + 1, .top)
        case "end":
            guard boundedCurrentPage != boundedMaxPage else { return nil }
            return .loadPage(boundedMaxPage, .bottom)
        default:
            return nil
        }
    }

    private func popupAction(for url: URL, scheme: String) -> MessageWebAction? {
        switch scheme {
        case Constants.popupAvatarScheme:
            guard let payload = popupPayload(for: url, source: .avatar) else {
                return .ignore
            }
            return .showPopupMenu(payload)
        case Constants.popupMessageScheme:
            guard let payload = popupPayload(for: url, source: .message) else {
                return .ignore
            }
            return .showPopupMenu(payload)
        default:
            return nil
        }
    }

    private func popupPayload(for url: URL, source: MessageWebPopupSource) -> MessageWebPopupPayload? {
        var values: [Int] = []
        if let host = url.host, let hostValue = Int(host) {
            values.append(hostValue)
        }
        values.append(contentsOf: url.pathComponents.compactMap(Int.init))

        guard let messageIndex = values.last else {
            return nil
        }
        let yOffset = values.dropLast().last ?? 0
        let xOffset = values.count >= 3 ? values.dropLast(2).last : nil
        return MessageWebPopupPayload(
            source: source,
            messageIndex: messageIndex,
            yOffset: yOffset,
            xOffset: xOffset
        )
    }

    private func isIgnoredCustomScheme(_ scheme: String) -> Bool {
        scheme == Constants.touchScheme ||
            scheme == Constants.preloadedScheme ||
            scheme == Constants.loadedScheme
    }

    private func imageBrowserAction(for url: URL, scheme: String) -> MessageWebAction? {
        guard scheme == Constants.imageBrowserScheme else {
            return nil
        }

        guard let imageURL = decodeEmbeddedURL(from: url, expectedScheme: Constants.imageBrowserScheme) else {
            return .ignore
        }

        return .openExternalURL(imageURL)
    }

    private func smileyAction(for url: URL, scheme: String) -> MessageWebAction? {
        guard scheme == Constants.smileyScheme else {
            return nil
        }

        let prefix = "\(Constants.smileyScheme)://smileycode/"
        let absolute = url.absoluteString
        guard absolute.lowercased().hasPrefix(prefix) else {
            return .ignore
        }

        let remainder = String(absolute.dropFirst(prefix.count))
        guard let separatorIndex = remainder.firstIndex(of: "/") else {
            return .ignore
        }

        let encodedCode = String(remainder[..<separatorIndex])
        let encodedURL = String(remainder[remainder.index(after: separatorIndex)...])

        let decodedCode = (encodedCode.removingPercentEncoding ?? encodedCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedCode.isEmpty else {
            return .ignore
        }

        let normalizedCode = decodedCode.hasPrefix("[:") ? decodedCode : "[:\(decodedCode)]"

        guard let smileyURL = decodeEmbeddedURL(encodedURL) else {
            return .ignore
        }

        return .manageSmileyFavorite(
            MessageWebSmileyPayload(
                code: normalizedCode,
                imageURL: smileyURL.absoluteString
            )
        )
    }

    private func decodeEmbeddedURL(from url: URL, expectedScheme: String) -> URL? {
        let prefix = "\(expectedScheme)://"
        let absolute = url.absoluteString
        guard absolute.lowercased().hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(absolute.dropFirst(prefix.count))
        guard let separatorIndex = remainder.firstIndex(of: "/") else {
            return nil
        }

        let encodedURL = String(remainder[remainder.index(after: separatorIndex)...])
        return decodeEmbeddedURL(encodedURL)
    }

    private func decodeEmbeddedURL(_ encodedURL: String) -> URL? {
        var decoded = encodedURL
        for _ in 0..<2 {
            if let nextDecoded = decoded.removingPercentEncoding, nextDecoded != decoded {
                decoded = nextDecoded
            } else {
                break
            }
        }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private func isForumTopicURL(_ url: URL) -> Bool {
        guard (url.host ?? "").lowercased() == "forum.hardware.fr" else {
            return false
        }
        let firstPathComponent = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        return firstPathComponent == "forum2.php" || firstPathComponent == "hfr"
    }
}

struct TopicQuickActionsConfiguration {
    var showOpenFirstPage = true
    var showOpenLastPage = true
    var showOpenLastReply = true
    var showOpenPagePicker = true
    var showCopyLink = true
}

enum TopicOpenContext: Equatable {
    case generic
    case forum(selectedFlag: TopicListFlag)
    case favorites
    case messages
}

struct TopicOpenPolicy {
    struct Decision {
        let preferredURL: String?
        let fallbackPage: Int
    }

    static func defaultDecision(for topic: Topic, context: TopicOpenContext) -> Decision {
        let currentPage = max(Int(topic.curTopicPage), 1)
        let maxPage = max(Int(topic.maxTopicPage), 1)

        switch context {
        case .forum(let selectedFlag):
            if let flaggedURL = nonEmptyString(topic.aURLOfFlag) {
                return Decision(preferredURL: flaggedURL, fallbackPage: currentPage)
            }
            if selectedFlag != .all {
                return Decision(
                    preferredURL: nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURL),
                    fallbackPage: maxPage
                )
            }
            return Decision(
                preferredURL: nonEmptyString(topic.aURL),
                fallbackPage: currentPage
            )
        case .favorites:
            if let flaggedURL = nonEmptyString(topic.aURLOfFlag) {
                return Decision(preferredURL: flaggedURL, fallbackPage: currentPage)
            }
            return Decision(
                preferredURL: nonEmptyString(topic.aURL),
                fallbackPage: currentPage
            )
        case .messages:
            return Decision(
                preferredURL: nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURL),
                fallbackPage: maxPage
            )
        case .generic:
            return Decision(
                preferredURL: nonEmptyString(topic.aURL) ?? nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURLOfLastPage),
                fallbackPage: currentPage
            )
        }
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private struct TopicNavigationTarget {
    let topic: Topic
    let page: Int
    let maxPage: Int
    let openedURL: String?
    let initialScroll: WebView.InitialScroll?
}

struct TopicListRowView: View {
    let topic: Topic
    let isVisited: Bool
    var titleFont: Font = .headline
    var showUnreadBadge = false
    var showUnreadBadgeWhenZero = false
    var leadingBottomText: String?
    var trailingBottomText: String?
    var openContext: TopicOpenContext = .generic
    var quickActions = TopicQuickActionsConfiguration()
    var onOpen: ((String?) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    @State private var navigateToTarget = false
    @State private var navigationTarget: TopicNavigationTarget?
    @State private var isPagePickerPresented = false
    @State private var pagePickerInput = ""

    private var unreadCount: Int {
        max(Int(topic.maxTopicPage - topic.curTopicPage), 0)
    }

    private var titleText: String {
        topic._aTitle ?? "Sans titre"
    }

    private var maxTopicPageValue: Int {
        max(Int(topic.maxTopicPage), 1)
    }

    private var currentPageValue: Int {
        max(Int(topic.curTopicPage), 1)
    }

    private var defaultURL: String? {
        nonEmptyString(topic.aURL) ?? nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURLOfLastPage)
    }

    private var firstPageURL: String? {
        nonEmptyString(topic.aURLOfFirstPage) ?? nonEmptyString(topic.aURL)
    }

    private var lastPageURL: String? {
        nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURL)
    }

    private var copyURL: String? {
        nonEmptyString(topic.aURLOfFirstPage) ?? nonEmptyString(topic.aURL) ?? nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURLOfLastPost)
    }

    private var unreadBadgeTextColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var unreadBadgeBackgroundColor: Color {
        if colorScheme == .dark {
            return isVisited ? .white.opacity(0.55) : .white.opacity(0.78)
        }
        return isVisited ? .secondary.opacity(0.5) : .secondary
    }

    private func nonEmptyString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func pageNumber(from urlString: String?) -> Int? {
        guard let urlString = nonEmptyString(urlString) else { return nil }

        if
            let components = URLComponents(string: urlString),
            let pageValue = components.queryItems?.first(where: { $0.name == "page" })?.value,
            let page = Int(pageValue),
            page > 0
        {
            return page
        }

        let patterns = [
            "page=(\\d+)",
            "_(\\d+)\\.htm"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
            guard
                let match = regex.firstMatch(in: urlString, options: [], range: range),
                match.numberOfRanges >= 2,
                let captureRange = Range(match.range(at: 1), in: urlString),
                let page = Int(urlString[captureRange]),
                page > 0
            else {
                continue
            }
            return page
        }

        return nil
    }

    private func replacingPage(in urlString: String, page: Int) -> String {
        var updated = urlString
        if let range = updated.range(of: "page=\\d+", options: .regularExpression) {
            updated.replaceSubrange(range, with: "page=\(page)")
            return updated
        }
        if let range = updated.range(of: "_\\d+\\.htm", options: .regularExpression) {
            updated.replaceSubrange(range, with: "_\(page).htm")
            return updated
        }
        if var components = URLComponents(string: updated) {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "page", value: "\(page)"))
            components.queryItems = queryItems
            components.fragment = nil
            return components.string ?? updated
        }
        return updated
    }

    private func navigationTopic(url: String, page: Int, maxPage: Int) -> Topic {
        let destination = Topic()
        destination._aTitle = topic._aTitle
        destination.aURL = url
        destination.aURLOfFirstPage = topic.aURLOfFirstPage
        destination.aURLOfFlag = topic.aURLOfFlag
        destination.aTypeOfFlag = topic.aTypeOfFlag
        destination.aURLOfLastPost = topic.aURLOfLastPost
        destination.aURLOfLastPage = nonEmptyString(topic.aURLOfLastPage) ?? url
        destination.curTopicPage = Int32(page)
        destination.maxTopicPage = Int32(max(maxPage, page))
        destination.isViewed = topic.isViewed
        destination.isPoll = topic.isPoll
        destination.isClosed = topic.isClosed
        destination.isSticky = topic.isSticky
        destination.isSuperFavorite = topic.isSuperFavorite
        return destination
    }

    private func makeNavigationTarget(
        preferredURL: String?,
        fallbackPage: Int? = nil,
        initialScroll: WebView.InitialScroll? = nil
    ) -> TopicNavigationTarget? {
        guard let openedURL = nonEmptyString(preferredURL) ?? defaultURL else {
            return nil
        }

        let resolvedPage = max(pageNumber(from: openedURL) ?? fallbackPage ?? currentPageValue, 1)
        let resolvedMaxPage = max(maxTopicPageValue, resolvedPage)
        let destinationTopic = navigationTopic(url: openedURL, page: resolvedPage, maxPage: resolvedMaxPage)

        return TopicNavigationTarget(
            topic: destinationTopic,
            page: resolvedPage,
            maxPage: resolvedMaxPage,
            openedURL: openedURL,
            initialScroll: initialScroll
        )
    }

    private func defaultOpenTarget() -> TopicNavigationTarget? {
        let decision = TopicOpenPolicy.defaultDecision(for: topic, context: openContext)
        return makeNavigationTarget(
            preferredURL: decision.preferredURL ?? defaultURL,
            fallbackPage: decision.fallbackPage
        )
    }

    private func openNavigationTarget(_ target: TopicNavigationTarget?) {
        guard let target else { return }
        navigationTarget = target
        navigateToTarget = true
    }

    private func openDefaultTopic() {
        openNavigationTarget(defaultOpenTarget())
    }

    private func openFirstPageAction() {
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: firstPageURL,
                fallbackPage: 1,
                initialScroll: .top
            )
        )
    }

    private func openLastPageAction() {
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: lastPageURL,
                fallbackPage: maxTopicPageValue,
                initialScroll: .top
            )
        )
    }

    private func openLastReplyAction() {
        let lastReplyURL = nonEmptyString(topic.aURLOfLastPage) ?? nonEmptyString(topic.aURLOfLastPost) ?? nonEmptyString(topic.aURL)
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: lastReplyURL,
                fallbackPage: maxTopicPageValue,
                initialScroll: .bottom
            )
        )
    }

    private func openPagePickerAction() {
        pagePickerInput = "\(currentPageValue)"
        isPagePickerPresented = true
    }

    private func submitPagePicker() {
        let trimmed = pagePickerInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let requestedPage = Int(trimmed),
            (1...maxTopicPageValue).contains(requestedPage)
        else {
            return
        }

        let baseURL = defaultURL
        let pageURL = baseURL.map { replacingPage(in: $0, page: requestedPage) }
        openNavigationTarget(
            makeNavigationTarget(
                preferredURL: pageURL,
                fallbackPage: requestedPage,
                initialScroll: .top
            )
        )
    }

    @ViewBuilder
    private var quickActionsMenuContent: some View {
        if quickActions.showOpenFirstPage, firstPageURL != nil {
            Button("Premiere page", systemImage: "backward.end") {
                openFirstPageAction()
            }
        }
        if quickActions.showOpenLastPage, lastPageURL != nil {
            Button("Derniere page", systemImage: "forward.end") {
                openLastPageAction()
            }
        }
        if quickActions.showOpenLastReply {
            Button("Derniere reponse", systemImage: "text.append") {
                openLastReplyAction()
            }
        }
        if quickActions.showOpenPagePicker {
            Button("Page numero...", systemImage: "number") {
                openPagePickerAction()
            }
        }
        if quickActions.showCopyLink, let copyURL {
            Button("Copier l'URL", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = copyURL
            }
        }
    }

    var body: some View {
        Button {
            openDefaultTopic()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(titleText)
                            .font(titleFont)
                            .foregroundStyle(isVisited ? .secondary : .primary)
                        Spacer()
                        if showUnreadBadge && (showUnreadBadgeWhenZero || unreadCount > 0) {
                            Text("\(unreadCount)")
                                .font(.caption2)
                                .bold()
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .frame(minWidth: 20)
                                .background(Capsule().fill(unreadBadgeBackgroundColor))
                                .foregroundStyle(unreadBadgeTextColor)
                        }
                    }

                    if leadingBottomText != nil || trailingBottomText != nil {
                        HStack {
                            if let leadingBottomText {
                                Text(leadingBottomText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let trailingBottomText {
                                Text(trailingBottomText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            quickActionsMenuContent
        }
        .background {
            NavigationLink(
                "",
                isActive: $navigateToTarget
            ) {
                if let navigationTarget {
                    MessagesView(
                        topic: navigationTarget.topic,
                        curPage: navigationTarget.page,
                        maxPage: navigationTarget.maxPage,
                        separatorNewMessages: true,
                        initialLoadScroll: navigationTarget.initialScroll
                    )
                    .onAppear {
                        onOpen?(navigationTarget.openedURL)
                    }
                    .toolbar(.hidden, for: .tabBar)
                } else {
                    EmptyView()
                }
            }
            .hidden()
            .allowsHitTesting(false)
        }
        .alert("Page numéro...", isPresented: $isPagePickerPresented) {
            TextField("1...\(maxTopicPageValue)", text: $pagePickerInput)
                .keyboardType(.numberPad)
            Button("Annuler", role: .cancel) {}
            Button("Aller") {
                submitPagePicker()
            }
        } message: {
            Text("Choisir une page entre 1 et \(maxTopicPageValue)")
        }
    }
}
