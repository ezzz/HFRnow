//
//  TopicSearchService.swift
//  SuperHFRplus
//
//  Intra-topic search: POSTs the search form to /transsearch.php and
//  returns the redirected URL pointing to the filtered results page.
//

import Foundation

struct TopicSearchParams: Equatable {
    var hashCheck: String?
    var p: String?
    var post: String?
    var cat: String?
    var firstnum: String?
    var currentnum: String?
    var word: String
    var spseudo: String
    var filterEnabled: Bool
    var fromFirstPost: Bool

    static let empty = TopicSearchParams(
        hashCheck: nil,
        p: nil,
        post: nil,
        cat: nil,
        firstnum: nil,
        currentnum: nil,
        word: "",
        spseudo: "",
        filterEnabled: false,
        fromFirstPost: true
    )

    var isSubmittable: Bool {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPseudo = spseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedWord.isEmpty || !trimmedPseudo.isEmpty
    }

    /// Builds the form dictionary ready for POST to /transsearch.php.
    /// Mirrors the legacy searchSubmit behavior: pagination fields are included
    /// only when fromFirstPost == false.
    func formDictionary() -> [String: String] {
        var dict: [String: String] = [:]
        if let hashCheck, !hashCheck.isEmpty { dict["hash_check"] = hashCheck }
        if let p, !p.isEmpty { dict["p"] = p }
        if let post, !post.isEmpty { dict["post"] = post }
        if let cat, !cat.isEmpty { dict["cat"] = cat }

        dict["word"] = word
        dict["spseudo"] = spseudo
        if filterEnabled {
            dict["filter"] = "1"
        }

        if !fromFirstPost {
            if let firstnum, !firstnum.isEmpty { dict["firstnum"] = firstnum }
            if let currentnum, !currentnum.isEmpty { dict["currentnum"] = currentnum }
        }
        return dict
    }

    /// Builds a TopicSearchParams from the controller's parsed form dictionary.
    /// `tmp_firstnum` / `tmp_currentnum` (set by legacy setupIntrSearch) are used
    /// so we remember the original pagination even when fromFirstPost is toggled.
    static func fromLegacyDictionary(_ legacy: [String: String]) -> TopicSearchParams {
        let word = legacy["word"] ?? ""
        let spseudo = legacy["spseudo"] ?? ""
        let filter = (legacy["filter"].map { !$0.isEmpty && $0 != "0" }) ?? false
        let firstnum = legacy["firstnum"] ?? legacy["tmp_firstnum"]
        let currentnum = legacy["currentnum"] ?? legacy["tmp_currentnum"]
        let fromFirstPost = (legacy["currentnum"] == nil) && (legacy["firstnum"] == nil)
        return TopicSearchParams(
            hashCheck: legacy["hash_check"],
            p: legacy["p"],
            post: legacy["post"],
            cat: legacy["cat"],
            firstnum: firstnum,
            currentnum: currentnum,
            word: word,
            spseudo: spseudo,
            filterEnabled: filter,
            fromFirstPost: fromFirstPost
        )
    }
}

enum TopicSearchError: LocalizedError {
    case controllerUnavailable
    case emptyQuery
    case noResultURL
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .controllerUnavailable:
            return "Le module de recherche n'est pas disponible."
        case .emptyQuery:
            return "Renseigne un mot-clé ou un pseudo pour lancer la recherche."
        case .noResultURL:
            return "Aucun résultat n'a été trouvé."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

protocol TopicSearchServicing {
    func performSearch(params: TopicSearchParams) async -> Result<URL, TopicSearchError>
}

final class ObjCTopicSearchService: TopicSearchServicing {
    private let controller: NSObject?

    init(controller: NSObject? = LegacyTopicWorkerRuntime.instantiate()) {
        self.controller = controller
    }

    func performSearch(params: TopicSearchParams) async -> Result<URL, TopicSearchError> {
        guard params.isSubmittable else {
            return .failure(.emptyQuery)
        }
        guard let controller else {
            return .failure(.controllerUnavailable)
        }

        let selector = NSSelectorFromString(LegacyTopicWorkerRuntime.SelectorName.performSearch)
        guard controller.responds(to: selector) else {
            return .failure(.controllerUnavailable)
        }

        let formDict = params.formDictionary()

        return await withCheckedContinuation { continuation in
            typealias CompletionBlock = @convention(block) (NSString?, NSError?) -> Void
            typealias Function = @convention(c) (AnyObject, Selector, NSDictionary, CompletionBlock) -> Void
            let implementation = controller.method(for: selector)
            let function = unsafeBitCast(implementation, to: Function.self)
            let block: CompletionBlock = { rawURL, error in
                if let error {
                    continuation.resume(returning: .failure(.underlying(error)))
                    return
                }
                guard let rawString = rawURL as String?,
                      !rawString.isEmpty,
                      let url = URL(string: rawString) else {
                    continuation.resume(returning: .failure(.noResultURL))
                    return
                }
                continuation.resume(returning: .success(url))
            }
            function(controller, selector, formDict as NSDictionary, block)
        }
    }
}

/// Carries the active search state across pushed MessagesView instances.
/// When non-nil, the view renders in "search results" mode: bottom toolbar
/// becomes a "next results" control, title shows "Recherche", menu offers
/// re-opening the search sheet pre-filled with these params.
struct TopicSearchContext: Equatable {
    /// Params used to submit the initial search — preserved so the sheet can be re-opened pre-filled.
    var params: TopicSearchParams
    /// URL returned by the last /transsearch.php redirect. Used to load the current results page.
    var resultURL: URL
}
