//
//  FavoritePostFilterService.swift
//  SuperHFRplus
//
//  Swift bridge for the legacy "Filtrer les posts" worker used from Favoris.
//

import Foundation

struct FavoritePostFilterProgress: Equatable {
    let currentPage: Int
    let maxPage: Int
    let resultCount: Int

    var statusText: String {
        let postText = resultCount <= 1 ? "\(resultCount) post" : "\(resultCount) posts"
        return "\(postText) | page \(currentPage)/\(max(maxPage, 1))"
    }
}

struct FavoritePostFilterResult {
    let html: String
    let messageActionsByIndex: [Int: TopicPageMessageActions]
    let startPage: Int
    let endPage: Int
    let maxPage: Int
    let isFinished: Bool
    let resultCount: Int

    var subtitle: String {
        let countText = resultCount == 1 ? "1 post" : "\(resultCount) posts"
        if startPage == endPage {
            return "\(countText) | \(startPage)"
        }
        return "\(countText) | \(startPage) a \(endPage)"
    }

    func markingFinished() -> FavoritePostFilterResult {
        FavoritePostFilterResult(
            html: html,
            messageActionsByIndex: messageActionsByIndex,
            startPage: startPage,
            endPage: endPage,
            maxPage: maxPage,
            isFinished: true,
            resultCount: resultCount
        )
    }
}

enum FavoritePostFilterError: LocalizedError {
    case workerUnavailable
    case renderUnavailable
    case missingHTML
    case noResult
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .workerUnavailable:
            return "Le filtre de posts n'est pas disponible."
        case .renderUnavailable:
            return "Le rendu des posts filtres n'est pas disponible."
        case .missingHTML:
            return "Aucun contenu n'a ete genere."
        case .noResult:
            return "Aucun post trouve."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

protocol FavoritePostFilteringServicing: AnyObject {
    func filterPosts(
        topic: Topic,
        startPage: Int?,
        progress: @escaping @MainActor (FavoritePostFilterProgress) -> Void
    ) async -> Result<FavoritePostFilterResult, FavoritePostFilterError>

    func cancel()
}

final class ObjCFavoritePostFilterService: FavoritePostFilteringServicing {
    private enum MessageActionKey {
        static let quoteURL = "quoteURL"
        static let profileURL = "profileURL"
        static let privateMessageURL = "privateMessageURL"
        static let avatarImagePath = "avatarImagePath"
        static let postID = "postID"
        static let editURL = "editURL"
        static let favoriteURL = "favoriteURL"
        static let alertURL = "alertURL"
        static let permalinkURL = "permalinkURL"
        static let authorName = "authorName"
        static let quoteJS = "quoteJS"
        static let isOwnMessage = "isOwnMessage"
        static let canBeFavorite = "canBeFavorite"
        static let isPrivateCategory = "isPrivateCategory"
        static let canAQ = "canAQ"
        static let canBookmark = "canBookmark"
        static let canDelete = "canDelete"
        static let topicID = "topicID"
        static let topicCategory = "topicCategory"
        static let topicTitle = "topicTitle"
    }

    private var activeWorker: NSObject?

    func filterPosts(
        topic: Topic,
        startPage: Int?,
        progress: @escaping @MainActor (FavoritePostFilterProgress) -> Void
    ) async -> Result<FavoritePostFilterResult, FavoritePostFilterError> {
        do {
            return .success(try await performFilter(topic: topic, startPage: startPage, progress: progress))
        } catch let error as FavoritePostFilterError {
            return .failure(error)
        } catch {
            return .failure(.underlying(error))
        }
    }

    func cancel() {
        guard let worker = activeWorker else { return }
        let selector = NSSelectorFromString("cancelSwiftFiltering")
        guard worker.responds(to: selector) else { return }
        typealias Function = @convention(c) (AnyObject, Selector) -> Void
        let implementation = worker.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(worker, selector)
    }

    private func performFilter(
        topic: Topic,
        startPage: Int?,
        progress: @escaping @MainActor (FavoritePostFilterProgress) -> Void
    ) async throws -> FavoritePostFilterResult {
        guard let worker = LegacyLoaderRuntime.instantiateController(named: "FilterPostsQuotes") else {
            throw FavoritePostFilterError.workerUnavailable
        }

        let selector = NSSelectorFromString("fetchFilteredPostsForTopic:startPage:progress:completion:")
        guard worker.responds(to: selector) else {
            throw FavoritePostFilterError.workerUnavailable
        }

        activeWorker = worker
        let startPageNumber = NSNumber(value: startPage ?? 0)

        return try await withCheckedThrowingContinuation { continuation in
            typealias ProgressBlock = @convention(block) (NSNumber, NSNumber, NSNumber) -> Void
            typealias CompletionBlock = @convention(block) (NSArray?, NSNumber?, NSNumber?, NSNumber, NSError?) -> Void
            typealias Function = @convention(c) (AnyObject, Selector, Topic, NSNumber, ProgressBlock?, CompletionBlock) -> Void

            let implementation = worker.method(for: selector)
            let function = unsafeBitCast(implementation, to: Function.self)
            let progressBlock: ProgressBlock = { currentPage, maxPage, resultCount in
                Task { @MainActor in
                    progress(FavoritePostFilterProgress(
                        currentPage: currentPage.intValue,
                        maxPage: maxPage.intValue,
                        resultCount: resultCount.intValue
                    ))
                }
            }
            let completionBlock: CompletionBlock = { items, resultStartPage, resultEndPage, finished, error in
                Task { @MainActor in
                    self.activeWorker = nil
                    if let error {
                        continuation.resume(throwing: FavoritePostFilterError.underlying(error))
                        return
                    }
                    let safeItems = items ?? []
                    guard safeItems.count > 0 else {
                        continuation.resume(throwing: FavoritePostFilterError.noResult)
                        return
                    }
                    do {
                        let rendered = try await self.renderFilteredPosts(
                            items: safeItems,
                            topic: topic,
                            startPage: resultStartPage?.intValue ?? max(startPage ?? Int(topic.curTopicPage), 1),
                            endPage: resultEndPage?.intValue ?? max(startPage ?? Int(topic.curTopicPage), 1),
                            finished: finished.boolValue,
                            maxPage: max(Int(topic.maxTopicPage), 1)
                        )
                        continuation.resume(returning: rendered)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            DispatchQueue.global(qos: .userInitiated).async {
                function(worker, selector, topic, startPageNumber, progressBlock, completionBlock)
            }
        }
    }

    @MainActor
    private func renderFilteredPosts(
        items: NSArray,
        topic: Topic,
        startPage: Int,
        endPage: Int,
        finished: Bool,
        maxPage: Int
    ) async throws -> FavoritePostFilterResult {
        guard let renderer = LegacyLoaderRuntime.instantiateController(named: "ObjCFilteredPostsRendererWorker") else {
            throw FavoritePostFilterError.renderUnavailable
        }

        let selector = NSSelectorFromString("renderFilteredPosts:topic:startPage:endPage:finished:completion:")
        guard renderer.responds(to: selector) else {
            throw FavoritePostFilterError.renderUnavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            typealias CompletionBlock = @convention(block) (NSString?, NSDictionary?, NSError?) -> Void
            typealias Function = @convention(c) (AnyObject, Selector, NSArray, Topic, NSNumber, NSNumber, NSNumber, CompletionBlock) -> Void
            let implementation = renderer.method(for: selector)
            let function = unsafeBitCast(implementation, to: Function.self)
            let block: CompletionBlock = { html, rawActions, error in
                if let error {
                    continuation.resume(throwing: FavoritePostFilterError.underlying(error))
                    return
                }
                guard let html = html as String?, !html.isEmpty else {
                    continuation.resume(throwing: FavoritePostFilterError.missingHTML)
                    return
                }
                continuation.resume(returning: FavoritePostFilterResult(
                    html: html,
                    messageActionsByIndex: Self.decodeMessageActions(from: rawActions),
                    startPage: startPage,
                    endPage: endPage,
                    maxPage: maxPage,
                    isFinished: finished,
                    resultCount: items.count
                ))
            }

            function(renderer, selector, items, topic, NSNumber(value: startPage), NSNumber(value: endPage), NSNumber(value: finished), block)
        }
    }

    private static func decodeMessageActions(from rawActions: NSDictionary?) -> [Int: TopicPageMessageActions] {
        guard let rawEntries = rawActions as? [AnyHashable: Any] else {
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

            result[index] = TopicPageMessageActions(
                quoteURL: urlValue(in: entry, key: MessageActionKey.quoteURL),
                profileURL: urlValue(in: entry, key: MessageActionKey.profileURL),
                privateMessageURL: urlValue(in: entry, key: MessageActionKey.privateMessageURL),
                avatarImagePath: stringValue(in: entry, key: MessageActionKey.avatarImagePath),
                postID: stringValue(in: entry, key: MessageActionKey.postID),
                editURL: urlValue(in: entry, key: MessageActionKey.editURL),
                favoriteURL: urlValue(in: entry, key: MessageActionKey.favoriteURL),
                alertURL: urlValue(in: entry, key: MessageActionKey.alertURL),
                permalinkURL: urlValue(in: entry, key: MessageActionKey.permalinkURL),
                authorName: stringValue(in: entry, key: MessageActionKey.authorName),
                quoteJS: stringValue(in: entry, key: MessageActionKey.quoteJS),
                isOwnMessage: boolValue(in: entry, key: MessageActionKey.isOwnMessage),
                canBeFavorite: boolValue(in: entry, key: MessageActionKey.canBeFavorite),
                isPrivateCategory: boolValue(in: entry, key: MessageActionKey.isPrivateCategory),
                canAQ: boolValue(in: entry, key: MessageActionKey.canAQ),
                canBookmark: boolValue(in: entry, key: MessageActionKey.canBookmark),
                canDelete: boolValue(in: entry, key: MessageActionKey.canDelete),
                topicID: stringValue(in: entry, key: MessageActionKey.topicID),
                topicCategory: stringValue(in: entry, key: MessageActionKey.topicCategory),
                topicTitle: stringValue(in: entry, key: MessageActionKey.topicTitle)
            )
        }

        return result
    }

    private static func urlValue(in dictionary: [AnyHashable: Any], key: String) -> URL? {
        guard let rawValue = stringValue(in: dictionary, key: key) else {
            return nil
        }
        return URL(string: rawValue)
    }

    private static func stringValue(in dictionary: [AnyHashable: Any], key: String) -> String? {
        guard let rawValue = dictionary[key] as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolValue(in dictionary: [AnyHashable: Any], key: String) -> Bool {
        if let number = dictionary[key] as? NSNumber {
            return number.boolValue
        }
        guard let string = stringValue(in: dictionary, key: key)?.lowercased() else {
            return false
        }
        return string == "1" || string == "true" || string == "yes"
    }
}
