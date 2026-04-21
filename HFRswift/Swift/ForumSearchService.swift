//
//  ForumSearchService.swift
//  SuperHFRplus
//
//  Swift bridge for the legacy global forum search parser.
//

import Foundation

struct ForumSearchParams: Equatable {
    enum SearchType: String, CaseIterable, Identifiable {
        case allWords
        case anyWord
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .allWords: return "Tous les mots"
            case .anyWord: return "Au moins un mot"
            case .advanced: return "Avancé"
            }
        }

        var legacyValue: String {
            switch self {
            case .allWords: return "1"
            case .anyWord: return "2"
            case .advanced: return "0"
            }
        }
    }

    enum SearchScope: String, CaseIterable, Identifiable {
        case titleAndContent
        case title
        case content

        var id: String { rawValue }

        var title: String {
            switch self {
            case .titleAndContent: return "Titre et contenu"
            case .title: return "Titre"
            case .content: return "Contenu"
            }
        }

        var legacyValue: String {
            switch self {
            case .titleAndContent: return "3"
            case .title: return "1"
            case .content: return "0"
            }
        }
    }

    enum DateRange: String, CaseIterable, Identifiable {
        case fromBeginning
        case fiveYears
        case oneYear

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fromBeginning: return "Début"
            case .fiveYears: return "5 ans"
            case .oneYear: return "1 an"
            }
        }

        var legacyValue: String {
            switch self {
            case .fromBeginning: return "2"
            case .fiveYears, .oneYear: return "1"
            }
        }

        var yearOffset: Int? {
            switch self {
            case .fromBeginning: return nil
            case .fiveYears: return -5
            case .oneYear: return -1
            }
        }
    }

    var searchText: String
    var categoryID: String
    var searchType: SearchType
    var searchScope: SearchScope
    var dateRange: DateRange

    static let empty = ForumSearchParams(
        searchText: "",
        categoryID: "13",
        searchType: .allWords,
        searchScope: .titleAndContent,
        dateRange: .fromBeginning
    )

    var isSubmittable: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func legacyDictionary(now: Date = Date(), calendar: Calendar = .current) -> [String: String] {
        var dictionary: [String: String] = [
            "search": searchText,
            "cat": categoryID,
            "searchtype": searchType.legacyValue,
            "titre": searchScope.legacyValue,
            "daterange": dateRange.legacyValue
        ]

        if let yearOffset = dateRange.yearOffset,
           let date = calendar.date(byAdding: .year, value: yearOffset, to: now) {
            let components = calendar.dateComponents([.day, .month, .year], from: date)
            dictionary["jour"] = String(format: "%02d", components.day ?? 1)
            dictionary["mois"] = String(format: "%02d", components.month ?? 1)
            dictionary["annee"] = String(format: "%04d", components.year ?? 2000)
        }

        return dictionary
    }
}

struct ForumSearchPageInfo: Equatable {
    let currentURL: String?
    let nextPageURL: String?
    let previousPageURL: String?
    let firstPageURL: String?
    let lastPageURL: String?
    let categoryID: String?
    let pageNumber: Int
    let firstPageNumber: Int
    let lastPageNumber: Int
    let resultCount: Int

    static let empty = ForumSearchPageInfo(
        currentURL: nil,
        nextPageURL: nil,
        previousPageURL: nil,
        firstPageURL: nil,
        lastPageURL: nil,
        categoryID: nil,
        pageNumber: 1,
        firstPageNumber: 1,
        lastPageNumber: 1,
        resultCount: 0
    )

    init(raw: NSDictionary?) {
        self.currentURL = Self.string(raw?["currentURL"])
        self.nextPageURL = Self.string(raw?["nextPageURL"])
        self.previousPageURL = Self.string(raw?["previousPageURL"])
        self.firstPageURL = Self.string(raw?["firstPageURL"])
        self.lastPageURL = Self.string(raw?["lastPageURL"])
        self.categoryID = Self.string(raw?["cat"])
        self.pageNumber = Self.integer(raw?["pageNumber"], fallback: 1)
        self.firstPageNumber = Self.integer(raw?["firstPageNumber"], fallback: 1)
        self.lastPageNumber = Self.integer(raw?["lastPageNumber"], fallback: 1)
        self.resultCount = Self.integer(raw?["resultCount"], fallback: 0)
    }

    private init(
        currentURL: String?,
        nextPageURL: String?,
        previousPageURL: String?,
        firstPageURL: String?,
        lastPageURL: String?,
        categoryID: String?,
        pageNumber: Int,
        firstPageNumber: Int,
        lastPageNumber: Int,
        resultCount: Int
    ) {
        self.currentURL = currentURL
        self.nextPageURL = nextPageURL
        self.previousPageURL = previousPageURL
        self.firstPageURL = firstPageURL
        self.lastPageURL = lastPageURL
        self.categoryID = categoryID
        self.pageNumber = pageNumber
        self.firstPageNumber = firstPageNumber
        self.lastPageNumber = lastPageNumber
        self.resultCount = resultCount
    }

    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return string
    }

    private static func integer(_ value: Any?, fallback: Int) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String, let integer = Int(string) {
            return integer
        }
        return fallback
    }
}

struct ForumSearchResult {
    let topics: [Topic]
    let pageInfo: ForumSearchPageInfo

    var countText: String {
        topics.count == 1 ? "1 résultat" : "\(topics.count) résultats"
    }
}

enum ForumSearchError: LocalizedError {
    case workerUnavailable
    case emptyQuery
    case cancelled
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .workerUnavailable:
            return "Le module de recherche n'est pas disponible."
        case .emptyQuery:
            return "Renseigne une recherche pour continuer."
        case .cancelled:
            return "Recherche annulée."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

protocol ForumSearchServicing: AnyObject {
    func search(params: ForumSearchParams) async -> Result<ForumSearchResult, ForumSearchError>
    func fetchPage(urlString: String) async -> Result<ForumSearchResult, ForumSearchError>
    func cancel()
}

final class ObjCForumSearchService: ForumSearchServicing {
    private var activeWorker: NSObject?

    func search(params: ForumSearchParams) async -> Result<ForumSearchResult, ForumSearchError> {
        guard params.isSubmittable else {
            return .failure(.emptyQuery)
        }
        return await perform(selectorName: "performForumSearchWithParams:completion:", argument: params.legacyDictionary() as NSDictionary)
    }

    func fetchPage(urlString: String) async -> Result<ForumSearchResult, ForumSearchError> {
        return await perform(selectorName: "fetchForumSearchPageURL:completion:", argument: urlString as NSString)
    }

    func cancel() {
        guard let worker = activeWorker else { return }
        let selector = NSSelectorFromString("cancelForumSearch")
        guard worker.responds(to: selector) else { return }
        typealias Function = @convention(c) (AnyObject, Selector) -> Void
        let implementation = worker.method(for: selector)
        let function = unsafeBitCast(implementation, to: Function.self)
        function(worker, selector)
    }

    private func perform(selectorName: String, argument: NSObject) async -> Result<ForumSearchResult, ForumSearchError> {
        guard let worker = LegacyLoaderRuntime.instantiateController(named: "TopicsSearchViewController") else {
            return .failure(.workerUnavailable)
        }

        let selector = NSSelectorFromString(selectorName)
        guard worker.responds(to: selector) else {
            return .failure(.workerUnavailable)
        }

        activeWorker = worker
        return await withCheckedContinuation { continuation in
            typealias CompletionBlock = @convention(block) (NSArray?, NSDictionary?, NSError?) -> Void
            typealias Function = @convention(c) (AnyObject, Selector, NSObject, CompletionBlock) -> Void
            let implementation = worker.method(for: selector)
            let function = unsafeBitCast(implementation, to: Function.self)
            let block: CompletionBlock = { topics, pageInfo, error in
                self.activeWorker = nil
                if let error {
                    if (error as NSError).domain == NSURLErrorDomain,
                       (error as NSError).code == NSURLErrorCancelled {
                        continuation.resume(returning: .failure(.cancelled))
                    } else {
                        continuation.resume(returning: .failure(.underlying(error)))
                    }
                    return
                }
                let result = ForumSearchResult(
                    topics: topics as? [Topic] ?? [],
                    pageInfo: ForumSearchPageInfo(raw: pageInfo)
                )
                continuation.resume(returning: .success(result))
            }
            function(worker, selector, argument, block)
        }
    }
}
