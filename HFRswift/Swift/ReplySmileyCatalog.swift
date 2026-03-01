import Foundation

enum ReplySmileyImageSource: Equatable {
    case bundledGIF(filename: String)
    case remote(URL)
    case none
}

struct ReplySmiley: Identifiable, Equatable {
    let code: String
    let imageSource: ReplySmileyImageSource

    var id: String {
        "\(code)|\(imageSourceKey)"
    }

    private var imageSourceKey: String {
        switch imageSource {
        case .bundledGIF(let filename):
            return "bundle:\(filename)"
        case .remote(let url):
            return "remote:\(url.absoluteString)"
        case .none:
            return "none"
        }
    }
}

protocol ReplySmileyCatalogLoading {
    func loadDefaultSmileys() -> [ReplySmiley]
    func loadFavoriteSmileys() -> [ReplySmiley]
}

enum ReplySmileyCacheBridge {
    static func favoriteSmileyEntries() -> [[String: Any]] {
        guard let sharedCache = sharedCacheObject else {
            return []
        }

        let forumFavorites = sharedCache.value(forKey: "arrFavoritesSmileysForum") as? [[String: Any]] ?? []
        let appFavorites = sharedCache.value(forKey: "arrFavoritesSmileysApp") as? [[String: Any]] ?? []
        return forumFavorites + appFavorites
    }

    static func updateForumFavorites(_ entries: [[String: String]]) {
        guard let sharedCache = sharedCacheObject else {
            return
        }

        let normalizedEntries = entries.compactMap { entry -> [String: String]? in
            guard let source = entry["source"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let code = entry["code"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty,
                  !code.isEmpty else {
                return nil
            }
            return ["source": source, "code": code]
        }

        sharedCache.setValue(NSMutableArray(array: normalizedEntries), forKey: "arrFavoritesSmileysForum")
    }

    private static var sharedCacheObject: AnyObject? {
        guard let cacheClass = NSClassFromString("SmileyCache") as? NSObject.Type else {
            return nil
        }
        let sharedSelector = NSSelectorFromString("shared")
        guard cacheClass.responds(to: sharedSelector),
              let unmanaged = cacheClass.perform(sharedSelector) else {
            return nil
        }
        return unmanaged.takeUnretainedValue() as AnyObject
    }
}

final class BundleReplySmileyCatalogLoader: ReplySmileyCatalogLoading {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadDefaultSmileys() -> [ReplySmiley] {
        guard let path = bundle.path(forResource: "commonsmile", ofType: "plist"),
              let rawEntries = NSArray(contentsOfFile: path) as? [[String: Any]] else {
            return []
        }

        return rawEntries.compactMap { entry in
            let isEditorVisible: Bool
            if let flag = entry["editor"] as? Bool {
                isEditorVisible = flag
            } else if let flag = entry["editor"] as? NSNumber {
                isEditorVisible = flag.boolValue
            } else {
                isEditorVisible = false
            }
            guard isEditorVisible else { return nil }
            guard let code = entry["code"] as? String,
                  let resourceName = entry["resource"] as? String else {
                return nil
            }
            return ReplySmiley(code: code, imageSource: .bundledGIF(filename: resourceName))
        }
    }

    func loadFavoriteSmileys() -> [ReplySmiley] {
        ReplySmileyCacheBridge.favoriteSmileyEntries().compactMap { entry in
            guard let code = entry["code"] as? String else { return nil }
            let sourceString = entry["source"] as? String
            let sourceURL = sourceString.flatMap(URL.init(string:))
            if let sourceURL {
                return ReplySmiley(code: code, imageSource: .remote(sourceURL))
            }
            return ReplySmiley(code: code, imageSource: .none)
        }
    }
}
