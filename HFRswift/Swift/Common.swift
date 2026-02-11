//
//  Common.swift
//  SuperHFRplus
//
//  Created by Bruno ARENE on 9/2/25.
//

import Foundation

extension Favorite: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

extension Topic: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

typealias FavoritesLoadCompletion = ([Favorite]?, Error?) -> Void
typealias TopicsLoadCompletion = ([Topic]?, Error?) -> Void

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

struct TopicPageContent {
    let html: String
    let topicAnswerURL: URL?
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
            completion(.success(TopicPageContent(html: html, topicAnswerURL: answerURL)))
        }
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
        let createdFileURL = offlineStorage.createHtmlFileInCache(for: nil, withContent: html)
        let cacheDirectoryURL = offlineStorage.cacheURL()
        return TopicPageRenderOutput(fileURL: createdFileURL, readAccessURL: cacheDirectoryURL)
    }
}
